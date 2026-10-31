import Foundation

enum JunkSafety {
    case safe, review

    var title: String {
        switch self {
        case .safe: "Güvenli"
        case .review: "Gözden geçir"
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
    /// Çöp Kutusu gibi yalnızca kalıcı silinebilen kategoriler.
    let permanentOnly: Bool
    var items: [JunkItem]
    var size: Int64 { items.reduce(0) { $0 + $1.size } }
}

/// Bilinen önbellek, günlük ve geliştirici artığı konumlarını tarar.
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

    static let home = FileManager.default.homeDirectoryForCurrentUser.path
    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip", "iso"]
    static let oldDownloadDays = 90

    static let definitions: [Definition] = [
        Definition(id: "caches", title: "Uygulama Önbellekleri",
                   detail: "Uygulamaların geçici önbellek dosyaları. Silinince uygulamalar gerektiğinde yeniden oluşturur.",
                   icon: "archivebox", safety: .safe, source: .childrenOf(["~/Library/Caches"])),
        Definition(id: "logs", title: "Günlük (Log) Dosyaları",
                   detail: "Uygulamaların tuttuğu kayıtlar. Sorun giderme dışında işe yaramaz, güvenle silinebilir.",
                   icon: "doc.text.magnifyingglass", safety: .safe, source: .childrenOf(["~/Library/Logs"])),
        Definition(id: "xcode-derived", title: "Xcode DerivedData",
                   detail: "Xcode derleme ara çıktıları. Projeler ilk derlemede yeniden oluşturur.",
                   icon: "hammer", safety: .safe, source: .childrenOf(["~/Library/Developer/Xcode/DerivedData"])),
        Definition(id: "device-support", title: "Cihaz Destek Dosyaları",
                   detail: "iOS / watchOS cihaz sembolleri. Cihaz tekrar bağlandığında yeniden indirilir.",
                   icon: "iphone", safety: .safe,
                   source: .childrenOf(["~/Library/Developer/Xcode/iOS DeviceSupport",
                                        "~/Library/Developer/Xcode/watchOS DeviceSupport",
                                        "~/Library/Developer/Xcode/tvOS DeviceSupport",
                                        "~/Library/Developer/Xcode/visionOS DeviceSupport"])),
        Definition(id: "simulator-caches", title: "Simülatör Önbellekleri",
                   detail: "iOS Simülatörü önbellekleri. Gerektiğinde yeniden oluşturulur.",
                   icon: "ipad.and.iphone", safety: .safe,
                   source: .childrenOf(["~/Library/Developer/CoreSimulator/Caches"])),
        Definition(id: "package-caches", title: "Paket Yöneticisi Önbellekleri",
                   detail: "npm, pnpm, Gradle, Cargo, Bun ve Go indirme önbellekleri. Gerektiğinde yeniden indirilir.",
                   icon: "shippingbox", safety: .safe,
                   source: .paths(["~/.npm/_cacache", "~/Library/pnpm/store", "~/.gradle/caches",
                                   "~/.cargo/registry/cache", "~/.bun/install/cache", "~/go/pkg/mod/cache/download"])),
        Definition(id: "dot-cache", title: "Genel Önbellek Klasörü (~/.cache)",
                   detail: "Komut satırı araçlarının önbellekleri. İndirilmiş yapay zekâ modelleri gibi büyük ama yeniden indirilebilir veriler olabilir.",
                   icon: "tray.full", safety: .review, source: .childrenOf(["~/.cache"])),
        Definition(id: "installers", title: "İndirilenlerdeki Kurulum Dosyaları",
                   detail: "~/Downloads içindeki .dmg, .pkg, .xip, .iso dosyaları. Kurulum bittiyse genellikle gereksizdir.",
                   icon: "opticaldiscdrive", safety: .review, source: .downloads(installers: true)),
        Definition(id: "old-downloads", title: "Eski İndirmeler",
                   detail: "~/Downloads içinde \(oldDownloadDays) günden uzun süredir duran öğeler.",
                   icon: "clock.arrow.circlepath", safety: .review, source: .downloads(installers: false)),
        Definition(id: "xcode-archives", title: "Xcode Arşivleri",
                   detail: "Yayınlanmış uygulama arşivleri. Eski sürümlerin sembollerine ihtiyacın yoksa silinebilir.",
                   icon: "archivebox.circle", safety: .review,
                   source: .childrenOf(["~/Library/Developer/Xcode/Archives"])),
        Definition(id: "ios-backups", title: "iPhone / iPad Yedekleri",
                   detail: "Finder ile alınmış yerel cihaz yedekleri. Eski cihazlara ait olanları silebilirsin.",
                   icon: "externaldrive.badge.timemachine", safety: .review,
                   source: .childrenOf(["~/Library/Application Support/MobileSync/Backup"])),
        Definition(id: "trash", title: "Çöp Kutusu",
                   detail: "Çöpe taşınan dosyalar hâlâ yer kaplar. Boşaltmak kalıcıdır. (Görmek için Tam Disk Erişimi gerekebilir.)",
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
        var items = candidates(for: d.source).compactMap { url -> JunkItem? in
            let size = DiskScanner.allocatedSize(of: url)
            guard size > 0 else { return nil }
            let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .addedToDirectoryDateKey])
            return JunkItem(url: url, size: size, date: rv?.addedToDirectoryDate ?? rv?.contentModificationDate)
        }
        items.sort { $0.size > $1.size }
        return JunkCategory(id: d.id, title: d.title, detail: d.detail, icon: d.icon, safety: d.safety,
                            permanentOnly: d.permanentOnly, items: items)
    }

    static func expand(_ p: String) -> String {
        p.hasPrefix("~") ? home + String(p.dropFirst()) : p
    }

    private static func candidates(for source: Source) -> [URL] {
        let fm = FileManager()
        let ignored: Set<String> = [".DS_Store", ".localized"]
        switch source {
        case .paths(let paths):
            return paths.map { URL(fileURLWithPath: expand($0)) }.filter { fm.fileExists(atPath: $0.path) }
        case .childrenOf(let paths):
            return paths.flatMap { p -> [URL] in
                (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: expand(p)),
                                             includingPropertiesForKeys: nil, options: [])) ?? []
            }.filter { !ignored.contains($0.lastPathComponent) }
        case .downloads(let installers):
            let dl = URL(fileURLWithPath: expand("~/Downloads"))
            let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey]
            let all = (try? fm.contentsOfDirectory(at: dl, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
            let cutoff = Date().addingTimeInterval(-Double(oldDownloadDays) * 86_400)
            return all.filter { url in
                let isInstaller = installerExtensions.contains(url.pathExtension.lowercased())
                if installers { return isInstaller }
                guard !isInstaller else { return false }
                let rv = try? url.resourceValues(forKeys: Set(keys))
                let date = rv?.addedToDirectoryDate ?? rv?.contentModificationDate ?? Date()
                return date < cutoff
            }
        }
    }
}
