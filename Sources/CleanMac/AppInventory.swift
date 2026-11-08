import AppKit
import CoreServices

struct InstalledApp: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleID: String?
    let version: String?
    var size: Int64
    let lastUsed: Date?
    var id: String { url.path }

    var isApple: Bool { bundleID?.hasPrefix("com.apple.") == true }
    var lastUsedSort: Date { lastUsed ?? .distantPast }
    var isRunning: Bool {
        guard let bundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static func == (l: InstalledApp, r: InstalledApp) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct AppLeftover: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let kind: String
    var id: String { url.path }
}

/// Finds installed apps and the files they leave behind in Library.
enum AppInventory {
    static let home = Paths.home

    static func installedApps() -> [InstalledApp] {
        let fm = FileManager()
        var urls: [URL] = []
        for dir in Paths.applicationDirectories {
            let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for item in items {
                if item.pathExtension == "app" {
                    urls.append(item)
                } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    // One level of subfolders such as "Utilities".
                    let sub = (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                    urls += sub.filter { $0.pathExtension == "app" }
                }
            }
        }

        var apps = [InstalledApp?](repeating: nil, count: urls.count)
        DispatchQueue.concurrentPerform(iterations: urls.count) { i in
            let url = urls[i]
            let bundle = Bundle(url: url)
            let info = bundle?.infoDictionary
            let name = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            apps[i] = InstalledApp(url: url, name: name, bundleID: bundle?.bundleIdentifier,
                                   version: info?["CFBundleShortVersionString"] as? String,
                                   size: DiskScanner.allocatedSize(of: url), lastUsed: lastUsedDate(url))
        }
        return apps.compactMap { $0 }.sorted { $0.size > $1.size }
    }

    /// The "last opened" date tracked by Spotlight.
    static func lastUsedDate(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// Files the app left in ~/Library. Matched by bundle identifier (and, for some folders, the exact app name).
    static func leftovers(for app: InstalledApp) -> [AppLeftover] {
        guard let id = app.bundleID, !id.isEmpty else { return [] }
        let lib = home.appendingPathComponent("Library")
        let fm = FileManager()
        let appName = app.url.deletingPathExtension().lastPathComponent
        var candidates: [(URL, String)] = []

        func add(_ rel: String, _ kind: String) {
            let u = lib.appendingPathComponent(rel)
            if fm.fileExists(atPath: u.path) { candidates.append((u, kind)) }
        }
        add("Application Support/\(id)", L("App data"))
        add("Application Support/\(appName)", L("App data"))
        add("Caches/\(id)", L("Cache"))
        add("Caches/\(appName)", L("Cache"))
        add("HTTPStorages/\(id)", L("Cache"))
        add("HTTPStorages/\(id).binarycookies", L("Cookies"))
        add("WebKit/\(id)", L("Web data"))
        add("Preferences/\(id).plist", L("Preferences"))
        add("Saved Application State/\(id).savedState", L("Window state"))
        add("Logs/\(appName)", L("Logs"))
        add("Logs/\(id)", L("Logs"))
        add("Cookies/\(id).binarycookies", L("Cookies"))
        add("Containers/\(id)", L("Sandbox (container)"))
        add("Application Scripts/\(id)", L("Scripts"))

        // Group containers are named "TEAMID.bundle.identifier"; take the ones ending with the full bundle identifier.
        let groups = (try? fm.contentsOfDirectory(atPath: lib.appendingPathComponent("Group Containers").path)) ?? []
        for g in groups where g.hasSuffix(".\(id)") || g == id {
            candidates.append((lib.appendingPathComponent("Group Containers/\(g)"), L("Group data")))
        }
        let agents = (try? fm.contentsOfDirectory(atPath: lib.appendingPathComponent("LaunchAgents").path)) ?? []
        for a in agents where a.hasPrefix(id) {
            candidates.append((lib.appendingPathComponent("LaunchAgents/\(a)"), L("Launch at login")))
        }

        var seen = Set<String>()
        return candidates.compactMap { url, kind in
            guard seen.insert(url.path).inserted else { return nil }
            return AppLeftover(url: url, size: DiskScanner.allocatedSize(of: url), kind: kind)
        }
        .sorted { $0.size > $1.size }
    }
}
