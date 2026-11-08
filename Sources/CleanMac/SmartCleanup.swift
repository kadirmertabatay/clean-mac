import Foundation

/// Akıllı Silme'de "buna dokunma" denilebilen bir uygulama, alan ya da araç.
struct Protection: Identifiable, Hashable {
    enum Group: String, CaseIterable {
        case areas = "Kişisel alanlar"
        case browsers = "Tarayıcılar"
        case apps = "Uygulamalar"
        case developer = "Geliştirici"
    }

    let id: String
    let title: String
    let icon: String
    let group: Group
    /// Bu alt dizgelerden birini içeren yollar korunur (küçük harf).
    var tokens: [String] = []
    /// Bu klasörlerin altındaki her şey korunur.
    var paths: [String] = []
    /// Simge için uygulama konumu.
    var appURL: URL?

    func matches(_ path: String) -> Bool {
        if paths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        let lower = path.lowercased()
        return tokens.contains { lower.contains($0) }
    }

    /// Bu yolu silmek korunan bir şeye dokunur mu? Yolun kendisi, korunan bir klasörü içermesi ya da
    /// doğrudan alt öğelerinden biri (ör. ~/Library/Caches/Google içindeki Chrome) kontrol edilir.
    static func protecting(_ path: String, in protections: [Protection]) -> Protection? {
        if let p = protections.first(where: { $0.matches(path) || $0.paths.contains { $0.hasPrefix(path + "/") } }) { return p }
        let children = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        for child in children {
            if let p = protections.first(where: { $0.matches(path + "/" + child) }) { return p }
        }
        return nil
    }
}

enum ProtectionCatalog {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// Varsayılan olarak korunan kişisel alanlar.
    static let defaultIDs: Set<String> = ["area.desktop", "area.documents", "area.pictures", "area.music", "area.icloud"]

    static let areas: [Protection] = [
        Protection(id: "area.desktop", title: "Masaüstü", icon: "menubar.dock.rectangle", group: .areas, paths: [home + "/Desktop"]),
        Protection(id: "area.documents", title: "Belgeler", icon: "doc.text", group: .areas, paths: [home + "/Documents"]),
        Protection(id: "area.downloads", title: "İndirilenler", icon: "arrow.down.circle", group: .areas, paths: [home + "/Downloads"]),
        Protection(id: "area.pictures", title: "Fotoğraflar ve Videolar", icon: "photo.on.rectangle", group: .areas,
                   paths: [home + "/Pictures", home + "/Movies"]),
        Protection(id: "area.music", title: "Müzik", icon: "music.note", group: .areas, paths: [home + "/Music"]),
        Protection(id: "area.icloud", title: "iCloud Drive", icon: "icloud", group: .areas,
                   paths: [home + "/Library/Mobile Documents"]),
    ]

    static let developer: [Protection] = [
        Protection(id: "dev.deps", title: "Proje bağımlılıkları (node_modules, .venv…)", icon: "shippingbox", group: .developer,
                   tokens: DiskScanner.devArtifactNames.map { "/" + $0.lowercased() }),
        Protection(id: "dev.pkgcache", title: "Paket önbellekleri (npm, Gradle, Cargo…)", icon: "archivebox", group: .developer,
                   tokens: ["/caches/yarn", "/caches/pip", "/caches/cocoapods", "/caches/homebrew"],
                   paths: [".npm", ".gradle", ".cargo", ".bun", "go/pkg", "Library/pnpm"].map { home + "/" + $0 }),
        Protection(id: "dev.xcode", title: "Xcode ve simülatörler", icon: "hammer", group: .developer,
                   tokens: ["com.apple.dt.xcode", "/developer/xcode", "/developer/coresimulator"]),
        Protection(id: "dev.dotcache", title: "~/.cache (yapay zekâ modelleri vb.)", icon: "brain", group: .developer,
                   paths: [home + "/.cache"]),
    ]

    /// Klasör adı paket kimliğinden farklı olan bilinen uygulamalar için ek eşleşmeler.
    static let aliases: [String: [String]] = [
        "com.google.chrome": ["/google/chrome", "google chrome"],
        "org.mozilla.firefox": ["/firefox", "mozilla"],
        "com.brave.browser": ["bravesoftware", "brave-browser"],
        "com.microsoft.edgemac": ["microsoft edge"],
        "company.thebrowser.browser": ["company.thebrowser", "/arc/"],
        "com.operasoftware.opera": ["com.operasoftware", "/opera"],
        "com.apple.safari": ["/safari", "com.apple.webkit.networking", "com.apple.safari"],
        "com.microsoft.vscode": ["/code/", "/.vscode", "com.microsoft.vscode"],
        "com.tinyspeck.slackmacgap": ["/slack"],
        "com.spotify.client": ["/spotify"],
        "com.hnc.discord": ["/discord"],
        "com.docker.docker": ["/docker", "com.docker"],
        "us.zoom.xos": ["us.zoom", "/zoom"],
        "com.todesktop.230313mzl4w4u92": ["/cursor"],
        "com.openai.chat": ["com.openai.chat", "/chatgpt"],
        "com.figma.desktop": ["/figma"],
        "notion.id": ["/notion"],
        "ru.keepcoder.telegram": ["/telegram"],
        "net.whatsapp.whatsapp": ["whatsapp"],
        "com.microsoft.teams2": ["microsoft teams", "com.microsoft.teams"],
    ]

