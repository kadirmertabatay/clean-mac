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

        let state = AppState()
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
    func testMoveToTrashForTestFile() async throws {
        // Kullanıcının Çöp Kutusu'na dosya bırakır; yalnızca istenirse çalışır: CLEANMAC_TRASH_TEST=1
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLEANMAC_TRASH_TEST"] == "1")
        let file = try makeFile("CleanMac-test-trash.bin", bytes: 10_000)
        let state = AppState()
        let result = await state.remove([RemovalTarget(url: file, size: 10_000)], permanently: false)
        XCTAssertEqual(result.succeeded.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
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
        let home = FileManager.default.homeDirectoryForCurrentUser
        let result = DiskScanner { _ in }.scan(root: home)
        print("[bench] \(result.totalFiles) dosya, \(result.root.size.formattedBytes), \(result.files.count) büyük dosya, \(result.devArtifacts.count) bağımlılık klasörü, \(result.unreadable) okunamayan, \(String(format: "%.1f", result.duration)) sn")
        for c in result.root.children.prefix(8) { print("[bench]   \(c.name): \(c.size.formattedBytes)") }
        let start = Date()
        let groups = DuplicateFinder.find(in: result.files, minSize: 1_000_000) { _ in }
        let waste = groups.filter { $0.files.contains { !$0.isProtected } }.reduce(Int64(0)) { $0 + $1.wasted }
        print("[bench] tekrar: \(groups.count) grup, kullanıcı alanında boşa ~\(waste.formattedBytes), \(String(format: "%.1f", Date().timeIntervalSince(start))) sn")
    }
}
