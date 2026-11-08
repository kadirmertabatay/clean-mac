import Foundation

/// Copies files to another disk, verifies each copy with SHA-256 and records where every file went.
/// Removing the originals is left to the caller (only for verified files).
enum ArchiveEngine {
    struct Result {
        var verified: [(source: FileEntry, destination: URL)] = []
        var failed: [(name: String, reason: String)] = []
    }

    enum Problem: Error, LocalizedError {
        case sameVolume
        var errorDescription: String? { L("The destination is on the same disk; archiving won’t free any space. Choose an external disk.") }
    }

    static func isSameVolume(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let va = (try? a.resourceValues(forKeys: key))?.volumeIdentifier as? NSObject,
              let vb = (try? b.resourceValues(forKeys: key))?.volumeIdentifier as? NSObject else { return false }
        return va.isEqual(vb)
    }

    /// Keeps the source structure at the destination: ~/Movies/a.mov → <destination>/CleanMac Archive/Movies/a.mov
    static func destination(for source: URL, in root: URL) -> URL {
        let home = Paths.home.path
        var rel = source.path
        if rel.hasPrefix(home + "/") { rel = String(rel.dropFirst(home.count + 1)) } else { rel = String(rel.drop { $0 == "/" }) }
        var dest = root.appendingPathComponent("CleanMac Archive").appendingPathComponent(rel)
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            let base = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension
            dest = dest.deletingLastPathComponent().appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            n += 1
        }
        return dest
    }

    static func archive(_ files: [FileEntry], to root: URL, requireDifferentVolume: Bool = true,
                        progress: @escaping (Int, String) -> Void) throws -> Result {
        if requireDifferentVolume, let first = files.first, isSameVolume(first.url, root) { throw Problem.sameVolume }
        let fm = FileManager()
        var result = Result()
        var log = ""
        for (i, f) in files.enumerated() {
            if Task.isCancelled { break }
            progress(i, f.name)
            let dest = destination(for: f.url, in: root)
            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: f.url, to: dest)
                guard let a = DuplicateFinder.fullHash(f.url), let b = DuplicateFinder.fullHash(dest), a == b else {
                    try? fm.removeItem(at: dest)
                    result.failed.append((f.name, L("verification failed")))
                    continue
                }
                result.verified.append((f, dest))
                log += "\(ISO8601DateFormatter().string(from: Date()))\t\(f.url.path)\t→\t\(dest.path)\n"
            } catch {
                result.failed.append((f.name, error.localizedDescription))
            }
        }
        progress(files.count, "")
        if !log.isEmpty {
            let logURL = root.appendingPathComponent("CleanMac Archive/archive-log.tsv")
            if let h = try? FileHandle(forWritingTo: logURL) {
                h.seekToEndOfFile()
                h.write(Data(log.utf8))
                try? h.close()
            } else {
                try? Data(("date\toriginal location\t\tdestination\n" + log).utf8).write(to: logURL)
            }
        }
        return result
    }
}
