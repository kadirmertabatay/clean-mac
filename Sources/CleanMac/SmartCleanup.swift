import Foundation

/// An app, area or tool that can be marked "don't touch" in Smart Cleanup.
struct Protection: Identifiable, Hashable {
    enum Group: String, CaseIterable {
        case areas, browsers, apps, developer

        var title: String {
            switch self {
            case .areas: L("Personal areas")
            case .browsers: L("Browsers")
            case .apps: L("Apps")
            case .developer: L("Developer")
            }
        }
    }

    let id: String
    let title: String
    let icon: String
    let group: Group
    /// Paths containing one of these substrings are protected (lowercase).
    var tokens: [String] = []
    /// Everything under these folders is protected.
    var paths: [String] = []
    /// App location used for the icon.
    var appURL: URL?

    func matches(_ path: String) -> Bool {
        if paths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        let lower = path.lowercased()
        return tokens.contains { lower.contains($0) }
    }

    /// Would deleting this path touch something protected? Checks the path itself, whether it contains a protected folder, or
    /// one of its direct children (e.g. Chrome inside ~/Library/Caches/Google).
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
    static let home = Paths.home.path

    /// Personal areas protected by default.
    static let defaultIDs: Set<String> = ["area.desktop", "area.documents", "area.pictures", "area.music", "area.icloud"]

    static let areas: [Protection] = [
        Protection(id: "area.desktop", title: L("Desktop"), icon: "menubar.dock.rectangle", group: .areas, paths: [home + "/Desktop"]),
        Protection(id: "area.documents", title: L("Documents"), icon: "doc.text", group: .areas, paths: [home + "/Documents"]),
        Protection(id: "area.downloads", title: L("Downloads"), icon: "arrow.down.circle", group: .areas, paths: [home + "/Downloads"]),
        Protection(id: "area.pictures", title: L("Photos and Videos"), icon: "photo.on.rectangle", group: .areas,
                   paths: [home + "/Pictures", home + "/Movies"]),
        Protection(id: "area.music", title: L("Music"), icon: "music.note", group: .areas, paths: [home + "/Music"]),
        Protection(id: "area.icloud", title: "iCloud Drive", icon: "icloud", group: .areas,
                   paths: [home + "/Library/Mobile Documents"]),
    ]

    static let developer: [Protection] = [
        Protection(id: "dev.deps", title: L("Project dependencies (node_modules, .venv…)"), icon: "shippingbox", group: .developer,
                   tokens: DiskScanner.devArtifactNames.map { "/" + $0.lowercased() }),
        Protection(id: "dev.pkgcache", title: L("Package caches (npm, Gradle, Cargo…)"), icon: "archivebox", group: .developer,
                   tokens: ["/caches/yarn", "/caches/pip", "/caches/cocoapods", "/caches/homebrew"],
                   paths: [".npm", ".gradle", ".cargo", ".bun", "go/pkg", "Library/pnpm"].map { home + "/" + $0 }),
        Protection(id: "dev.xcode", title: L("Xcode and simulators"), icon: "hammer", group: .developer,
                   tokens: ["com.apple.dt.xcode", "/developer/xcode", "/developer/coresimulator"]),
        Protection(id: "dev.dotcache", title: L("~/.cache (AI models etc.)"), icon: "brain", group: .developer,
                   paths: [home + "/.cache"]),
    ]

    /// Extra matches for well-known apps whose folder names differ from their bundle identifier.
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
            // Of the apps that ship with macOS, only Safari is listed.
            if app.isApple && bid != "com.apple.safari" { return nil }
            let name = app.url.deletingPathExtension().lastPathComponent.lowercased()
            var tokens = [bid] + (aliases[bid] ?? [])
            // Short, generic names (e.g. "Code") match only as a folder name to avoid false matches.
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
    /// Items that are trivial to get back, like caches (deleted permanently if "delete permanently" is on in Settings).
    let regenerable: Bool
    var size: Int64 { items.reduce(0) { $0 + $1.size } }
}

struct SmartPlan {
    var groups: [SmartPlanGroup]
    /// Protection name → (item count, size)
    var protected: [(title: String, count: Int, size: Int64)]
    var total: Int64 { groups.reduce(0) { $0 + $1.size } }
}

enum SmartLevel: String, CaseIterable, Identifiable {
    case safe, balanced, thorough
    var id: String { rawValue }

    var title: String {
        switch self {
        case .safe: L("Safe")
        case .balanced: L("Balanced")
        case .thorough: L("Thorough")
        }
    }

    var detail: String {
        switch self {
        case .safe: L("Only files that regenerate on their own: app caches, logs, Xcode and package manager caches.")
        case .balanced: L("Safe + installers in Downloads, dependencies of projects untouched for 90+ days, and exact duplicates (the oldest is kept).")
        case .thorough: L("Balanced + files sitting in Downloads for 90+ days, ~/.cache contents, and dependencies of projects untouched for 30+ days.")
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
    /// Splits items by protections and exclusions; also returns a breakdown of what was protected.
    static func filter(_ groups: [SmartPlanGroup], protections: [Protection], isExcluded: (String) -> Bool)
        -> (groups: [SmartPlanGroup], protected: [(title: String, count: Int, size: Int64)]) {
        var tally: [String: (Int, Int64)] = [:]
        let filtered = groups.map { g -> SmartPlanGroup in
            var g = g
            g.items = g.items.filter { item in
                if isExcluded(item.id) {
                    tally[L("Exclusions"), default: (0, 0)].0 += 1
                    tally[L("Exclusions"), default: (0, 0)].1 += item.size
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
