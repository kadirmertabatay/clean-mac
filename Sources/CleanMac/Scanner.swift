import Foundation

struct ScanProgress {
    var files: Int
    var bytes: Int64
    var currentPath: String
}

struct ScanResult {
    let root: FileNode
    let files: [FileEntry]
    let devArtifacts: [FileNode]
    let totalFiles: Int
    let unreadable: Int
    let duration: TimeInterval
}

/// Paralel çalışan tarayıcıların ortak sayaçları ve iptal bayrağı.
final class ScanCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var files = 0
    private var bytes: Int64 = 0
    private var lastReport = Date.distantPast
    private var cancelled = false
    private let onProgress: (ScanProgress) -> Void

    init(onProgress: @escaping (ScanProgress) -> Void) {
        self.onProgress = onProgress
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    func add(files f: Int, bytes b: Int64, at path: String, force: Bool = false) {
        lock.lock()
        files += f
        bytes += b
        let now = Date()
        let shouldReport = force || now.timeIntervalSince(lastReport) > 0.1
        if shouldReport { lastReport = now }
        let snapshot = ScanProgress(files: files, bytes: bytes, currentPath: path)
        lock.unlock()
        if shouldReport { onProgress(snapshot) }
    }
}

/// Bir klasörü özyinelemeli olarak tarar, boyut ağacı ve büyük dosya listesi çıkarır.
/// Üst düzey alt klasörler paralel taranır.
final class DiskScanner {
    /// Bu boyutun üzerindeki dosyalar tek tek tutulur; küçükler klasör başına toplanır.
    static let trackThreshold: Int64 = 1_000_000

    static let devArtifactNames: Set<String> = [
        "node_modules", ".venv", "venv", "Pods", ".next", ".nuxt", ".gradle",
        "DerivedData", ".dart_tool", ".turbo", ".parcel-cache", ".angular",
    ]

    /// Başka birimleri ve sanal dosya sistemlerini tekrar saymamak için atlanan yollar.
    /// /.nofollow, /.resolve ve /.vol tüm diski yeniden gösteren sanal yollardır.
    static let excludedPaths: Set<String> = ["/Volumes", "/System/Volumes", "/dev", "/net", "/home",
                                             "/.nofollow", "/.resolve", "/.vol"]

    static let protectedRoots = ["/System", "/usr", "/bin", "/sbin", "/Library", "/Applications", "/opt",
                                 "/etc", "/private/etc", "/private/var/db", "/private/var/vm", "/var/db", "/var/vm"]

