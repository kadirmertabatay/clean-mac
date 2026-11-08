import XCTest
@testable import CleanMac

final class SmartCleanupTests: XCTestCase {
    let home = FileManager.default.homeDirectoryForCurrentUser.path

    func app(_ name: String, _ bid: String) -> InstalledApp {
        InstalledApp(url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name, bundleID: bid, version: nil, size: 0, lastUsed: nil)
    }

    func testChromeProtectionMatchesItsCachesOnly() throws {
        let chrome = try XCTUnwrap(ProtectionCatalog.appProtections([app("Google Chrome", "com.google.Chrome")]).first)
        XCTAssertEqual(chrome.group, .browsers)
        for p in ["/Library/Caches/Google/Chrome", "/Library/Caches/com.google.Chrome", "/Library/Application Support/Google/Chrome/Default",
                  "/Library/HTTPStorages/com.google.Chrome", "/Library/Logs/Google Chrome"] {
            XCTAssertTrue(chrome.matches(home + p), p)
        }
        for p in ["/Library/Caches/com.spotify.client", "/Library/Caches/Firefox", "/Downloads/chrome-notlari.pdf"] {
            XCTAssertFalse(chrome.matches(home + p), p)
        }
    }

    func testShortAppNamesDoNotOvermatch() throws {
        // "Code" gibi kısa adlar yol bileşeni olarak bile eşleşmemeli; VS Code bilinen takma adlarla korunur.
        let code = try XCTUnwrap(ProtectionCatalog.appProtections([app("Code", "com.example.code")]).first)
        XCTAssertFalse(code.matches(home + "/codes/projects/x/node_modules"))
        let vscode = try XCTUnwrap(ProtectionCatalog.appProtections([app("Visual Studio Code", "com.microsoft.VSCode")]).first)
        XCTAssertTrue(vscode.matches(home + "/Library/Application Support/Code/Cache"))
        XCTAssertTrue(vscode.matches(home + "/Library/Caches/com.microsoft.VSCode.ShipIt"))
    }

    func testAreaProtectionsAndPlannerTally() {
        let desktop = ProtectionCatalog.areas.first { $0.id == "area.desktop" }!
        XCTAssertTrue(desktop.matches(home + "/Desktop/a/b.dmg"))
        XCTAssertFalse(desktop.matches(home + "/DesktopBackup/b.dmg"))

        let chrome = ProtectionCatalog.appProtections([app("Google Chrome", "com.google.Chrome")])[0]
        let group = SmartPlanGroup(id: "g", title: "Önbellek", detail: "", icon: "x", items: [
            SmartPlanItem(url: URL(fileURLWithPath: "/nonexistent-cleanmac/Library/Caches/Google"), size: 100),
            SmartPlanItem(url: URL(fileURLWithPath: "/nonexistent-cleanmac/Library/Caches/Google/Chrome"), size: 500),
            SmartPlanItem(url: URL(fileURLWithPath: "/nonexistent-cleanmac/Library/Caches/com.spotify.client"), size: 300),
            SmartPlanItem(url: URL(fileURLWithPath: home + "/Desktop/x.dmg"), size: 50),
            SmartPlanItem(url: URL(fileURLWithPath: "/nonexistent-cleanmac/Library/Caches/keep-me"), size: 10),
        ], regenerable: true)
        let r = SmartPlanner.filter([group], protections: [chrome, desktop], isExcluded: { $0.hasSuffix("keep-me") })
        XCTAssertEqual(r.groups.first?.items.map(\.url.lastPathComponent), ["Google", "com.spotify.client"],
                       "Bu yollar diskte yok; alt öğe kontrolü yalnızca gerçek klasörlerde çalışır")
        XCTAssertEqual(r.protected.map(\.title), ["Google Chrome", "Masaüstü", "Hariç tutulanlar"])
    }

    func testVendorFolderContainingProtectedAppIsProtected() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("CleanMacVendor-\(UUID().uuidString)")
        let vendor = base.appendingPathComponent("Caches/Google")
        try FileManager.default.createDirectory(at: vendor.appendingPathComponent("Chrome/Default"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("Caches/Other"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let chrome = ProtectionCatalog.appProtections([app("Google Chrome", "com.google.Chrome")])[0]
        XCTAssertEqual(Protection.protecting(vendor.path, in: [chrome])?.id, chrome.id)
        XCTAssertNil(Protection.protecting(base.appendingPathComponent("Caches/Other").path, in: [chrome]))
        // Korunan bir alanı içeren üst klasör de korunur.
        let desktop = Protection(id: "d", title: "Masaüstü", icon: "", group: .areas, paths: [base.path + "/Caches/Other/Desk"])
        XCTAssertNotNil(Protection.protecting(base.appendingPathComponent("Caches/Other").path, in: [desktop]))
    }

    func testRealMachineChromeProtectionReadOnly() async throws {
        let apps = AppInventory.installedApps()
        guard let chrome = ProtectionCatalog.appProtections(apps).first(where: { $0.id == "app.com.google.chrome" }) else {
            throw XCTSkip("Chrome yüklü değil")
        }
        let caches = await JunkScanner.scanAll().flatMap(\.items)
        let hit = caches.filter { Protection.protecting($0.id, in: [chrome]) != nil }
        print("[smart] Chrome koruması \(hit.count) öğeyi (\(hit.reduce(Int64(0)) { $0 + $1.size }.formattedBytes)) korur: \(hit.map(\.name).prefix(5))")
    }
}
