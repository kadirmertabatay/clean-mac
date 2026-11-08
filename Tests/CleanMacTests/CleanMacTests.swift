import XCTest
@testable import CleanMac

/// Tüm testler yalnızca kendi oluşturdukları geçici klasörde çalışır.
final class CleanMacTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanMacTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func makeFile(_ rel: String, bytes: Int, seed: UInt8 = 7) throws -> URL {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data((0..<bytes).map { UInt8(truncatingIfNeeded: $0 &* 31) &+ seed })
        try data.write(to: url)
        return url
    }

    func testScannerBuildsTreeAndTracksLargeFiles() throws {
        try makeFile("Movies/big.mov", bytes: 3_000_000)
        try makeFile("Movies/small.txt", bytes: 1_000)
        try makeFile("Projects/app/node_modules/pkg/index.js", bytes: 2_000_000)
        try makeFile("Projects/app/node_modules/pkg/node_modules/inner.js", bytes: 1_500_000)
        try makeFile("Library/Caches/cache.bin", bytes: 2_000_000)

        let result = DiskScanner { _ in }.scan(root: root)

        XCTAssertEqual(result.totalFiles, 5)
        XCTAssertEqual(result.files.count, 4, "1 MB üzeri 4 dosya izlenmeli")
        XCTAssertEqual(result.devArtifacts.count, 1, "İç içe node_modules tek sayılmalı")
        XCTAssertEqual(result.devArtifacts.first?.name, "node_modules")

        let movies = try XCTUnwrap(result.root.children.first { $0.name == "Movies" })
        XCTAssertEqual(movies.fileCount, 2)
        XCTAssertTrue(movies.children.contains { $0.isAggregate }, "Küçük dosyalar toplanmalı")
        XCTAssertGreaterThanOrEqual(movies.size, 3_000_000)
        XCTAssertEqual(result.root.size, result.root.children.reduce(0) { $0 + $1.size })

        let cache = try XCTUnwrap(result.files.first { $0.name == "cache.bin" })
        XCTAssertTrue(cache.isProtected, "Library içindekiler korumalı işaretlenmeli")
        XCTAssertFalse(try XCTUnwrap(result.files.first { $0.name == "big.mov" }).isProtected)
    }

    func testParallelScanSizesAreConsistentAtEveryDepth() throws {
        // splitDepth'ten derin klasörler: bölünen ve özyinelemeli taranan kısımlar birlikte doğru toplanmalı.
        for i in 0..<3 {
            try makeFile("a\(i)/b/c/d/e/f/g/deep\(i).bin", bytes: 1_200_000)
            try makeFile("a\(i)/b/c/mid.txt", bytes: 5_000)
            try makeFile("a\(i)/top.bin", bytes: 2_000_000)
        }
        try makeFile("a0/b/c/d/node_modules/x/lib.js", bytes: 1_100_000)
        let result = DiskScanner { _ in }.scan(root: root)
        XCTAssertEqual(result.totalFiles, 10)
        XCTAssertEqual(result.files.count, 7)
        XCTAssertEqual(result.devArtifacts.count, 1)

        func check(_ n: FileNode) {
            guard n.isDirectory else { return }
            XCTAssertEqual(n.size, n.children.reduce(0) { $0 + $1.size }, n.url.path)
            XCTAssertEqual(n.fileCount, n.children.reduce(0) { $0 + $1.fileCount }, n.url.path)
            XCTAssertEqual(n.children.map(\.size), n.children.map(\.size).sorted(by: >), "sıralı olmalı")
            n.children.forEach(check)
        }
        check(result.root)
        XCTAssertEqual(result.root.fileCount, 10)
    }

    func testDuplicateFinderMatchesContentNotJustSize() throws {
        let a = try makeFile("a/photo.jpg", bytes: 2_500_000)
        try makeFile("b/photo copy.jpg", bytes: 2_500_000)
        try makeFile("c/photo2.jpg", bytes: 2_500_000)
        try makeFile("d/same-size-different.jpg", bytes: 2_500_000, seed: 99)
        // Ortası farklı, baş ve sonu aynı: kısmi özet eşleşir, tam özet ayırmalı.
        var tricky = try Data(contentsOf: a)
        tricky[1_250_000] ^= 0xFF
        try tricky.write(to: root.appendingPathComponent("e-tricky.jpg"))
        // Sabit bağlantı kopya sayılmamalı.
        try FileManager.default.linkItem(at: a, to: root.appendingPathComponent("a/hardlink.jpg"))

        let scan = DiskScanner { _ in }.scan(root: root)
        let groups = DuplicateFinder.find(in: scan.files, minSize: 1_000_000) { _ in }

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.files.count, 3)
        XCTAssertFalse(groups.first!.files.contains { $0.name.contains("different") || $0.name.contains("tricky") })
    }

    func testAllocatedSizeOfFolder() throws {
        try makeFile("x/1.bin", bytes: 1_000_000)
        try makeFile("x/y/2.bin", bytes: 1_000_000)
        let size = DiskScanner.allocatedSize(of: root.appendingPathComponent("x"))
        XCTAssertGreaterThanOrEqual(size, 2_000_000)
    }

    @MainActor
    func testRemovalUpdatesTreeListsAndDuplicates() async throws {
        let keep = try makeFile("docs/report.pdf", bytes: 2_000_000)
        let dup = try makeFile("docs/old/report.pdf", bytes: 2_000_000)
        try makeFile("proj/node_modules/lib.js", bytes: 1_200_000)
        try makeFile("Movies/clip.mov", bytes: 4_000_000)

        let state = AppState(historyURL: root.appendingPathComponent("history.json"))
        state.scanRoot = root
        await state.scan()
        await state.findDuplicates()
        let rootNode = try XCTUnwrap(state.rootNode)
        let sizeBefore = rootNode.size
        XCTAssertEqual(state.duplicateGroups.count, 1)
        XCTAssertEqual(state.devArtifacts.count, 1)

        // Kalıcı silme: yalnızca test dosyaları.
        let artifact = state.devArtifacts[0]
        let result = await state.remove([RemovalTarget(url: dup, size: 2_000_000),
                                         RemovalTarget(url: artifact.url, size: artifact.size)], permanently: true)
        XCTAssertEqual(result.succeeded.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dup.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
        XCTAssertTrue(state.duplicateGroups.isEmpty, "Tek kopya kalınca grup kaybolmalı")
        XCTAssertTrue(state.devArtifacts.isEmpty)
        XCTAssertFalse(state.files.contains { $0.url == dup })
        XCTAssertFalse(state.files.contains { $0.name == "lib.js" }, "Silinen klasörün içindekiler de düşmeli")
        XCTAssertLessThan(rootNode.size, sizeBefore)
        XCTAssertNil(rootNode.find(path: dup.path))
        XCTAssertEqual(rootNode.size, rootNode.children.reduce(0) { $0 + $1.size })
    }

    @MainActor
    func testMoveToTrashRecordsHistoryAndRestores() async throws {
        let file = try makeFile("CleanMac-test-trash.bin", bytes: 10_000)
        let state = AppState(historyURL: root.appendingPathComponent("history.json"))
        let result = await state.remove([RemovalTarget(url: file, size: 10_000)], permanently: false)
        XCTAssertEqual(result.succeeded.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let record = try XCTUnwrap(state.history.first)
        XCTAssertNotNil(record.trashPath)
        XCTAssertTrue(state.isInTrash(record))

        // Geri al: dosya eski yerine dönmeli, Çöp Kutusu'nda iz kalmamalı.
        state.restore(record)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(state.history.first!.restored)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.trashPath!))
    }

    @MainActor
    func testRemovalSafetyChecks() async throws {
        let changed = try makeFile("changed.bin", bytes: 1_000)
        let lastCopy = try makeFile("dups/copy.bin", bytes: 1_000)
        let excluded = try makeFile("keep/important.bin", bytes: 1_000)
        let state = AppState(historyURL: root.appendingPathComponent("history.json"))
        state.addExclusion(excluded.deletingLastPathComponent())

        let result = await state.remove([
            // Taramadaki tarih farklı → dosya sonradan değişmiş.
            RemovalTarget(url: changed, size: 1_000, expectedModified: Date(timeIntervalSince1970: 0)),
            // Korunacak kopya artık yok → son kopya silinmemeli.
            RemovalTarget(url: lastCopy, size: 1_000, keepAnyOf: [root.appendingPathComponent("dups/gone.bin")]),
            // Hariç tutulan klasörde.
            RemovalTarget(url: excluded, size: 1_000),
            // Zaten yok.
            RemovalTarget(url: root.appendingPathComponent("missing.bin"), size: 1_000),
        ], permanently: true)

        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertEqual(result.skipped.count, 4)
        for f in [changed, lastCopy, excluded] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.path), f.lastPathComponent)
        }
        state.removeExclusion(excluded.deletingLastPathComponent().path)
    }

    func testPackageRootIsProtected() throws {
        let pkg = root.appendingPathComponent("Test.app")
        try makeFile("Test.app/Contents/MacOS/big.bin", bytes: 1_500_000)
        XCTAssertTrue(DiskScanner.isProtectedRoot(pkg))
        XCTAssertTrue(DiskScanner.isProtectedRoot(pkg.appendingPathComponent("Contents")))
        XCTAssertFalse(DiskScanner.isProtectedRoot(root))
        let result = DiskScanner { _ in }.scan(root: pkg)
        XCTAssertTrue(result.files.allSatisfy(\.isProtected))
    }

    func testJunkScannerRunsAndIsReadOnly() async throws {
        let categories = await JunkScanner.scanAll()
        XCTAssertEqual(categories.count, JunkScanner.definitions.count)
        for c in categories {
            print("[junk] \(c.title): \(c.size.formattedBytes) (\(c.items.count) öğe)")
            XCTAssertEqual(c.items, c.items.sorted { $0.size > $1.size })
        }
    }
}