    fileprivate static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey, .contentAccessDateKey,
    ]
    fileprivate static let keySet = Set(keys)

    private let coordinator: ScanCoordinator

    convenience init(onProgress: @escaping (ScanProgress) -> Void) {
        self.init(coordinator: ScanCoordinator(onProgress: onProgress))
    }

    init(coordinator: ScanCoordinator) {
        self.coordinator = coordinator
    }

    static let protectedRootSet = Set(protectedRoots)

    static func isProtectedPath(_ path: String) -> Bool {
        if protectedRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        return path.contains("/Library/") || path.hasSuffix("/Library")
    }

    /// Kökün kendisi, sembolik bağlantısı çözülmüş hâli ya da bir üst klasörü korumalıysa (veya paketse) true.
    static func isProtectedRoot(_ root: URL) -> Bool {
        let resolved = root.resolvingSymlinksInPath()
        if isProtectedPath(root.path) || isProtectedPath(resolved.path) { return true }
        var url = resolved
        while url.path != "/" {
            if (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true { return true }
            url = url.deletingLastPathComponent()
        }
        return false
    }

    /// Kökten bu derinliğe kadar klasörler ayrı işlere bölünür; daha derindekiler tek işte özyinelemeli taranır.
    static let splitDepth = 4

    func scan(root: URL) -> ScanResult {
        let start = Date()
        let rootName = root.path == "/" ? (DiskInfo.current()?.name ?? "Macintosh HD") : root.abbreviatedPath
        let rootNode = FileNode(url: root, name: rootName, isDirectory: true)
        let queue = JobQueue(SubdirJob(node: rootNode, protected: Self.isProtectedRoot(root),
                                       inArtifact: false, isArtifact: false, depth: 0))

        // Her çekirdek kuyruktan iş çeker; sığ klasörler yeni işlere bölünür, böylece tek bir
        // büyük klasör (ör. ~/Library) tüm taramayı tek iş parçacığına mahkûm etmez.
        let workerCount = max(ProcessInfo.processInfo.activeProcessorCount, 2)
        let workers = (0..<workerCount).map { _ in Worker(coordinator: coordinator) }
        DispatchQueue.concurrentPerform(iterations: workerCount) { i in
            let w = workers[i]
            while let job = queue.next() {
                var children: [SubdirJob] = []
                if coordinator.isCancelled {
                    // Kuyruğu boşaltmak için işi tamamlanmış say.
                } else if job.depth < Self.splitDepth {
                    children = w.scanDirectory(job.node, protected: job.protected, inArtifact: job.inArtifact, recurse: false)
                        .map { $0.withDepth(job.depth + 1) }
                    w.splitJobs.append(job)
                } else {
                    w.scanSubtree(job.node, protected: job.protected, inArtifact: job.inArtifact)
                    if job.isArtifact && job.node.size > 0 { w.artifacts.append(job.node) }
                }
                queue.finish(adding: children)
            }
        }

        // Bölünen klasörlerin boyutlarını en derinden köke doğru topla.
        let split = workers.flatMap(\.splitJobs).sorted { $0.depth > $1.depth }
        var artifacts = workers.flatMap(\.artifacts)
        for job in split {
            let node = job.node
            for c in node.children where c.isDirectory {
                node.size += c.size
                node.fileCount += c.fileCount
            }
            node.children.sort { $0.size > $1.size }
            if job.isArtifact && node.size > 0 { artifacts.append(node) }
        }

        coordinator.add(files: 0, bytes: 0, at: root.path, force: true)
        return ScanResult(root: rootNode, files: workers.flatMap(\.files), devArtifacts: artifacts,
                          totalFiles: workers.reduce(0) { $0 + $1.totalFiles },
                          unreadable: workers.reduce(0) { $0 + $1.unreadable },
                          duration: Date().timeIntervalSince(start))
    }

    struct SubdirJob {
        let node: FileNode
        let protected: Bool
        let inArtifact: Bool
        let isArtifact: Bool
        var depth = 0

        func withDepth(_ d: Int) -> SubdirJob {
            var j = self
            j.depth = d
            return j
        }
    }

    /// İş parçacıkları arasında paylaşılan iş kuyruğu. Kuyruk boş ve çalışan iş kalmadığında next() nil döner.
    final class JobQueue: @unchecked Sendable {
        private let cond = NSCondition()
        private var jobs: [SubdirJob]
        private var inFlight = 0

        init(_ first: SubdirJob) {
            jobs = [first]
        }

        func next() -> SubdirJob? {
            cond.lock()
            defer { cond.unlock() }
            while jobs.isEmpty {
                if inFlight == 0 { return nil }
                cond.wait()
            }
            inFlight += 1
            return jobs.removeLast()
        }

        func finish(adding newJobs: [SubdirJob]) {
            cond.lock()
            jobs.append(contentsOf: newJobs)
            inFlight -= 1
            cond.broadcast()
            cond.unlock()
        }
    }

    final class Worker {
        let coordinator: ScanCoordinator
        let fm = FileManager()
        var files: [FileEntry] = []
        var artifacts: [FileNode] = []
        var splitJobs: [SubdirJob] = []
        var totalFiles = 0
        var unreadable = 0
        private var pendingFiles = 0
        private var pendingBytes: Int64 = 0

        init(coordinator: ScanCoordinator) {
            self.coordinator = coordinator
        }

        func scanSubtree(_ node: FileNode, protected: Bool, inArtifact: Bool) {
            _ = scanDirectory(node, protected: protected, inArtifact: inArtifact, recurse: true)
            flush(node.url.path)
        }

        /// `recurse` false ise alt klasörler taranmaz, iş olarak döndürülür (kök için).
        func scanDirectory(_ node: FileNode, protected: Bool, inArtifact: Bool, recurse: Bool) -> [SubdirJob] {
            if coordinator.isCancelled { return [] }
            let contents: [URL]
            do {
                contents = try fm.contentsOfDirectory(at: node.url, includingPropertiesForKeys: DiskScanner.keys, options: [])
            } catch {
                unreadable += 1
                return []
            }

            var jobs: [SubdirJob] = []
            var smallSize: Int64 = 0
            var smallCount = 0
            for child in contents {
                if coordinator.isCancelled { return [] }
                guard let rv = try? child.resourceValues(forKeys: DiskScanner.keySet) else { continue }
                if rv.isSymbolicLink == true { continue }

                if rv.isDirectory == true {
                    // Bazı sanal yollar sonda "/" ile döner (ör. "/.nofollow/").
                    var childPath = child.path
                    if childPath.count > 1, childPath.hasSuffix("/") { childPath.removeLast() }
                    if DiskScanner.excludedPaths.contains(childPath) { continue }
                    let isPackage = rv.isPackage == true
                    let childProtected = protected || isPackage || child.lastPathComponent == "Library"
                        || DiskScanner.protectedRootSet.contains(childPath)
                    let isArtifact = !inArtifact && !childProtected
                        && DiskScanner.devArtifactNames.contains(child.lastPathComponent)
                    let sub = FileNode(url: child, isDirectory: true, isPackage: isPackage)
                    sub.parent = node
                    node.children.append(sub)
                    if recurse {
                        _ = scanDirectory(sub, protected: childProtected, inArtifact: inArtifact || isArtifact, recurse: true)
                        node.size += sub.size
                        node.fileCount += sub.fileCount
                        if isArtifact && sub.size > 0 { artifacts.append(sub) }
                    } else {
                        jobs.append(SubdirJob(node: sub, protected: childProtected,
                                              inArtifact: inArtifact || isArtifact, isArtifact: isArtifact))
                    }
                } else {
                    let size = Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? rv.fileSize ?? 0)
                    totalFiles += 1
                    pendingFiles += 1
                    pendingBytes += size
                    node.size += size
                    node.fileCount += 1
                    if size >= DiskScanner.trackThreshold {
                        let f = FileNode(url: child, isDirectory: false, size: size, fileCount: 1)
                        f.parent = node
                        node.children.append(f)
                        files.append(FileEntry(url: child, size: size, modified: rv.contentModificationDate,
                                               accessed: rv.contentAccessDate, isProtected: protected))
                    } else {
                        smallSize += size
                        smallCount += 1
                    }
                    if pendingFiles >= 256 { flush(node.url.path) }
                }
            }

            if smallCount > 0 {
                let agg = FileNode(url: node.url.appendingPathComponent(".__kucuk_dosyalar__"),
                                   name: "\(smallCount) küçük dosya (< 1 MB)", isDirectory: false,
                                   isAggregate: true, size: smallSize, fileCount: smallCount)
                agg.parent = node
                node.children.append(agg)
            }
            if recurse { node.children.sort { $0.size > $1.size } }
            if !recurse { flush(node.url.path) }
            return jobs
        }

        private func flush(_ path: String) {
            guard pendingFiles > 0 else { return }
            coordinator.add(files: pendingFiles, bytes: pendingBytes, at: path)
            pendingFiles = 0
            pendingBytes = 0
        }
    }

    /// Bir dosya ya da klasörün diskte kapladığı toplam alan.
    static func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let rv = try? url.resourceValues(forKeys: keys) else { return 0 }
        if rv.isSymbolicLink == true { return 0 }
        if rv.isDirectory != true { return Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0) }
        guard let en = FileManager().enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [],
                                                errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        while let f = en.nextObject() as? URL {
            if Task.isCancelled { break }
            guard let r = try? f.resourceValues(forKeys: keys), r.isDirectory != true else { continue }
            total += Int64(r.totalFileAllocatedSize ?? r.fileAllocatedSize ?? 0)
        }
        return total
    }
}
