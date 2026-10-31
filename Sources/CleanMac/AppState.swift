import AppKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case assistant, overview, explorer, largeFiles, duplicates, junk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assistant: "Akıllı Asistan"
        case .overview: "Genel Bakış"
        case .explorer: "Klasör Gezgini"
        case .largeFiles: "Büyük Dosyalar"
        case .duplicates: "Tekrarlanan Dosyalar"
        case .junk: "Gereksiz Dosyalar"
        }
    }

    var icon: String {
        switch self {
        case .assistant: "sparkles"
        case .overview: "internaldrive"
        case .explorer: "folder"
        case .largeFiles: "doc.badge.arrow.up"
        case .duplicates: "doc.on.doc"
        case .junk: "trash"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    struct ScanSummary {
        let root: URL
        let totalFiles: Int
        let unreadable: Int
        let duration: TimeInterval
        let date: Date
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    static let home = FileManager.default.homeDirectoryForCurrentUser

    @Published var section: AppSection? = .assistant
    @Published private(set) var disk: DiskInfo? = DiskInfo.current()
    @Published private(set) var hasFullDiskAccess = AppState.checkFullDiskAccess()
    @Published var toast: Toast?

    // Klasör taraması
    @Published var scanRoot: URL
    @Published private(set) var rootNode: FileNode?
    @Published var currentNode: FileNode?
    @Published private(set) var files: [FileEntry] = []
    @Published private(set) var devArtifacts: [FileNode] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scanProgress: ScanProgress?
    @Published private(set) var lastScan: ScanSummary?
    private var scanTask: Task<ScanResult, Never>?

    // Tekrarlanan dosyalar
    @Published private(set) var duplicateGroups: [DuplicateGroup] = []
    @Published private(set) var isFindingDuplicates = false
    @Published private(set) var duplicateProgress: Double = 0
    @Published private(set) var duplicatesReady = false
    @Published var duplicateMinSize: Int64 = 1_000_000
    private var duplicateTask: Task<[DuplicateGroup], Never>?

    // Gereksiz dosyalar
    @Published private(set) var junkCategories: [JunkCategory] = []
    @Published private(set) var isScanningJunk = false
    @Published private(set) var junkReady = false

    // Asistan
    @Published private(set) var isAnalyzing = false
    @Published private(set) var analysisStep = ""
    @Published private(set) var lastAnalysis: Date?
    @Published var largeFilesStaleOnly = false
    @Published private(set) var isRemoving = false

    init() {
        if let custom = ProcessInfo.processInfo.environment["CLEANMAC_SCAN_ROOT"] {
            scanRoot = URL(fileURLWithPath: custom)
        } else {
            scanRoot = Self.home
        }
    }

    // MARK: - Genel

    func refreshDisk() {
        disk = DiskInfo.current()
        hasFullDiskAccess = Self.checkFullDiskAccess()
    }

    /// Tam Disk Erişimi olmadan okunamayan bir klasörü yoklar (izin istemi tetiklemez).
    static func checkFullDiskAccess() -> Bool {
        let fm = FileManager.default
        for p in ["Library/Safari", "Library/Mail", "Library/Messages"] {
            let path = home.appendingPathComponent(p).path
            if fm.fileExists(atPath: path) {
                return (try? fm.contentsOfDirectory(atPath: path)) != nil
            }
        }
        return fm.isReadableFile(atPath: "/Library/Application Support/com.apple.TCC/TCC.db")
    }

    func showToast(_ message: String, isError: Bool = false) {
        let t = Toast(message: message, isError: isError)
        toast = t
        Task {
            try? await Task.sleep(for: .seconds(4))
            if toast?.id == t.id { toast = nil }
        }
    }

    func chooseScanRoot() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = scanRoot
        panel.prompt = "Tara"
        panel.message = "Analiz edilecek klasörü seçin"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        scanRoot = url
        return true
    }

    // MARK: - Tarama

    func startScan() {
        Task { await scan() }
    }

    func cancelScan() {
        scanTask?.cancel()
        duplicateTask?.cancel()
    }

    func scan() async {
        guard !isScanning else { return }
        let root = scanRoot
        isScanning = true
        scanProgress = ScanProgress(files: 0, bytes: 0, currentPath: root.path)

        let task = Task.detached(priority: .userInitiated) { [weak self] () -> ScanResult in
            let coordinator = ScanCoordinator { p in
                Task { @MainActor in
                    guard let self, self.isScanning else { return }
                    self.scanProgress = p
                }
            }
            return await withTaskCancellationHandler {
                DiskScanner(coordinator: coordinator).scan(root: root)
            } onCancel: {
                coordinator.cancel()
            }
        }
        scanTask = task
        let result = await task.value
        scanTask = nil
        isScanning = false
        scanProgress = nil

        if task.isCancelled {
            showToast("Tarama durduruldu.")
            return
        }
        rootNode = result.root
        currentNode = result.root
        files = result.files
        devArtifacts = result.devArtifacts.sorted { $0.size > $1.size }
        duplicateGroups = []
        duplicatesReady = false
        lastScan = ScanSummary(root: root, totalFiles: result.totalFiles, unreadable: result.unreadable,
                               duration: result.duration, date: Date())
        refreshDisk()
    }

    func findDuplicates() async {
        guard !isFindingDuplicates else { return }
        if rootNode == nil { await scan() }
        guard rootNode != nil else { return }

        isFindingDuplicates = true
        duplicateProgress = 0
        let entries = files
        let minSize = duplicateMinSize
        let task = Task.detached(priority: .userInitiated) { [weak self] () -> [DuplicateGroup] in
            DuplicateFinder.find(in: entries, minSize: minSize) { p in
                Task { @MainActor in self?.duplicateProgress = p }
            }
        }
        duplicateTask = task
        let groups = await task.value
        duplicateTask = nil
        isFindingDuplicates = false
        guard !task.isCancelled else { return }
        duplicateGroups = groups
        duplicatesReady = true
    }

    func scanJunk() async {
        guard !isScanningJunk else { return }
        isScanningJunk = true
        let categories = await Task.detached(priority: .userInitiated) { await JunkScanner.scanAll() }.value
        junkCategories = categories
        junkReady = true
        isScanningJunk = false
    }

    func refreshJunkCategory(_ id: String) async {
        let category = await Task.detached(priority: .utility) { JunkScanner.scan(id: id) }.value
        if let category, let i = junkCategories.firstIndex(where: { $0.id == id }) {
            junkCategories[i] = category
        }
    }

    /// Asistanın tek tıkla çalıştırdığı tam analiz: gereksizler → klasör taraması → tekrarlar.
    func runFullAnalysis() async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        defer {
            isAnalyzing = false
            analysisStep = ""
        }
        analysisStep = "Önbellekler ve gereksiz dosyalar aranıyor…"
        await scanJunk()
        analysisStep = "\(scanRoot.abbreviatedPath) klasörü taranıyor…"
        await scan()
        guard rootNode != nil, lastScan?.root == scanRoot else { return }
        analysisStep = "Tekrarlanan dosyalar karşılaştırılıyor…"
        await findDuplicates()
        lastAnalysis = Date()
        refreshDisk()
    }

    // MARK: - Silme

    /// Öğeleri Çöp Kutusu'na taşır (ya da kalıcı siler) ve tüm listeleri günceller.
    @discardableResult
    func remove(_ targets: [RemovalTarget], permanently: Bool) async -> OperationResult {
        guard !targets.isEmpty, !isRemoving else { return OperationResult() }
        isRemoving = true
        let result = await Task.detached(priority: .userInitiated) { () -> OperationResult in
            var r = OperationResult()
            let fm = FileManager()
            for t in targets {
                do {
                    if permanently {
                        try fm.removeItem(at: t.url)
                    } else {
                        try fm.trashItem(at: t.url, resultingItemURL: nil)
                    }
                    r.succeeded.append(t.url)
                    r.freed += t.size
                } catch {
                    r.failed.append(t.url.lastPathComponent)
                }
            }
            return r
        }.value
        isRemoving = false
        // Sembolik bağlantılı yollar (/var ↔ /private/var) için iki biçimi de eşleştir.
        var removedPaths = Set<String>()
        for url in result.succeeded {
            removedPaths.insert(url.path)
            removedPaths.insert(url.resolvingSymlinksInPath().path)
            if url.path.hasPrefix("/private/") {
                removedPaths.insert(String(url.path.dropFirst("/private".count)))
            } else if ["/var/", "/tmp/", "/etc/"].contains(where: url.path.hasPrefix) {
                removedPaths.insert("/private" + url.path)
            }
        }
        applyRemoval(removedPaths)

        if !result.succeeded.isEmpty {
            let verb = permanently ? "kalıcı olarak silindi" : "Çöp Kutusu'na taşındı"
            var message = "\(result.succeeded.count) öğe \(verb) · \(result.freed.formattedBytes)"
            if !result.failed.isEmpty { message += " · \(result.failed.count) öğe atlandı (izin yok ya da kullanımda)" }
            showToast(message)
        } else if !result.failed.isEmpty {
            showToast("Öğeler silinemedi: izin yok ya da kullanımda olabilir.", isError: true)
        }
        refreshDisk()
        if junkReady { await refreshJunkCategory("trash") }
        return result
    }

    func cleanJunkCategory(_ id: String) async {
        guard let category = junkCategories.first(where: { $0.id == id }) else { return }
        let permanent = category.permanentOnly || UserDefaults.standard.bool(forKey: "permanentDelete")
        await remove(category.items.map { RemovalTarget(url: $0.url, size: $0.size) }, permanently: permanent)
    }

    private func applyRemoval(_ removed: Set<String>) {
        guard !removed.isEmpty else { return }
        func isRemoved(_ path: String) -> Bool {
            var p = path
            while true {
                if removed.contains(p) { return true }
                guard let r = p.range(of: "/", options: .backwards), r.lowerBound > p.startIndex else { return false }
                p = String(p[..<r.lowerBound])
            }
        }

        files.removeAll { isRemoved($0.id) }
        devArtifacts.removeAll { isRemoved($0.url.path) }
        duplicateGroups = duplicateGroups.compactMap { g in
            var g = g
            g.files.removeAll { isRemoved($0.id) }
            return g.files.count > 1 ? g : nil
        }
        for i in junkCategories.indices {
            junkCategories[i].items.removeAll { isRemoved($0.id) }
        }
        if let root = rootNode {
            for path in removed {
                if let node = root.find(path: path), let parent = node.parent {
                    parent.removeChild(node)
                }
            }
            if let current = currentNode, current !== root, isRemoved(current.url.path) {
                currentNode = root
            }
        }
        objectWillChange.send()
    }
}