/// Gerçek ana klasörde salt okunur performans ölçümü: CLEANMAC_BENCH=1 swift test --filter Benchmark
final class BenchmarkTests: XCTestCase {
    func testHomeScanPerformance() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLEANMAC_BENCH"] == "1")
        let path = ProcessInfo.processInfo.environment["CLEANMAC_BENCH_ROOT"]
        let home = path.map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
        let result = DiskScanner { _ in }.scan(root: home)
        print("[bench] \(result.totalFiles) dosya, \(result.root.size.formattedBytes), \(result.files.count) büyük dosya, \(result.devArtifacts.count) bağımlılık klasörü, \(result.unreadable) okunamayan, \(String(format: "%.1f", result.duration)) sn")
        for c in result.root.children.prefix(8) { print("[bench]   \(c.name): \(c.size.formattedBytes)") }
        let start = Date()
        let groups = DuplicateFinder.find(in: result.files, minSize: 1_000_000) { _ in }
        let waste = groups.filter { $0.files.contains { !$0.isProtected } }.reduce(Int64(0)) { $0 + $1.wasted }
        print("[bench] tekrar: \(groups.count) grup, kullanıcı alanında boşa ~\(waste.formattedBytes), \(String(format: "%.1f", Date().timeIntervalSince(start))) sn")
    }
}

