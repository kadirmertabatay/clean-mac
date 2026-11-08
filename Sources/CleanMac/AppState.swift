import AppKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case assistant, smart, overview, storage, growth, explorer, largeFiles, duplicates, photos, junk, apps, developer, docker, rules, history, exclusions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assistant: L("Smart Assistant")
        case .smart: L("Smart Cleanup")
        case .overview: L("Overview")
        case .storage: L("Storage Breakdown")
        case .growth: L("What Grew?")
        case .explorer: L("Folder Explorer")
        case .largeFiles: L("Large Files")
        case .duplicates: L("Duplicate Files")
        case .photos: L("Similar Photos")
        case .junk: L("Junk Files")
        case .apps: L("Apps")
        case .developer: L("Developer")
        case .docker: "Docker"
        case .rules: L("Auto Cleanup")
        case .history: L("Cleanup History")
        case .exclusions: L("Exclusions")
        }
    }

    var icon: String {
        switch self {
        case .assistant: "sparkles"
        case .smart: "wand.and.sparkles"
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

    static let home = Paths.home

    @Published var section: AppSection? = .assistant
    @Published private(set) var disk: DiskInfo? = DiskInfo.current()
    @Published private(set) var hasFullDiskAccess = AppState.checkFullDiskAccess()
    @Published var toast: Toast?

    // Folder scan
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

    // Duplicate files
    @Published private(set) var duplicateGroups: [DuplicateGroup] = []
    @Published private(set) var isFindingDuplicates = false
    @Published private(set) var duplicateProgress: Double = 0
    @Published private(set) var duplicatesReady = false
    @Published var duplicateMinSize: Int64 = 1_000_000
    private var duplicateTask: Task<[DuplicateGroup], Never>?

    // Similar photos
    @Published private(set) var similarPhotoGroups: [[FileEntry]] = []
    @Published private(set) var isFindingSimilar = false
    @Published private(set) var similarProgress: Double = 0
    @Published private(set) var similarPhotosReady = false
    private var similarTask: Task<[[FileEntry]], Never>?

    // Junk files
    @Published private(set) var junkCategories: [JunkCategory] = []
    @Published private(set) var isScanningJunk = false
    @Published private(set) var junkReady = false

    // Assistant
    @Published private(set) var isAnalyzing = false
    @Published private(set) var analysisStep = ""
    @Published private(set) var lastAnalysis: Date?
    @Published var largeFilesStaleOnly = false
    @Published private(set) var isRemoving = false
    /// Set while archiving is in progress (completed, total, current file).
    @Published private(set) var archiveProgress: (done: Int, total: Int, current: String)?
    private var junkTask: Task<[JunkCategory], Never>?
    private var analysisCancelled = false

    // Storage breakdown
    @Published private(set) var storage: StorageReport?
    @Published private(set) var isLoadingStorage = false

    // Apps
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isLoadingApps = false
    /// Size of Docker's virtual disk (if Docker is installed).
    @Published private(set) var dockerDataSize: Int64 = 0

    // What grew? (newest first)
    @Published private(set) var scanSnapshots: [ScanSnapshot] = []
    private let snapshotStore: SnapshotStore

    // Docker
    @Published private(set) var dockerSnapshot: DockerService.Snapshot?
    @Published private(set) var isLoadingDocker = false
    static let dockerInstalled = DockerService.isInstalled

    // Smart Cleanup
    @Published private(set) var smartProtectionIDs: Set<String>
    @Published private(set) var smartStep = ""

    // Auto cleanup rules
    @Published private(set) var rules: [CleanupRule] = []

    // History and exclusions
    @Published private(set) var history: [HistoryRecord] = []
    @Published private(set) var excludedPaths: [String]
    private let historyURL: URL

    nonisolated static let defaultHistoryURL = Paths.dataDirectory.appendingPathComponent("history.json")

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
        smartProtectionIDs = Set(UserDefaults.standard.stringArray(forKey: "smartProtections") ?? Array(ProtectionCatalog.defaultIDs))
        if let data = UserDefaults.standard.data(forKey: "cleanupRules"),
           let saved = try? JSONDecoder().decode([CleanupRule].self, from: data) {
            rules = saved
        }
        if let data = try? Data(contentsOf: historyURL),
           let records = try? JSONDecoder().decode([HistoryRecord].self, from: data) {
            history = records
        }
    }

    // MARK: - General

    func refreshDisk() {
        disk = DiskInfo.current()
        hasFullDiskAccess = Self.checkFullDiskAccess()
    }

    /// Probes a folder that can't be read without Full Disk Access (doesn't trigger a permission prompt).
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
        case "/": L("Entire Mac")
        case Self.home.path: L("Home Folder (~)")
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
        panel.prompt = L("Scan")
        panel.message = L("Choose the folder to analyze")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        scanRoot = url
        return true
    }

    // MARK: - Scanning

    func startScan() {
        Task { await scan() }
    }

    /// Stops the scan, duplicate search, junk scan and any running full analysis.
    func cancelScan() {
        analysisCancelled = true
        scanTask?.cancel()
        duplicateTask?.cancel()
        junkTask?.cancel()
        similarTask?.cancel()
    }

    /// Returns true if the scan completed, false if it was stopped.
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
            showToast(L("Scan stopped."))
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

    /// The one-click full analysis run by the assistant: junk → folder scan → duplicates.
    func runFullAnalysis() async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        analysisCancelled = false
        defer {
            isAnalyzing = false
            analysisStep = ""
        }
        analysisStep = L("Looking for caches and junk files…")
        await scanJunk()
        guard !analysisCancelled else { return }
        analysisStep = L("Scanning \(scanRoot.abbreviatedPath)…")
        guard await scan(), !analysisCancelled else { return }
        analysisStep = L("Comparing duplicate files…")
        await findDuplicates()
        guard !analysisCancelled else { return }
        await loadStorage()
        analysisStep = L("Measuring apps…")
        await loadApps()
        lastAnalysis = Date()
        refreshDisk()
    }

    // MARK: - Removal

    /// Moves items to the Trash (or deletes them permanently) and updates all lists.
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
        // Match both forms for symlinked paths (/var ↔ /private/var).
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
            let verb = permanently ? L("deleted permanently") : L("moved to the Trash")
            var message = L("\(result.succeeded.count) items \(verb) · \(result.freed.formattedBytes)")
            let notDone = result.failed.count + result.skipped.count
            if notDone > 0 { message += L(" · \(notDone) skipped") }
            showToast(message)
        } else if !result.skipped.isEmpty {
            showToast(L("Safety check: \(result.skipped.first!)\(result.skipped.count > 1 ? " (+\(result.skipped.count - 1))" : "")"), isError: true)
        } else if !result.failed.isEmpty {
            showToast(L("Items could not be removed: permission denied or they may be in use."), isError: true)
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
        panel.prompt = L("Archive Here")
        panel.message = L("Choose the external disk or folder to copy the files to")
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Copies files to the destination and verifies them; only the originals of verified copies are moved to the Trash.
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
            var message = L("\(r.verified.count) files archived to \(destination.lastPathComponent) and verified; the originals are in the Trash.")
            if !r.failed.isEmpty { message += L(" \(r.failed.count) files skipped (\(r.failed[0].reason)).") }
            showToast(message, isError: r.verified.isEmpty)
        }
    }

    func cleanJunkCategory(_ id: String) async {
        guard let category = junkCategories.first(where: { $0.id == id }) else { return }
        let permanent = category.permanentOnly || UserDefaults.standard.bool(forKey: "permanentDelete")
        let items = category.items.filter { !isSmartProtected($0.id) }
        await remove(items.map { RemovalTarget(url: $0.url, size: $0.size) }, permanently: permanent)
    }

    /// Safety check performed right before removal. Returns nil if there's no problem.
    nonisolated static func safetyProblem(for t: RemovalTarget, excluded: [String], fm: FileManager) -> String? {
        let path = t.url.path
        if excluded.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return L("in the exclusions list")
        }
        var st = stat()
        guard lstat(path, &st) == 0 else { return L("no longer exists") }
        if let expected = t.expectedModified {
            let current = (try? t.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let current, abs(current.timeIntervalSince(expected)) > 1 {
                return L("changed since the scan, scan again")
            }
        }
        if !t.keepAnyOf.isEmpty, !t.keepAnyOf.contains(where: { fm.fileExists(atPath: $0.path) }) {
            return L("the copy to keep no longer exists, this may be the last copy")
        }
        return nil
    }

    // MARK: - Storage breakdown

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
            showToast(L("\(snapshots.count) snapshots deleted."))
        } else {
            showToast(L("Some snapshots could not be deleted: \(errors[0])"), isError: true)
        }
        await loadStorage()
        refreshDisk()
    }

    // MARK: - Apps

    func loadApps() async {
        guard !isLoadingApps else { return }
        isLoadingApps = true
        apps = await Task.detached(priority: .userInitiated) { AppInventory.installedApps() }.value
        if apps.contains(where: { $0.bundleID == "com.docker.docker" }) {
            dockerDataSize = await Task.detached(priority: .utility) { DiskScanner.allocatedSize(of: DevTools.dockerDataURL) }.value
        }
        isLoadingApps = false
    }

    /// Moves the app (quitting it first if running) to the Trash together with the selected leftovers.
    func uninstall(_ app: InstalledApp, leftovers: [AppLeftover]) async {
        guard !app.isApple else { return }
        if let id = app.bundleID {
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: id) { running.terminate() }
            for _ in 0..<20 where app.isRunning { try? await Task.sleep(for: .milliseconds(250)) }
            if app.isRunning {
                showToast(L("Couldn’t quit \(app.name); quit it and try again."), isError: true)
                return
            }
        }
        let targets = [RemovalTarget(url: app.url, size: app.size)] + leftovers.map { RemovalTarget(url: $0.url, size: $0.size) }
        let result = await remove(targets, permanently: false)
        if result.succeeded.contains(app.url) {
            apps.removeAll { $0.id == app.id }
        } else {
            showToast(L("Couldn’t move \(app.name): administrator permission may be required. You can drag it to the Trash in Finder."), isError: true)
        }
    }

    // MARK: - Smart Cleanup

    var protectionCatalog: [Protection] { ProtectionCatalog.all(apps: apps) }
    var activeProtections: [Protection] { protectionCatalog.filter { smartProtectionIDs.contains($0.id) } }

    func setProtection(_ id: String, _ on: Bool) {
        if on { smartProtectionIDs.insert(id) } else { smartProtectionIDs.remove(id) }
        UserDefaults.standard.set(Array(smartProtectionIDs).sorted(), forKey: "smartProtections")
    }

    /// Does a Smart Cleanup protection or the exclusions list cover this path?
    func isSmartProtected(_ path: String) -> Bool {
        isExcluded(path) || Protection.protecting(path, in: activeProtections) != nil
    }

    func buildSmartPlan(level: SmartLevel) async -> SmartPlan? {
        defer { smartStep = "" }
        if apps.isEmpty { smartStep = L("Reading apps…"); await loadApps() }
        smartStep = L("Looking for caches and junk files…")
        await scanJunk()
        var groups: [SmartPlanGroup] = []
        for id in level.junkCategories {
            guard let c = junkCategories.first(where: { $0.id == id }), !c.items.isEmpty else { continue }
            groups.append(SmartPlanGroup(id: "junk-\(id)", title: c.title, detail: c.detail, icon: c.icon,
                                         items: c.items.map { SmartPlanItem(url: $0.url, size: $0.size) },
                                         regenerable: c.safety == .safe))
        }

        if level != .safe {
            if rootNode == nil {
                smartStep = L("Scanning \(scanRoot.abbreviatedPath)…")
                guard await scan() else { return nil }
            }
            if let days = level.staleProjectDays {
                smartStep = L("Inspecting projects…")
                let artifacts = visibleDevArtifacts
                let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
                let stale = await Task.detached { artifacts.filter { (DevTools.projectLastActivity($0.url) ?? .distantFuture) < cutoff } }.value
                if !stale.isEmpty {
                    groups.append(SmartPlanGroup(id: "deps", title: L("Dependencies of projects untouched for \(days)+ days"),
                                                 detail: L("node_modules, .venv, Pods… They come back with npm install / pip install when you work on the project again."),
                                                 icon: "shippingbox", items: stale.map { SmartPlanItem(url: $0.url, size: $0.size) },
                                                 regenerable: false))
                }
            }
            if level.includesDuplicates {
                if !duplicatesReady { smartStep = L("Comparing duplicate files…"); await findDuplicates() }
                var items: [SmartPlanItem] = []
                for g in duplicateGroups {
                    let files = g.files.filter { !$0.isProtected }
                    guard files.count > 1, let keep = files.first else { continue }
                    items += files.dropFirst().map { SmartPlanItem(url: $0.url, size: $0.size, modified: $0.modified, keepAnyOf: [keep.url]) }
                }
                if !items.isEmpty {
                    groups.append(SmartPlanGroup(id: "dups", title: L("Exact duplicates"),
                                                 detail: L("The oldest file in each group is kept; the other copies are removed."),
                                                 icon: "doc.on.doc", items: items, regenerable: false))
                }
            }
        }
        let result = SmartPlanner.filter(groups, protections: activeProtections, isExcluded: isExcluded)
        return SmartPlan(groups: result.groups, protected: result.protected)
    }

    func applySmartPlan(_ plan: SmartPlan, selected: Set<String>) async {
        func targets(_ groups: [SmartPlanGroup]) -> [RemovalTarget] {
            groups.flatMap(\.items).filter { selected.contains($0.id) }
                .map { RemovalTarget(url: $0.url, size: $0.size, expectedModified: $0.modified, keepAnyOf: $0.keepAnyOf) }
        }
        let permanentOK = UserDefaults.standard.bool(forKey: "permanentDelete")
        let others = targets(plan.groups.filter { !$0.regenerable })
        let regenerable = targets(plan.groups.filter(\.regenerable))
        if !others.isEmpty { await remove(others, permanently: false) }
        if !regenerable.isEmpty { await remove(regenerable, permanently: permanentOK) }
    }

    // MARK: - Docker

    func loadDocker() async {
        guard !isLoadingDocker else { return }
        isLoadingDocker = true
        dockerSnapshot = await Task.detached(priority: .userInitiated) { DockerService.load() }.value
        if let s = dockerSnapshot { dockerDataSize = s.diskImageSize }
        isLoadingDocker = false
    }

    /// Starts Docker Desktop and waits until the engine is ready (up to ~2 minutes).
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

    // MARK: - Auto cleanup

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
        let allowed = list.filter { !isSmartProtected($0.url.path) }
        if !allowed.isEmpty { await remove(allowed, permanently: RuleEngine.isPermanent(rule)) }
        updateRule(id) {
            $0.lastRun = Date()
            $0.pendingSize = nil
        }
    }

    /// Processes due rules: applies them if automatic, otherwise computes the preview size and sends a notification.
    func checkRules() async {
        for rule in rules where rule.isDue() {
            if rule.autoApply {
                await runRule(rule.id)
                SpaceMonitor.notify(title: L("Automatic cleanup done"), body: rule.title)
            } else if rule.pendingSize == nil {
                let targets = await Task.detached { RuleEngine.targets(for: rule) }.value.filter { !isSmartProtected($0.url.path) }
                let size = targets.reduce(Int64(0)) { $0 + $1.size }
                if targets.isEmpty {
                    updateRule(rule.id) { $0.lastRun = Date() }
                } else {
                    updateRule(rule.id) { $0.pendingSize = size }
                    SpaceMonitor.notify(title: L("Cleanup awaiting approval"),
                                        body: L("\(rule.title): \(size.formattedBytes). To apply, open CleanMac › Auto Cleanup."))
                }
            }
        }
    }

    // MARK: - History

    /// Puts an item that was moved to the Trash back in its original location.
    func restore(_ record: HistoryRecord) {
        guard let trashPath = record.trashPath, !record.restored else { return }
        let fm = FileManager.default
        let original = URL(fileURLWithPath: record.originalPath)
        guard fm.fileExists(atPath: trashPath) else {
            showToast(L("\(record.name) wasn’t found in the Trash (it may have been emptied)."), isError: true)
            return
        }
        guard !fm.fileExists(atPath: original.path) else {
            showToast(L("An item with the same name exists at the original location: \(original.abbreviatedPath)"), isError: true)
            return
        }
        do {
            try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: URL(fileURLWithPath: trashPath), to: original)
            if let i = history.firstIndex(where: { $0.id == record.id }) { history[i].restored = true }
            saveHistory()
            showToast(L("\(record.name) restored. Scan again to refresh the lists."))
            refreshDisk()
            if junkReady { Task { await refreshJunkCategory("trash") } }
        } catch {
            showToast(L("Couldn’t restore: \(error.localizedDescription)"), isError: true)
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

    // MARK: - Exclusions

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
        showToast(L("\(url.abbreviatedPath) will now be ignored by suggestions and cleanups."))
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
        panel.prompt = L("Exclude")
        panel.message = L("Choose folders or files to protect from cleanup suggestions")
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(addExclusion)
    }

    private func withoutExcluded(_ c: JunkCategory) -> JunkCategory {
        var c = c
        c.items.removeAll { isExcluded($0.id) }
        return c
    }

    /// Project dependency folders outside the exclusions.
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
