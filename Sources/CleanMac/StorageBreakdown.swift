import Foundation

/// Komut satırı araçlarını (diskutil, tmutil) çalıştırmak için küçük yardımcı.
enum Shell {
    struct Output {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// GUI uygulamalarının PATH'i kısıtlı olduğu için araçlar (brew, docker, xcrun) bu PATH ile çalıştırılır.
    static let toolPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    static func run(_ path: String, _ args: [String], env: [String: String] = [:]) -> Output {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = toolPath
        environment.merge(env) { $1 }
        p.environment = environment
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return Output(status: -1, stdout: "", stderr: error.localizedDescription) }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Output(status: p.terminationStatus, stdout: String(decoding: o, as: UTF8.self),
                      stderr: String(decoding: e, as: UTF8.self))
    }

    /// Komutu yönetici parolası isteyerek çalıştırır (macOS'un kendi parola penceresi).
    static func runAsAdmin(_ command: String) -> Output {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return run("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
    }
}

struct APFSVolume: Identifiable {
    let id: String
    let name: String
    let roles: [String]
    let used: Int64

    var role: String { roles.first ?? "" }

    var title: String {
        switch role {
        case "System": "macOS Sistemi"
        case "Data": "Veriler (senin dosyaların, uygulamalar)"
        case "Preboot": "Preboot (başlatma dosyaları)"
        case "Recovery": "Kurtarma"
        case "VM": "Sanal Bellek (swap)"
        case "Update": "Güncelleme"
        default: name
        }
    }

    var explanation: String {
        switch role {
        case "System": "Salt okunur, mühürlü macOS. Silinemez; macOS sürümüne göre sabittir."
        case "Data": "Kullanıcı dosyaları, uygulamalar, önbellekler. Temizlik burada yer açar."
        case "Preboot": "Başlatma ve güvenlik dosyaları. macOS yönetir; büyükse genellikle bir sonraki güncellemede küçülür."
        case "Recovery": "Kurtarma sistemi. Silinmemeli."
        case "VM": "Bellek yetmediğinde kullanılan takas dosyaları. Yeniden başlatınca küçülür."
        case "Update": "Bekleyen sistem güncellemesi dosyaları."
        default: ""
        }
    }
}

struct LocalSnapshot: Identifiable, Hashable {
    let name: String
    /// tmutil'in silme için beklediği tarih metni, ör. "2026-11-08-101010".
    let dateString: String
    let date: Date?
    var id: String { name }
}

struct StorageReport {
    let capacity: Int64
    let free: Int64
    /// macOS'un gerektiğinde kendiliğinden silebileceği alan (önemli kullanım için kullanılabilir − gerçek boş).
    let purgeable: Int64
    let volumes: [APFSVolume]
    let snapshots: [LocalSnapshot]
    let otherSnapshotsNote: String?

    var dataVolume: APFSVolume? { volumes.first { $0.role == "Data" } }
}

enum StorageInspector {
    static func load() -> StorageReport? {
        let out = Shell.run("/usr/sbin/diskutil", ["apfs", "list", "-plist"])
        guard out.status == 0, let report = parseContainer(plist: Data(out.stdout.utf8)) else { return nil }
        let snaps = parseSnapshots(Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]).stdout)
        let important = DiskInfo.current()?.available ?? report.free
        return StorageReport(capacity: report.capacity, free: report.free,
                             purgeable: max(important - report.free, 0), volumes: report.volumes,
                             snapshots: snaps, otherSnapshotsNote: nil)
    }

    /// `diskutil apfs list -plist` çıktısından başlangıç diskinin (System + Data rolleri olan) konteynerini seçer.
    static func parseContainer(plist: Data) -> (capacity: Int64, free: Int64, volumes: [APFSVolume])? {
        guard let root = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
              let containers = root["Containers"] as? [[String: Any]] else { return nil }
        for c in containers {
            let vols = (c["Volumes"] as? [[String: Any]] ?? []).map { v in
                APFSVolume(id: v["DeviceIdentifier"] as? String ?? UUID().uuidString,
                           name: v["Name"] as? String ?? "?",
                           roles: v["Roles"] as? [String] ?? [],
                           used: (v["CapacityInUse"] as? NSNumber)?.int64Value ?? 0)
            }
            if vols.contains(where: { $0.role == "Data" }) && vols.contains(where: { $0.role == "System" }) {
                let capacity = (c["CapacityCeiling"] as? NSNumber)?.int64Value ?? 0
                let free = (c["CapacityFree"] as? NSNumber)?.int64Value ?? 0
                return (capacity, free, vols.sorted { $0.used > $1.used })
            }
        }
        return nil
    }

    /// `tmutil listlocalsnapshots /` satırlarını ayrıştırır: "com.apple.TimeMachine.2026-11-08-101010.local".
    static func parseSnapshots(_ text: String) -> [LocalSnapshot] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return text.split(separator: "\n").compactMap { line in
            let name = line.trimmingCharacters(in: .whitespaces)
            guard name.hasPrefix("com.apple.TimeMachine."),
                  let range = name.range(of: #"\d{4}-\d{2}-\d{2}-\d{6}"#, options: .regularExpression) else { return nil }
            let ds = String(name[range])
            return LocalSnapshot(name: name, dateString: ds, date: formatter.date(from: ds))
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Anlık görüntüyü siler; normal yetkiyle olmazsa yönetici parolası ister.
    static func delete(_ snapshot: LocalSnapshot) -> String? {
        let normal = Shell.run("/usr/bin/tmutil", ["deletelocalsnapshots", snapshot.dateString])
        if normal.status == 0 { return nil }
        let admin = Shell.runAsAdmin("/usr/bin/tmutil deletelocalsnapshots \(snapshot.dateString)")
        if admin.status == 0 { return nil }
        let message = (admin.stderr.isEmpty ? normal.stderr : admin.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Silinemedi." : message
    }
}
