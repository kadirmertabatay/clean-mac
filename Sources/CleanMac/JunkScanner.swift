import Foundation

enum JunkSafety {
    case safe, review

    var title: String {
        switch self {
        case .safe: L("Safe")
        case .review: L("Needs review")
        }
    }
}

struct JunkItem: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let date: Date?
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

struct JunkCategory: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let safety: JunkSafety
    /// Categories that can only be deleted permanently, such as the Trash.
    let permanentOnly: Bool
    var items: [JunkItem]
    /// Locations that exist but can't be read due to missing permissions.
    var deniedPaths: [String] = []
    var size: Int64 { items.reduce(0) { $0 + $1.size } }
}

/// Scans known cache, log and developer-leftover locations.
enum JunkScanner {
    enum Source {
        case childrenOf([String])
        case paths([String])
        case downloads(installers: Bool)
    }

    struct Definition {
        let id: String
        let title: String
        let detail: String
        let icon: String
        let safety: JunkSafety
        var permanentOnly = false
        let source: Source
    }

    static let home = Paths.home.path
    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip", "iso"]
    static let oldDownloadDays = 90

    static let definitions: [Definition] = [
        Definition(id: "caches", title: L("App Caches"),
                   detail: L("Temporary cache files of apps. Apps recreate them when needed."),
                   icon: "archivebox", safety: .safe, source: .childrenOf(["~/Library/Caches"])),
        Definition(id: "logs", title: L("Log Files"),
                   detail: L("Records kept by apps. Not useful except for troubleshooting; safe to delete."),
                   icon: "doc.text.magnifyingglass", safety: .safe, source: .childrenOf(["~/Library/Logs"])),
        Definition(id: "xcode-derived", title: "Xcode DerivedData",
                   detail: L("Intermediate Xcode build output. Projects recreate it on the next build."),
                   icon: "hammer", safety: .safe, source: .childrenOf(["~/Library/Developer/Xcode/DerivedData"])),
        Definition(id: "device-support", title: L("Device Support Files"),
                   detail: L("iOS / watchOS device symbols. Downloaded again when the device is reconnected."),
                   icon: "iphone", safety: .safe,
                   source: .childrenOf(["~/Library/Developer/Xcode/iOS DeviceSupport",
                                        "~/Library/Developer/Xcode/watchOS DeviceSupport",
                                        "~/Library/Developer/Xcode/tvOS DeviceSupport",
                                        "~/Library/Developer/Xcode/visionOS DeviceSupport"])),
        Definition(id: "simulator-caches", title: L("Simulator Caches"),
                   detail: L("iOS Simulator caches. Recreated when needed."),
                   icon: "ipad.and.iphone", safety: .safe,
                   source: .childrenOf(["~/Library/Developer/CoreSimulator/Caches"])),
        Definition(id: "package-caches", title: L("Package Manager Caches"),
                   detail: L("npm, pnpm, Gradle, Cargo, Bun and Go download caches. Downloaded again when needed."),
                   icon: "shippingbox", safety: .safe,
                   source: .paths(["~/.npm/_cacache", "~/Library/pnpm/store", "~/.gradle/caches",
                                   "~/.cargo/registry/cache", "~/.bun/install/cache", "~/go/pkg/mod/cache/download"])),
        Definition(id: "dot-cache", title: L("General Cache Folder (~/.cache)"),
                   detail: L("Caches of command-line tools. May contain large but re-downloadable data such as AI models."),
                   icon: "tray.full", safety: .review, source: .childrenOf(["~/.cache"])),
        Definition(id: "installers", title: L("Installers in Downloads"),
                   detail: L(".dmg, .pkg, .xip and .iso files in ~/Downloads. Usually unnecessary once installed."),
                   icon: "opticaldiscdrive", safety: .review, source: .downloads(installers: true)),
        Definition(id: "old-downloads", title: L("Old Downloads"),
                   detail: L("Items that have been sitting in ~/Downloads for more than \(oldDownloadDays) days."),
                   icon: "clock.arrow.circlepath", safety: .review, source: .downloads(installers: false)),
        Definition(id: "xcode-archives", title: L("Xcode Archives"),
                   detail: L("Archives of published apps. Can be deleted if you don’t need symbols for old versions."),
                   icon: "archivebox.circle", safety: .review,
                   source: .childrenOf(["~/Library/Developer/Xcode/Archives"])),
        Definition(id: "ios-backups", title: L("iPhone / iPad Backups"),
                   detail: L("Local device backups made with Finder. You can delete the ones for old devices."),
                   icon: "externaldrive.badge.timemachine", safety: .review,
                   source: .childrenOf(["~/Library/Application Support/MobileSync/Backup"])),
        Definition(id: "trash", title: L("Trash"),
                   detail: L("Files moved to the Trash still take up space. Emptying it is permanent. (Full Disk Access may be required to see it.)"),
                   icon: "trash", safety: .safe, permanentOnly: true, source: .childrenOf(["~/.Trash"])),
    ]

