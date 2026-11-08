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

/// Yüklü uygulamaları ve Library'de bıraktıkları dosyaları bulur.
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
                    // "Utilities" gibi bir seviye alt klasörler.
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

    /// Spotlight'ın tuttuğu "son açılma" tarihi.
    static func lastUsedDate(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// Uygulamanın ~/Library içinde bıraktığı dosyalar. Eşleştirme paket kimliği (ve bazı klasörlerde tam uygulama adı) ile yapılır.
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
        add("Application Support/\(id)", "Uygulama verisi")
        add("Application Support/\(appName)", "Uygulama verisi")
        add("Caches/\(id)", "Önbellek")
        add("Caches/\(appName)", "Önbellek")
        add("HTTPStorages/\(id)", "Önbellek")
        add("HTTPStorages/\(id).binarycookies", "Çerezler")
        add("WebKit/\(id)", "Web verisi")
        add("Preferences/\(id).plist", "Ayarlar")
        add("Saved Application State/\(id).savedState", "Pencere durumu")
        add("Logs/\(appName)", "Günlükler")
        add("Logs/\(id)", "Günlükler")
        add("Cookies/\(id).binarycookies", "Çerezler")
        add("Containers/\(id)", "Sanal alan (container)")
        add("Application Scripts/\(id)", "Betikler")

        // Grup kapsayıcıları "TAKIMKIMLIGI.paket.kimligi" biçimindedir; tam paket kimliğiyle bitenleri al.
        let groups = (try? fm.contentsOfDirectory(atPath: lib.appendingPathComponent("Group Containers").path)) ?? []
        for g in groups where g.hasSuffix(".\(id)") || g == id {
            candidates.append((lib.appendingPathComponent("Group Containers/\(g)"), "Grup verisi"))
        }
        let agents = (try? fm.contentsOfDirectory(atPath: lib.appendingPathComponent("LaunchAgents").path)) ?? []
        for a in agents where a.hasPrefix(id) {
            candidates.append((lib.appendingPathComponent("LaunchAgents/\(a)"), "Otomatik başlatma"))
        }

        var seen = Set<String>()
        return candidates.compactMap { url, kind in
            guard seen.insert(url.path).inserted else { return nil }
            return AppLeftover(url: url, size: DiskScanner.allocatedSize(of: url), kind: kind)
        }
        .sorted { $0.size > $1.size }
    }
}