final class StorageTests: XCTestCase {
    func testParsesTimeMachineSnapshots() {
        let text = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-11-07-093012.local
        com.apple.TimeMachine.2026-11-08-101010.local
        com.apple.os.update-ABC
        """
        let snaps = StorageInspector.parseSnapshots(text)
        XCTAssertEqual(snaps.map(\.dateString), ["2026-11-08-101010", "2026-11-07-093012"])
        XCTAssertNotNil(snaps.first?.date)
    }

    func testReadsStartupContainer() throws {
        let out = Shell.run("/usr/sbin/diskutil", ["apfs", "list", "-plist"])
        let report = try XCTUnwrap(StorageInspector.parseContainer(plist: Data(out.stdout.utf8)))
        XCTAssertGreaterThan(report.capacity, 0)
        XCTAssertTrue(report.volumes.contains { $0.role == "Data" })
        for v in report.volumes { print("[storage] \(v.title): \(v.used.formattedBytes)") }
    }
}

final class AppInventoryTests: XCTestCase {
    func testListsInstalledAppsReadOnly() {
        let apps = AppInventory.installedApps()
        XCTAssertFalse(apps.isEmpty)
        XCTAssertEqual(apps.map(\.size), apps.map(\.size).sorted(by: >))
        for a in apps.prefix(5) {
            print("[apps] \(a.name): \(a.size.formattedBytes), son açılma: \(a.lastUsed.map { "\($0)" } ?? "?")")
        }
        if let big = apps.first(where: { !$0.isApple }) {
            for l in AppInventory.leftovers(for: big) { print("[apps]   kalıntı \(l.kind): \(l.url.lastPathComponent) \(l.size.formattedBytes)") }
        }
    }
}

final class DevToolsTests: XCTestCase {
    func testParsesBrewDryRun() {
        let text = """
        Would remove: /opt/homebrew/Cellar/node/22.1.0 (2,000 files, 80MB)
        Would remove: /Users/x/Library/Caches/Homebrew/downloads/abc--wget.bottle.tar.gz (1.2MB)
        ==> This operation would free approximately 209.2MB of disk space.
        """
        let r = DevTools.parseBrew(text)
        XCTAssertEqual(r.items.count, 2)
        XCTAssertEqual(r.freeable, "209.2MB")
    }

    func testProjectLastActivityIgnoresDependencyFolder() throws {
        let project = FileManager.default.temporaryDirectory.appendingPathComponent("CleanMacProj-\(UUID().uuidString)")
        let deps = project.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: deps, withIntermediateDirectories: true)
        let pkg = project.appendingPathComponent("package.json")
        try Data("{}".utf8).write(to: pkg)
        let old = Date(timeIntervalSinceNow: -100 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: pkg.path)
        defer { try? FileManager.default.removeItem(at: project) }
        let activity = try XCTUnwrap(DevTools.projectLastActivity(deps))
        XCTAssertEqual(activity.timeIntervalSince1970, old.timeIntervalSince1970, accuracy: 1)
    }

    func testReadOnlyToolReports() {
        if let b = DevTools.brewDryRun() { print("[dev] brew: \(b.items.count) öğe, \(b.freeable ?? "-")") }
        print("[dev] simülatör: \(DevTools.unavailableSimulators().count)")
        if let d = DevTools.dockerReport() { print("[dev] docker çalışıyor: \(d.running), sanal disk: \(d.diskImageSize.formattedBytes)") }
    }
}
