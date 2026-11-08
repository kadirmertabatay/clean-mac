import CryptoKit
import Foundation

/// Bir taramanın karşılaştırma için saklanan özeti (klasörler 3 seviyeye kadar, 100 MB üzeri dosyalar).
struct ScanSnapshot: Codable {
    let root: String
    let date: Date
    let total: Int64
    let dirs: [String: Int64]
    let bigFiles: [String: Int64]

    static let maxDepth = 3
    static let minDirSize: Int64 = 10_000_000
    static let minFileSize: Int64 = 100_000_000

    init(root: String, date: Date, total: Int64, dirs: [String: Int64], bigFiles: [String: Int64]) {
        self.root = root
        self.date = date
        self.total = total
        self.dirs = dirs
        self.bigFiles = bigFiles
    }

    init(tree: FileNode, files: [FileEntry], date: Date = Date()) {
        var dirs: [String: Int64] = [:]
        func walk(_ n: FileNode, depth: Int) {
            guard depth <= Self.maxDepth else { return }
            for c in n.children where c.isDirectory && c.size >= Self.minDirSize {
                dirs[c.url.path] = c.size
                walk(c, depth: depth + 1)
            }
        }
        walk(tree, depth: 1)
        self.init(root: tree.url.path, date: date, total: tree.size, dirs: dirs,
                  bigFiles: Dictionary(files.filter { $0.size >= Self.minFileSize }.map { ($0.id, $0.size) }) { a, _ in a })
    }
}

struct GrowthItem: Identifiable {
    let path: String
    let old: Int64
    let new: Int64
    var id: String { path }
    var delta: Int64 { new - old }
    var url: URL { URL(fileURLWithPath: path) }
}

struct GrowthDiff {
    let from: Date
    let to: Date
    let totalDelta: Int64
    let grown: [GrowthItem]
    let shrunk: [GrowthItem]
    let newFiles: [GrowthItem]
    let goneFiles: [GrowthItem]

    /// İki özet arasındaki farklar; `minDelta` altındaki değişimler gürültü sayılır.
    static func compute(old: ScanSnapshot, new: ScanSnapshot, minDelta: Int64 = 50_000_000) -> GrowthDiff {
        // Bir tarafta olmayan klasör ya yeni/silinmiş ya da 10 MB eşiğinin altındadır; 0 saymanın hatası eşikten küçüktür.
        let changes = Set(old.dirs.keys).union(new.dirs.keys)
            .map { GrowthItem(path: $0, old: old.dirs[$0] ?? 0, new: new.dirs[$0] ?? 0) }
            .filter { abs($0.delta) >= minDelta }
        let newFiles = new.bigFiles.filter { old.bigFiles[$0.key] == nil }
            .map { GrowthItem(path: $0.key, old: 0, new: $0.value) }
        let goneFiles = old.bigFiles.filter { new.bigFiles[$0.key] == nil }
            .map { GrowthItem(path: $0.key, old: $0.value, new: 0) }
        return GrowthDiff(from: old.date, to: new.date, totalDelta: new.total - old.total,
                          grown: changes.filter { $0.delta > 0 }.sorted { $0.delta > $1.delta },
                          shrunk: changes.filter { $0.delta < 0 }.sorted { $0.delta < $1.delta },
                          newFiles: newFiles.sorted { $0.new > $1.new },
                          goneFiles: goneFiles.sorted { $0.old > $1.old })
    }
}

/// Tarama özetlerini kök klasör başına diskte saklar (en fazla 12 tane).
struct SnapshotStore {
    let directory: URL
    static let keep = 12

    private func file(for root: String) -> URL {
        let digest = SHA256.hash(data: Data(root.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(digest).json")
    }

    func load(root: String) -> [ScanSnapshot] {
        guard let data = try? Data(contentsOf: file(for: root)),
              let list = try? JSONDecoder().decode([ScanSnapshot].self, from: data) else { return [] }
        return list.sorted { $0.date > $1.date }
    }

    func save(_ snapshot: ScanSnapshot) {
        let list = ([snapshot] + load(root: snapshot.root)).prefix(Self.keep)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Array(list)) {
            try? data.write(to: file(for: snapshot.root), options: .atomic)
        }
    }
}
