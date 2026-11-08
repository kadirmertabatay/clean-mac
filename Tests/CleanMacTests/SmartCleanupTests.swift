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
        // Short names like "Code" must not match even as a path component; VS Code is protected through known aliases.
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
        let group = SmartPlanGroup(id: "g", title: L("Cache"), detail: "", icon: "x", items: [
            SmartPlanItem(url: URL(fileURLWithPath: "/nonexistent-cleanmac/Library/Caches/Google"), size: 100),
            SmartPlanItem(url: URL(fileURLWithPath: "/nonexistent-cleanmac/Library/Caches/Google/Chrome"), size: 500),
            SmartPlanItem(url: URL(fileURLWithPath: "/nonexistent-cleanmac/Library/Caches/com.spotify.client"), size: 300),
            SmartPlanItem(url: URL(fileURLWithPath: home + "/Desktop/x.dmg"), size: 50),
            SmartPlanItem(url: URL(fileURLWithPath: "/nonexistent-cleanmac/Library/Caches/keep-me"), size: 10),
        ], regenerable: true)
        let r = SmartPlanner.filter([group], protections: [chrome, desktop], isExcluded: { $0.hasSuffix("keep-me") })
        XCTAssertEqual(r.groups.first?.items.map(\.url.lastPathComponent), ["Google", "com.spotify.client"],
                       "These paths don’t exist on disk; the child check only works on real folders")
        XCTAssertEqual(r.protected.map(\.title), ["Google Chrome", L("Desktop"), L("Exclusions")])
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
        // A parent folder containing a protected area is protected too.
        let desktop = Protection(id: "d", title: L("Desktop"), icon: "", group: .areas, paths: [base.path + "/Caches/Other/Desk"])
        XCTAssertNotNil(Protection.protecting(base.appendingPathComponent("Caches/Other").path, in: [desktop]))
    }

    func testRealMachineChromeProtectionReadOnly() async throws {
        let apps = AppInventory.installedApps()
        guard let chrome = ProtectionCatalog.appProtections(apps).first(where: { $0.id == "app.com.google.chrome" }) else {
            throw XCTSkip("Chrome is not installed")
        }
        let caches = await JunkScanner.scanAll().flatMap(\.items)
        let hit = caches.filter { Protection.protecting($0.id, in: [chrome]) != nil }
        print("[smart] Chrome protection covers \(hit.count) items (\(hit.reduce(Int64(0)) { $0 + $1.size }.formattedBytes)): \(hit.map(\.name).prefix(5))")
    }
}
