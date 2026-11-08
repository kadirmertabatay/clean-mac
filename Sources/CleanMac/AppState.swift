import AppKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case assistant, overview, storage, growth, explorer, largeFiles, duplicates, photos, junk, apps, developer, docker, rules, history, exclusions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assistant: "Akıllı Asistan"
        case .overview: "Genel Bakış"
        case .storage: "Depolama Dökümü"
        case .growth: "Ne Büyüdü?"
        case .explorer: "Klasör Gezgini"
        case .largeFiles: "Büyük Dosyalar"
        case .duplicates: "Tekrarlanan Dosyalar"
        case .photos: "Benzer Fotoğraflar"
        case .junk: "Gereksiz Dosyalar"
        case .apps: "Uygulamalar"
        case .developer: "Geliştirici"
        case .docker: "Docker"
        case .rules: "Otomatik Temizlik"
        case .history: "Temizlik Geçmişi"
        case .exclusions: "Hariç Tutulanlar"
        }
    }

    var icon: String {
        switch self {
        case .assistant: "sparkles"
        case .overview: "internaldrive"
        case .storage: "chart.bar.doc.horizontal"
        case .growth: "chart.line.uptrend.xyaxis"
        case .explorer: "folder"
        case .largeFiles: "doc.badge.arrow.up"
        case .duplicates: "doc.on.doc"
        case .photos: "photo.stack"
        case .junk: "trash"
        case .apps: "square.grid.3x3"
        case .developer: "hammer"
        case .docker: "cube.box"
        case .rules: "calendar.badge.clock"
        case .history: "clock.arrow.circlepath"
        case .exclusions: "lock.shield"
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
    @Published var scanRoot: URL {
        didSet { UserDefaults.standard.set(scanRoot.path, forKey: "scanRootPath") }
    }
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

    // Benzer fotoğraflar
    @Published private(set) var similarPhotoGroups: [[FileEntry]] = []
    @Published private(set) var isFindingSimilar = false
    @Published private(set) var similarProgress: Double = 0
    @Published private(set) var similarPhotosReady = false
    private var similarTask: Task<[[FileEntry]], Never>?

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
    /// Arşivleme sürüyorsa (tamamlanan, toplam, şu anki dosya).
    @Published private(set) var archiveProgress: (done: Int, total: Int, current: String)?
    private var junkTask: Task<[JunkCategory], Never>?
    private var analysisCancelled = false

    // Depolama dökümü
    @Published private(set) var storage: StorageReport?
    @Published private(set) var isLoadingStorage = false

    // Uygulamalar
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isLoadingApps = false
    /// Docker'ın sanal diskinin boyutu (Docker yüklüyse).
    @Published private(set) var dockerDataSize: Int64 = 0

    // Ne büyüdü? (en yenisi başta)
    @Published private(set) var scanSnapshots: [ScanSnapshot] = []
    private let snapshotStore: SnapshotStore

    // Docker
    @Published private(set) var dockerSnapshot: DockerService.Snapshot?
    @Published private(set) var isLoadingDocker = false
    static let dockerInstalled = DockerService.isInstalled

    // Otomatik temizlik kuralları
    @Published private(set) var rules: [CleanupRule] = []

    // Geçmiş ve hariç tutulanlar
    @Published private(set) var history: [HistoryRecord] = []
    @Published private(set) var excludedPaths: [String]
    private let historyURL: URL

    nonisolated static let defaultHistoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CleanMac/history.json")

    init(historyURL: URL = AppState.defaultHistoryURL) {
        if let custom = ProcessInfo.processInfo.environment["CLEANMAC_SCAN_ROOT"] {
            scanRoot = URL(fileURLWithPath: custom)
        } else if let saved = UserDefaults.standard.string(forKey: "scanRootPath"),
                  FileManager.default.fileExists(atPath: saved) {
            scanRoot = URL(fileURLWithPath: saved)
        } else {
            scanRoot = Self.home
        }
        self.historyURL = historyURL
        snapshotStore = SnapshotStore(directory: historyURL.deletingLastPathComponent().appendingPathComponent("snapshots"))
        excludedPaths = UserDefaults.standard.stringArray(forKey: "excludedPaths") ?? []
        if let data = UserDefaults.standard.data(forKey: "cleanupRules"),
           let saved = try? JSONDecoder().decode([CleanupRule].self, from: data) {
            rules = saved
        }
        if let data = try? Data(contentsOf: historyURL),
           let records = try? JSONDecoder().decode([HistoryRecord].self, from: data) {
            history = records
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

    static let wholeMac = URL(fileURLWithPath: "/")

    var scanScopeTitle: String {
        switch scanRoot.path {
        case "/": "Tüm Mac"
        case Self.home.path: "Ana Klasör (~)"
        default: scanRoot.lastPathComponent
        }
    }

    var scanScopeIcon: String {
        switch scanRoot.path {
        case "/": "internaldrive"
        case Self.home.path: "house"
        default: "folder"
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

    /// Tarama, tekrar arama, gereksiz dosya taraması ve devam eden tam analizi durdurur.
    func cancelScan() {
        analysisCancelled = true
        scanTask?.cancel()
        duplicateTask?.cancel()
        junkTask?.cancel()
        similarTask?.cancel()
    }

    /// Tarama tamamlanırsa true, durdurulursa false döner.
    @discardableResult
    func scan() async -> Bool {
        guard !isScanning else { return false }
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
            return false
        }
        rootNode = result.root
        currentNode = result.root
        files = result.files
        devArtifacts = result.devArtifacts.sorted { $0.size > $1.size }
        duplicateGroups = []
        duplicatesReady = false
        similarPhotoGroups = []
        similarPhotosReady = false
        lastScan = ScanSummary(root: root, totalFiles: result.totalFiles, unreadable: result.unreadable,
                               duration: result.duration, date: Date())
        let snapshot = ScanSnapshot(tree: result.root, files: result.files)
        snapshotStore.save(snapshot)
        scanSnapshots = snapshotStore.load(root: root.path)
        refreshDisk()
        return true
    }

    func findDuplicates() async {
        guard !isFindingDuplicates else { return }
        if rootNode == nil { guard await scan() else { return } }
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

    func findSimilarPhotos() async {
        guard !isFindingSimilar else { return }
        if rootNode == nil { guard await scan() else { return } }
        isFindingSimilar = true
        similarProgress = 0
        let entries = files
        let task = Task.detached(priority: .userInitiated) { [weak self] () -> [[FileEntry]] in
            SimilarPhotos.findGroups(in: entries) { p in Task { @MainActor in self?.similarProgress = p } }
        }
        similarTask = task
        let groups = await task.value
        similarTask = nil
        isFindingSimilar = false
        guard !task.isCancelled else { return }
        similarPhotoGroups = groups
        similarPhotosReady = true
    }

    func scanJunk() async {
        guard !isScanningJunk else { return }
        isScanningJunk = true
        let task = Task.detached(priority: .userInitiated) { await JunkScanner.scanAll() }
        junkTask = task
        let categories = await task.value
        junkTask = nil
        isScanningJunk = false
        guard !task.isCancelled else { return }
        junkCategories = categories.map(withoutExcluded)
        junkReady = true
    }

    func refreshJunkCategory(_ id: String) async {
        let category = await Task.detached(priority: .utility) { JunkScanner.scan(id: id) }.value
        if let category, let i = junkCategories.firstIndex(where: { $0.id == id }) {
            junkCategories[i] = withoutExcluded(category)
        }
    }

    /// Asistanın tek tıkla çalıştırdığı tam analiz: gereksizler → klasör taraması → tekrarlar.
    func runFullAnalysis() async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        analysisCancelled = false
        defer {
            isAnalyzing = false
            analysisStep = ""
        }
        analysisStep = "Önbellekler ve gereksiz dosyalar aranıyor…"
        await scanJunk()
        guard !analysisCancelled else { return }
        analysisStep = "\(scanRoot.abbreviatedPath) klasörü taranıyor…"
        guard await scan(), !analysisCancelled else { return }
        analysisStep = "Tekrarlanan dosyalar karşılaştırılıyor…"
        await findDuplicates()
        guard !analysisCancelled else { return }
        await loadStorage()
        analysisStep = "Uygulamalar ölçülüyor…"
        await loadApps()
        lastAnalysis = Date()
        refreshDisk()
    }

    // MARK: - Silme

    /// Öğeleri Çöp Kutusu'na taşır (ya da kalıcı siler) ve tüm listeleri günceller.
    @discardableResult
    func remove(_ targets: [RemovalTarget], permanently: Bool) async -> OperationResult {
        guard !targets.isEmpty, !isRemoving else { return OperationResult() }
        isRemoving = true
        let excluded = excludedPaths
        let result = await Task.detached(priority: .userInitiated) { () -> OperationResult in
            var r = OperationResult()
            let fm = FileManager()
            for t in targets {
                if let reason = Self.safetyProblem(for: t, excluded: excluded, fm: fm) {
                    r.skipped.append("\(t.url.lastPathComponent): \(reason)")
                    continue
                }
                do {
                    var trashURL: URL?
                    if permanently {
                        try fm.removeItem(at: t.url)
                    } else {
                        var out: NSURL?
                        try fm.trashItem(at: t.url, resultingItemURL: &out)
                        trashURL = out as URL?
                    }
                    r.succeeded.append(t.url)
                    r.freed += t.size
                    r.records.append(HistoryRecord(originalPath: t.url.path, trashPath: trashURL?.path,
                                                   size: t.size, date: Date()))
                } catch {
                    r.failed.append(t.url.lastPathComponent)
                }
            }
            return r
        }.value
        isRemoving = false
        if !result.records.isEmpty {
            history.insert(contentsOf: result.records.reversed(), at: 0)
            saveHistory()
        }
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
            let notDone = result.failed.count + result.skipped.count
            if notDone > 0 { message += " · \(notDone) öğe atlandı" }
            showToast(message)
        } else if !result.skipped.isEmpty {
            showToast("Güvenlik kontrolü: \(result.skipped.first!)\(result.skipped.count > 1 ? " (+\(result.skipped.count - 1))" : "")", isError: true)
        } else if !result.failed.isEmpty {
            showToast("Öğeler silinemedi: izin yok ya da kullanımda olabilir.", isError: true)
        }
        refreshDisk()
        if junkReady { await refreshJunkCategory("trash") }
        return result
    }

    func chooseArchiveDestination() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        panel.prompt = "Buraya Arşivle"
        panel.message = "Dosyaların kopyalanacağı harici diski ya da klasörü seç"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Dosyaları hedefe kopyalar, doğrular; yalnızca doğrulananların orijinallerini Çöp Kutusu'na taşır.
    func archive(_ entries: [FileEntry], to destination: URL) async {
        guard archiveProgress == nil, !entries.isEmpty else { return }
        archiveProgress = (0, entries.count, "")
        let outcome = await Task.detached(priority: .userInitiated) { [weak self] () -> Swift.Result<ArchiveEngine.Result, Error> in
            Swift.Result {
                try ArchiveEngine.archive(entries, to: destination) { done, name in
                    Task { @MainActor in self?.archiveProgress = (done, entries.count, name) }
                }
            }
        }.value
        archiveProgress = nil
        switch outcome {
        case .failure(let error):
            showToast(error.localizedDescription, isError: true)
        case .success(let r):
            let targets = r.verified.map { RemovalTarget(url: $0.source.url, size: $0.source.size, expectedModified: $0.source.modified) }
            if !targets.isEmpty { await remove(targets, permanently: false) }
            var message = "\(r.verified.count) dosya \(destination.lastPathComponent) konumuna arşivlendi ve doğrulandı; orijinaller Çöp Kutusu'nda."
            if !r.failed.isEmpty { message += " \(r.failed.count) dosya atlandı (\(r.failed[0].reason))." }
            showToast(message, isError: r.verified.isEmpty)
        }
    }

    func cleanJunkCategory(_ id: String) async {
        guard let category = junkCategories.first(where: { $0.id == id }) else { return }
        let permanent = category.permanentOnly || UserDefaults.standard.bool(forKey: "permanentDelete")
        await remove(category.items.map { RemovalTarget(url: $0.url, size: $0.size) }, permanently: permanent)
    }

    /// Silmeden hemen önce yapılan güvenlik kontrolü. Sorun yoksa nil döner.
    nonisolated static func safetyProblem(for t: RemovalTarget, excluded: [String], fm: FileManager) -> String? {
        let path = t.url.path
        if excluded.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return "hariç tutulanlar listesinde"
        }
        var st = stat()
        guard lstat(path, &st) == 0 else { return "artık mevcut değil" }
        if let expected = t.expectedModified {
            let current = (try? t.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let current, abs(current.timeIntervalSince(expected)) > 1 {
                return "taramadan sonra değiştirilmiş, yeniden tara"
            }
        }
        if !t.keepAnyOf.isEmpty, !t.keepAnyOf.contains(where: { fm.fileExists(atPath: $0.path) }) {
            return "korunacak kopya artık yok, bu dosya son kopya olabilir"
        }
        return nil
    }

    // MARK: - Depolama dökümü

    func loadStorage() async {
        guard !isLoadingStorage else { return }
        isLoadingStorage = true
        storage = await Task.detached(priority: .userInitiated) { StorageInspector.load() }.value
        isLoadingStorage = false
    }

    func deleteSnapshots(_ snapshots: [LocalSnapshot]) async {
        let errors = await Task.detached(priority: .userInitiated) {
            snapshots.compactMap { StorageInspector.delete($0) }
        }.value
        if errors.isEmpty {
            showToast("\(snapshots.count) anlık görüntü silindi.")
        } else {
            showToast("Bazı anlık görüntüler silinemedi: \(errors[0])", isError: true)
        }
        await loadStorage()
        refreshDisk()
    }

    // MARK: - Uygulamalar

    func loadApps() async {
        guard !isLoadingApps else { return }
        isLoadingApps = true
        apps = await Task.detached(priority: .userInitiated) { AppInventory.installedApps() }.value
        if apps.contains(where: { $0.bundleID == "com.docker.docker" }) {
            dockerDataSize = await Task.detached(priority: .utility) { DiskScanner.allocatedSize(of: DevTools.dockerDataURL) }.value
        }
        isLoadingApps = false
    }

    /// Uygulamayı (açıksa kapatıp) seçili kalıntılarıyla birlikte Çöp Kutusu'na taşır.
    func uninstall(_ app: InstalledApp, leftovers: [AppLeftover]) async {
        guard !app.isApple else { return }
        if let id = app.bundleID {
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: id) { running.terminate() }
            for _ in 0..<20 where app.isRunning { try? await Task.sleep(for: .milliseconds(250)) }
            if app.isRunning {
                showToast("\(app.name) kapatılamadı; kapatıp tekrar dene.", isError: true)
                return
            }
        }
        let targets = [RemovalTarget(url: app.url, size: app.size)] + leftovers.map { RemovalTarget(url: $0.url, size: $0.size) }
        let result = await remove(targets, permanently: false)
        if result.succeeded.contains(app.url) {
            apps.removeAll { $0.id == app.id }
        } else {
            showToast("\(app.name) taşınamadı: yönetici izni gerekiyor olabilir. Finder'dan Çöp Kutusu'na sürükleyebilirsin.", isError: true)
        }
    }

    // MARK: - Docker

    func loadDocker() async {
        guard !isLoadingDocker else { return }
        isLoadingDocker = true
        dockerSnapshot = await Task.detached(priority: .userInitiated) { DockerService.load() }.value
        if let s = dockerSnapshot { dockerDataSize = s.diskImageSize }
        isLoadingDocker = false
    }

    /// Docker Desktop'ı başlatır ve motor hazır olana kadar (en fazla ~2 dk) bekler.
    func startDocker() async {
        _ = await Task.detached { () -> Bool in
            if let docker = DevTools.dockerPath, Shell.run(docker, ["desktop", "start"]).status == 0 { return true }
            return Shell.run("/usr/bin/open", ["-a", "Docker"]).status == 0
        }.value
        for _ in 0..<40 {
            if await Task.detached(operation: { DockerService.isRunning }).value { break }
            try? await Task.sleep(for: .seconds(3))
        }
        await loadDocker()
    }

    // MARK: - Otomatik temizlik

    func addRule(_ rule: CleanupRule) {
        guard !rules.contains(where: { $0.kind == rule.kind }) else { return }
        var r = rule
        r.id = UUID()
        r.createdAt = Date()
        rules.append(r)
        saveRules()
    }

    func updateRule(_ id: UUID, _ change: (inout CleanupRule) -> Void) {
        guard let i = rules.firstIndex(where: { $0.id == id }) else { return }
        change(&rules[i])
        saveRules()
    }

    func deleteRule(_ id: UUID) {
        rules.removeAll { $0.id == id }
        saveRules()
    }

    private func saveRules() {
        if let data = try? JSONEncoder().encode(rules) { UserDefaults.standard.set(data, forKey: "cleanupRules") }
    }

    func runRule(_ id: UUID, targets: [RemovalTarget]? = nil) async {
        guard let rule = rules.first(where: { $0.id == id }) else { return }
        let list: [RemovalTarget]
        if let targets { list = targets } else { list = await Task.detached { RuleEngine.targets(for: rule) }.value }
        if !list.isEmpty { await remove(list, permanently: RuleEngine.isPermanent(rule)) }
        updateRule(id) {
            $0.lastRun = Date()
            $0.pendingSize = nil
        }
    }

    /// Zamanı gelen kuralları işler: otomatikse uygular, değilse önizleme boyutunu hesaplayıp bildirim gönderir.
    func checkRules() async {
        for rule in rules where rule.isDue() {
            if rule.autoApply {
                await runRule(rule.id)
                SpaceMonitor.notify(title: "Otomatik temizlik yapıldı", body: rule.title)
            } else if rule.pendingSize == nil {
                let targets = await Task.detached { RuleEngine.targets(for: rule) }.value
                let size = targets.reduce(Int64(0)) { $0 + $1.size }
                if targets.isEmpty {
                    updateRule(rule.id) { $0.lastRun = Date() }
                } else {
                    updateRule(rule.id) { $0.pendingSize = size }
                    SpaceMonitor.notify(title: "Temizlik onay bekliyor",
                                        body: "\(rule.title): \(size.formattedBytes). Uygulamak için CleanMac › Otomatik Temizlik.")
                }
            }
        }
    }

    // MARK: - Geçmiş

    /// Çöp Kutusu'na taşınan öğeyi eski yerine geri koyar.
    func restore(_ record: HistoryRecord) {
        guard let trashPath = record.trashPath, !record.restored else { return }
        let fm = FileManager.default
        let original = URL(fileURLWithPath: record.originalPath)
        guard fm.fileExists(atPath: trashPath) else {
            showToast("\(record.name) Çöp Kutusu'nda bulunamadı (çöp boşaltılmış olabilir).", isError: true)
            return
        }
        guard !fm.fileExists(atPath: original.path) else {
            showToast("Eski konumda aynı adla bir öğe var: \(original.abbreviatedPath)", isError: true)
            return
        }
        do {
            try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: URL(fileURLWithPath: trashPath), to: original)
            if let i = history.firstIndex(where: { $0.id == record.id }) { history[i].restored = true }
            saveHistory()
            showToast("\(record.name) geri alındı. Listeleri güncellemek için yeniden tarayabilirsin.")
            refreshDisk()
            if junkReady { Task { await refreshJunkCategory("trash") } }
        } catch {
            showToast("Geri alınamadı: \(error.localizedDescription)", isError: true)
        }
    }

    func isInTrash(_ record: HistoryRecord) -> Bool {
        guard let p = record.trashPath, !record.restored else { return false }
        return FileManager.default.fileExists(atPath: p)
    }

    func clearHistory() {
        history = []
        saveHistory()
    }

    private func saveHistory() {
        let records = Array(history.prefix(2000))
        let url = historyURL
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(records) { try? data.write(to: url, options: .atomic) }
        }
    }

    // MARK: - Hariç tutulanlar

    func isExcluded(_ path: String) -> Bool {
        excludedPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    func addExclusion(_ url: URL) {
        let path = url.path
        guard !isExcluded(path) else { return }
        excludedPaths.removeAll { $0.hasPrefix(path + "/") }
        excludedPaths.append(path)
        excludedPaths.sort()
        UserDefaults.standard.set(excludedPaths, forKey: "excludedPaths")
        junkCategories = junkCategories.map(withoutExcluded)
        showToast("\(url.abbreviatedPath) artık önerilerde ve silme işlemlerinde yok sayılacak.")
    }

    func removeExclusion(_ path: String) {
        excludedPaths.removeAll { $0 == path }
        UserDefaults.standard.set(excludedPaths, forKey: "excludedPaths")
    }

    func chooseExclusion() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Hariç Tut"
        panel.message = "Temizlik önerilerinden korunacak klasör ya da dosyaları seç"
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(addExclusion)
    }

    private func withoutExcluded(_ c: JunkCategory) -> JunkCategory {
        var c = c
        c.items.removeAll { isExcluded($0.id) }
        return c
    }

    /// Hariç tutulanlar dışındaki proje bağımlılık klasörleri.
    var visibleDevArtifacts: [FileNode] { devArtifacts.filter { !isExcluded($0.url.path) } }

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
        similarPhotoGroups = similarPhotoGroups.compactMap { g in
            let rest = g.filter { !isRemoved($0.id) }
            return rest.count > 1 ? rest : nil
        }
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
