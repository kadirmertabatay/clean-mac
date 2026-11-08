import Foundation

struct CleanupRule: Codable, Identifiable, Hashable {
    enum Kind: Codable, Hashable {
        /// An entire safe junk category (e.g. "caches", "logs").
        case junk(String)
        /// .dmg / .pkg / .xip / .iso files in Downloads older than the given number of days.
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
            case .daily: L("Daily")
            case .weekly: L("Weekly")
            case .monthly: L("Monthly")
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var interval: Interval
    var enabled = true
    /// When off, a due rule only prepares a preview and sends a notification.
    var autoApply = false
    var createdAt = Date()
    var lastRun: Date?
    /// Estimated size of a due cleanup awaiting approval.
    var pendingSize: Int64?

    var title: String {
        switch kind {
        case .junk(let id): JunkScanner.definitions.first { $0.id == id }?.title ?? id
        case .installers(let days): L("Installers in Downloads older than \(days) days")
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
                        downloads: URL = Paths.home.appendingPathComponent("Downloads"),
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

    /// Whether items can be deleted permanently: only cache-type categories, and only if the user enabled it in Settings.
    static func isPermanent(_ rule: CleanupRule) -> Bool {
        if case .junk = rule.kind { return UserDefaults.standard.bool(forKey: "permanentDelete") }
        return false
    }
}
