import CryptoKit
import Foundation

struct DuplicateGroup: Identifiable {
    let id: String
    let size: Int64
    var files: [FileEntry]
    var wasted: Int64 { size * Int64(max(files.count - 1, 0)) }
}

/// Aynı içeriğe sahip dosyaları bulur: boyut → baş/son 64 KB özeti → tam SHA-256.
enum DuplicateFinder {
    private static let chunk = 64 * 1024

    static func find(in entries: [FileEntry], minSize: Int64,
                     progress: @escaping (Double) -> Void) -> [DuplicateGroup] {
        // Sabit bağlantıları (aynı inode) ayıkla ve gerçek bayt boyutuna göre grupla.
        var seenInodes = Set<String>()
        var bySize: [Int64: [FileEntry]] = [:]
        for e in entries where e.size >= minSize {
            var st = stat()
            guard lstat(e.url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { continue }
            // Yalnızca bulutta duran dosyaları okumak indirmeyi tetikler; atla.
            guard (st.st_flags & UInt32(SF_DATALESS)) == 0, st.st_blocks > 0 else { continue }
            guard seenInodes.insert("\(st.st_dev):\(st.st_ino)").inserted else { continue }
            bySize[Int64(st.st_size), default: []].append(e)
        }
        let groups = bySize.filter { $0.value.count > 1 }
        let total = max(groups.values.reduce(0) { $0 + $1.count }, 1)
        var done = 0
        var lastReported = 0.0
        var result: [DuplicateGroup] = []

        for (logical, group) in groups {
            if Task.isCancelled { return [] }
            var byPartial: [String: [FileEntry]] = [:]
            for e in group {
                if let h = partialHash(e.url, size: logical) { byPartial[h, default: []].append(e) }
            }
            for (ph, candidates) in byPartial where candidates.count > 1 {
                if logical <= Int64(chunk * 2) {
                    result.append(DuplicateGroup(id: "\(logical)-\(ph)", size: candidates[0].size,
                                                 files: candidates.sorted { $0.modifiedSort < $1.modifiedSort }))
                    continue
                }
                var byFull: [String: [FileEntry]] = [:]
                for e in candidates {
                    if Task.isCancelled { return [] }
                    if let h = fullHash(e.url) { byFull[h, default: []].append(e) }
                }
                for (fh, same) in byFull where same.count > 1 {
                    result.append(DuplicateGroup(id: "\(logical)-\(fh)", size: same[0].size,
                                                 files: same.sorted { $0.modifiedSort < $1.modifiedSort }))
                }
            }
            done += group.count
            let p = Double(done) / Double(total)
            if p - lastReported >= 0.01 { lastReported = p; progress(p) }
        }
        progress(1)
        return result.sorted { $0.wasted > $1.wasted }
    }

    static func partialHash(_ url: URL, size: Int64) -> String? {
        guard !FileManager.isDataless(url.path), let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        do {
            if size <= Int64(chunk * 2) {
                if let all = try h.read(upToCount: chunk * 2) { hasher.update(data: all) }
            } else {
                if let head = try h.read(upToCount: chunk) { hasher.update(data: head) }
                try h.seek(toOffset: UInt64(size - Int64(chunk)))
                if let tail = try h.read(upToCount: chunk) { hasher.update(data: tail) }
            }
        } catch {
            return nil
        }
        return hex(hasher.finalize())
    }

    static func fullHash(_ url: URL) -> String? {
        guard !FileManager.isDataless(url.path), let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while true {
            if Task.isCancelled { return nil }
            // 1: veri okundu, 0: dosya sonu, -1: hata
            let status: Int = autoreleasepool {
                do {
                    guard let data = try h.read(upToCount: 4 << 20), !data.isEmpty else { return 0 }
                    hasher.update(data: data)
                    return 1
                } catch {
                    return -1
                }
            }
            if status == 0 { break }
            if status < 0 { return nil }
        }
        return hex(hasher.finalize())
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