    static func scanAll() async -> [JunkCategory] {
        await withTaskGroup(of: (Int, JunkCategory).self) { group in
            for (i, d) in definitions.enumerated() {
                group.addTask { (i, scan(d)) }
            }
            var out: [(Int, JunkCategory)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    static func scan(id: String) -> JunkCategory? {
        definitions.first { $0.id == id }.map(scan)
    }

    static func scan(_ d: Definition) -> JunkCategory {
        let (urls, denied) = candidates(for: d.source)
        var items = urls.compactMap { url -> JunkItem? in
            let size = DiskScanner.allocatedSize(of: url)
            guard size > 0 else { return nil }
            let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .addedToDirectoryDateKey])
            return JunkItem(url: url, size: size, date: rv?.addedToDirectoryDate ?? rv?.contentModificationDate)
        }
        items.sort { $0.size > $1.size }
        return JunkCategory(id: d.id, title: d.title, detail: d.detail, icon: d.icon, safety: d.safety,
                            permanentOnly: d.permanentOnly, items: items, deniedPaths: denied)
    }

    static func expand(_ p: String) -> String {
        p.hasPrefix("~") ? home + String(p.dropFirst()) : p
    }

    private static func candidates(for source: Source) -> ([URL], [String]) {
        let fm = FileManager()
        let ignored: Set<String> = [".DS_Store", ".localized"]
        var denied: [String] = []

        func children(of path: String, keys: [URLResourceKey]? = nil, options: FileManager.DirectoryEnumerationOptions = []) -> [URL] {
            let url = URL(fileURLWithPath: path)
            guard fm.fileExists(atPath: path) else { return [] }
            do {
                return try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)
            } catch {
                denied.append(path)
                return []
            }
        }

        switch source {
        case .paths(let paths):
            return (paths.map { URL(fileURLWithPath: expand($0)) }.filter { fm.fileExists(atPath: $0.path) }, [])
        case .childrenOf(let paths):
            let urls = paths.flatMap { children(of: expand($0)) }.filter { !ignored.contains($0.lastPathComponent) }
            return (urls, denied)
        case .downloads(let installers):
            let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey]
            let all = children(of: expand("~/Downloads"), keys: keys, options: [.skipsHiddenFiles])
            let cutoff = Date().addingTimeInterval(-Double(oldDownloadDays) * 86_400)
            let urls = all.filter { url in
                let isInstaller = installerExtensions.contains(url.pathExtension.lowercased())
                if installers { return isInstaller }
                guard !isInstaller else { return false }
                let rv = try? url.resourceValues(forKeys: Set(keys))
                let date = rv?.addedToDirectoryDate ?? rv?.contentModificationDate ?? Date()
                return date < cutoff
            }
            return (urls, denied)
        }
    }
}
