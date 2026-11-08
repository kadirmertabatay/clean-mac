import Foundation

struct CleanupRule: Codable, Identifiable, Hashable {
    enum Kind: Codable, Hashable {
        /// Güvenli bir gereksiz dosya kategorisinin tamamı (ör. "caches", "logs").
        case junk(String)
        /// İndirilenler'de belirtilen günden eski .dmg / .pkg / .xip / .iso dosyaları.
        case installers(days: Int)
    }

    enum Interval: String, Codable, CaseIterable, Identifiable {
        case daily, weekly, monthly
        var id: String { rawValue }
        var seconds: TimeInterval {
            switch self {
            case .daily: 86_400
            case .weekly: 7 * 86_400
            case .monthly: 30 * 86_400
            }
        }
        var title: String {
            switch self {
            case .daily: "Her gün"
            case .weekly: "Her hafta"
            case .monthly: "Her ay"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var interval: Interval
    var enabled = true
    /// Kapalıyken kural zamanı gelince yalnızca önizleme hazırlanır ve bildirim gönderilir.
    var autoApply = false
    var createdAt = Date()
    var lastRun: Date?
    /// Zamanı gelmiş, onay bekleyen temizliğin tahmini boyutu.
    var pendingSize: Int64?

    var title: String {
        switch kind {
        case .junk(let id): JunkScanner.definitions.first { $0.id == id }?.title ?? id
        case .installers(let days): "İndirilenler'deki \(days)+ günlük kurulum dosyaları"
        }
    }

    var icon: String {
        switch kind {
        case .junk(let id): JunkScanner.definitions.first { $0.id == id }?.icon ?? "trash"
        case .installers: "opticaldiscdrive"
        }
    }

    var nextRun: Date { (lastRun ?? createdAt).addingTimeInterval(interval.seconds) }

    func isDue(now: Date = Date()) -> Bool { enabled && now >= nextRun }

    static let presets: [CleanupRule] = [
        CleanupRule(kind: .junk("caches"), interval: .weekly),
        CleanupRule(kind: .junk("logs"), interval: .weekly),
        CleanupRule(kind: .junk("package-caches"), interval: .monthly),
        CleanupRule(kind: .junk("xcode-derived"), interval: .monthly),
        CleanupRule(kind: .installers(days: 30), interval: .weekly),
    ]
}

enum RuleEngine {
    static func targets(for rule: CleanupRule,
                        downloads: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"),
                        now: Date = Date()) -> [RemovalTarget] {
        switch rule.kind {
        case .junk(let id):
            return (JunkScanner.scan(id: id)?.items ?? []).map { RemovalTarget(url: $0.url, size: $0.size, expectedModified: nil) }
        case .installers(let days):
            let keys: Set<URLResourceKey> = [.addedToDirectoryDateKey, .contentModificationDateKey]
            let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
            let items = (try? FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: Array(keys),
                                                                      options: [.skipsHiddenFiles])) ?? []
            return items.compactMap { url in
                guard JunkScanner.installerExtensions.contains(url.pathExtension.lowercased()) else { return nil }
                let rv = try? url.resourceValues(forKeys: keys)
                guard let date = rv?.addedToDirectoryDate ?? rv?.contentModificationDate, date < cutoff else { return nil }
                return RemovalTarget(url: url, size: DiskScanner.allocatedSize(of: url))
            }
        }
    }

    /// Kalıcı silinebilecek mi: yalnızca önbellek türü kategoriler ve kullanıcı bunu ayarlardan açtıysa.
    static func isPermanent(_ rule: CleanupRule) -> Bool {
        if case .junk = rule.kind { return UserDefaults.standard.bool(forKey: "permanentDelete") }
        return false
    }
}