    static let browserIDs: Set<String> = ["com.google.chrome", "org.mozilla.firefox", "com.brave.browser", "com.microsoft.edgemac",
                                          "company.thebrowser.browser", "com.operasoftware.opera", "com.apple.safari"]

    static func appProtections(_ apps: [InstalledApp]) -> [Protection] {
        var seen = Set<String>()
        var list = apps.compactMap { app -> Protection? in
            guard let bid = app.bundleID?.lowercased(), seen.insert(bid).inserted else { return nil }
            // macOS ile gelenlerden yalnızca Safari listelenir.
            if app.isApple && bid != "com.apple.safari" { return nil }
            let name = app.url.deletingPathExtension().lastPathComponent.lowercased()
            var tokens = [bid] + (aliases[bid] ?? [])
            // Kısa ve genel adlar (ör. "Code") yanlış eşleşmesin diye ad yalnızca klasör adı olarak eşleşir.
            if name.count >= 4 { tokens.append("/\(name)/") ; tokens.append("/\(name).") }
            return Protection(id: "app.\(bid)", title: app.name, icon: "app", group: browserIDs.contains(bid) ? .browsers : .apps,
                              tokens: tokens, appURL: app.url)
        }
        list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return list
    }

    static func all(apps: [InstalledApp]) -> [Protection] { areas + appProtections(apps) + developer }
}

// MARK: - Plan

struct SmartPlanItem: Identifiable, Hashable {
    let url: URL
    let size: Int64
    var modified: Date?
    var keepAnyOf: [URL] = []
    var id: String { url.path }
}

struct SmartPlanGroup: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    var items: [SmartPlanItem]
    /// Önbellek gibi geri gelmesi önemsiz öğeler (ayarlarda "kalıcı sil" açıksa kalıcı silinir).
    let regenerable: Bool
    var size: Int64 { items.reduce(0) { $0 + $1.size } }
}

struct SmartPlan {
    var groups: [SmartPlanGroup]
    /// Koruma adı → (öğe sayısı, boyut)
    var protected: [(title: String, count: Int, size: Int64)]
    var total: Int64 { groups.reduce(0) { $0 + $1.size } }
}

enum SmartLevel: String, CaseIterable, Identifiable {
    case safe, balanced, thorough
    var id: String { rawValue }

    var title: String {
        switch self {
        case .safe: "Güvenli"
        case .balanced: "Dengeli"
        case .thorough: "Kapsamlı"
        }
    }

    var detail: String {
        switch self {
        case .safe: "Yalnızca kendiliğinden yeniden oluşan dosyalar: uygulama önbellekleri, günlükler, Xcode ve paket yöneticisi önbellekleri."
        case .balanced: "Güvenli + İndirilenler'deki kurulum dosyaları, 90+ gündür dokunulmamış projelerin bağımlılıkları ve birebir aynı kopyalar (en eskisi korunur)."
        case .thorough: "Dengeli + 90+ gündür İndirilenler'de duran dosyalar, ~/.cache içeriği ve 30+ gündür dokunulmamış projelerin bağımlılıkları."
        }
    }

    var junkCategories: [String] {
        switch self {
        case .safe: ["caches", "logs", "xcode-derived", "device-support", "simulator-caches", "package-caches"]
        case .balanced: SmartLevel.safe.junkCategories + ["installers"]
        case .thorough: SmartLevel.balanced.junkCategories + ["old-downloads", "dot-cache"]
        }
    }

    var staleProjectDays: Int? {
        switch self {
        case .safe: nil
        case .balanced: 90
        case .thorough: 30
        }
    }

    var includesDuplicates: Bool { self != .safe }
}

enum SmartPlanner {
    /// Öğeleri korumalara ve hariç tutulanlara göre ayırır; korunanların dökümünü de döndürür.
    static func filter(_ groups: [SmartPlanGroup], protections: [Protection], isExcluded: (String) -> Bool)
        -> (groups: [SmartPlanGroup], protected: [(title: String, count: Int, size: Int64)]) {
        var tally: [String: (Int, Int64)] = [:]
        let filtered = groups.map { g -> SmartPlanGroup in
            var g = g
            g.items = g.items.filter { item in
                if isExcluded(item.id) {
                    tally["Hariç tutulanlar", default: (0, 0)].0 += 1
                    tally["Hariç tutulanlar", default: (0, 0)].1 += item.size
                    return false
                }
                if let p = Protection.protecting(item.id, in: protections) {
                    tally[p.title, default: (0, 0)].0 += 1
                    tally[p.title, default: (0, 0)].1 += item.size
                    return false
                }
                return true
            }
            return g
        }
        .filter { !$0.items.isEmpty }
        let protected = tally.map { (title: $0.key, count: $0.value.0, size: $0.value.1) }.sorted { $0.size > $1.size }
        return (filtered, protected)
    }
}
