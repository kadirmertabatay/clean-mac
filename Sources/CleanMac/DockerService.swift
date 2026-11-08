import Foundation

/// Docker CLI üzerinden imaj, konteyner, birim ve derleme önbelleğini okur ve siler.
enum DockerService {
    struct Image: Identifiable, Hashable {
        let imageID: String     // tam imaj kimliği (sha256:…); aynı imajın etiketleri bunu paylaşır
        let repository: String
        let tag: String
        let size: Int64
        let containers: Int
        let created: Date?
        let createdSince: String

        var isDangling: Bool { repository == "<none>" || tag == "<none>" }
        /// Silme için başvuru: etiketliyse "depo:etiket" (yalnız o etiketi kaldırır), değilse kimlik.
        var reference: String { isDangling ? imageID : "\(repository):\(tag)" }
        var displayName: String { isDangling ? "<etiketsiz> \(shortID)" : "\(repository):\(tag)" }
        var shortID: String { String(imageID.replacingOccurrences(of: "sha256:", with: "").prefix(12)) }
        /// Tablo satırı kimliği: her etiket ayrı satırdır.
        var id: String { "\(imageID)|\(repository):\(tag)" }
    }

    struct Container: Identifiable, Hashable {
        let id: String
        let name: String
        let image: String
        let state: String
        let status: String
        let size: Int64
        let created: Date?

        var isRunning: Bool { state == "running" || state == "restarting" || state == "paused" }
    }

    struct Volume: Identifiable, Hashable {
        let name: String
        let size: Int64
        let links: Int
        let isAnonymous: Bool
        var id: String { name }
        var displayName: String { isAnonymous ? "anonim \(name.prefix(12))…" : name }
    }

    struct CacheEntry: Identifiable, Hashable {
        let id: String
        let description: String
        let size: Int64
        let inUse: Bool
        let lastUsed: String
    }

    struct Snapshot {
        var images: [Image] = []
        var containers: [Container] = []
        var volumes: [Volume] = []
        var buildCache: [CacheEntry] = []
        /// Docker'ın sanal disk dosyasının macOS'ta kapladığı gerçek alan.
        var diskImageSize: Int64 = 0

        var usedTotal: Int64 {
            uniqueImageSize + containers.reduce(0) { $0 + $1.size } + volumes.reduce(0) { $0 + $1.size } + buildCache.reduce(0) { $0 + $1.size }
        }
        /// Aynı kimliğe sahip etiketler bir kez sayılır.
        var uniqueImageSize: Int64 {
            Dictionary(grouping: images, by: \.imageID).values.reduce(0) { $0 + ($1.first?.size ?? 0) }
        }
    }

    static var isInstalled: Bool {
        DevTools.dockerPath != nil || FileManager.default.fileExists(atPath: "/Applications/Docker.app")
    }

    static var isRunning: Bool {
        guard let docker = DevTools.dockerPath else { return false }
        return Shell.run(docker, ["info", "--format", "{{.ServerVersion}}"]).status == 0
    }

    static let diskImageURL = Paths.home
        .appendingPathComponent("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")

    // MARK: Okuma

    static func load() -> Snapshot? {
        guard let docker = DevTools.dockerPath else { return nil }
        var snap = Snapshot()
        snap.diskImageSize = DiskScanner.allocatedSize(of: diskImageURL)

        let images = Shell.run(docker, ["image", "ls", "-a", "--no-trunc", "--format", "{{json .}}"])
        guard images.status == 0 else { return nil }
        snap.images = jsonLines(images.stdout).map { o in
            Image(imageID: s(o["ID"]), repository: s(o["Repository"]), tag: s(o["Tag"]), size: parseSize(s(o["Size"])),
                  containers: Int(s(o["Containers"])) ?? 0, created: parseDate(s(o["CreatedAt"])),
                  createdSince: s(o["CreatedSince"]))
        }

        let containers = Shell.run(docker, ["ps", "-a", "--size", "--no-trunc", "--format", "{{json .}}"])
        snap.containers = jsonLines(containers.stdout).map { o in
            // "4.1kB (virtual 17kB)" → yazılabilir katman boyutu
            let size = s(o["Size"]).components(separatedBy: " (").first ?? ""
            return Container(id: s(o["ID"]), name: s(o["Names"]), image: s(o["Image"]), state: s(o["State"]),
                             status: s(o["Status"]), size: parseSize(size), created: parseDate(s(o["CreatedAt"])))
        }

        // Birim boyutları ve derleme önbelleği yalnızca ayrıntılı df çıktısında var.
        let df = Shell.run(docker, ["system", "df", "-v", "--format", "{{json .}}"])
        if let obj = try? JSONSerialization.jsonObject(with: Data(df.stdout.utf8)) as? [String: Any] {
            snap.volumes = (obj["Volumes"] as? [[String: Any]] ?? []).map { v in
                Volume(name: s(v["Name"]), size: parseSize(s(v["Size"])), links: Int(s(v["Links"])) ?? 0,
                       isAnonymous: s(v["Labels"]).contains("com.docker.volume.anonymous"))
            }
            snap.buildCache = (obj["BuildCache"] as? [[String: Any]] ?? []).map { c in
                CacheEntry(id: s(c["ID"]), description: s(c["Description"]), size: parseSize(s(c["Size"])),
                           inUse: s(c["InUse"]) == "true", lastUsed: s(c["LastUsedSince"]))
            }
        }
        snap.images.sort { $0.size > $1.size }
        snap.containers.sort { $0.size > $1.size }
        snap.volumes.sort { $0.size > $1.size }
        snap.buildCache.sort { $0.size > $1.size }
        return snap
    }

    // MARK: Analiz

    struct Findings {
        let dangling: [Image]
        let unusedImages: [Image]
        /// Aynı imaj kimliğine ait fazladan etiketler (yer kaplamaz ama karışıklık yaratır).
        let duplicateTags: [[Image]]
        /// Aynı deponun daha yeni sürümü varken kullanılmayan eski sürümleri.
        let oldVersions: [Image]
        let stoppedContainers: [Container]
        let orphanVolumes: [Volume]
        let reclaimableCache: [CacheEntry]
        /// Sanal diskin içerikten fazla kapladığı alan.
        let diskImageSlack: Int64
    }

    static func analyze(_ s: Snapshot) -> Findings {
        let byID = Dictionary(grouping: s.images, by: \.imageID)
        let unused = s.images.filter { $0.containers == 0 }
        let tagged = s.images.filter { !$0.isDangling }
        let byRepo = Dictionary(grouping: tagged, by: \.repository)
        let old = byRepo.values.flatMap { versions -> [Image] in
            guard Set(versions.map(\.imageID)).count > 1 else { return [] }
            let newest = versions.max { ($0.created ?? .distantPast) < ($1.created ?? .distantPast) }
            return versions.filter { $0.imageID != newest?.imageID && $0.containers == 0 }
        }
        return Findings(
            dangling: s.images.filter { $0.isDangling && $0.containers == 0 },
            unusedImages: unused.filter { !$0.isDangling },
            duplicateTags: byID.values.filter { $0.filter { !$0.isDangling }.count > 1 }.map { $0.sorted { $0.tag < $1.tag } },
            oldVersions: old.sorted { $0.size > $1.size },
            stoppedContainers: s.containers.filter { !$0.isRunning },
            orphanVolumes: s.volumes.filter { $0.links == 0 },
            reclaimableCache: s.buildCache.filter { !$0.inUse },
            diskImageSlack: max(s.diskImageSize - s.usedTotal, 0))
    }

    // MARK: Silme

    struct Outcome {
        var removed = 0
        var errors: [String] = []
    }

    private static func run(_ args: [String], items: [String]) -> Outcome {
        guard let docker = DevTools.dockerPath, !items.isEmpty else { return Outcome() }
        var out = Outcome()
        // Biri başarısız olsa da diğerleri silinsin diye tek tek çalıştırılır.
        for item in items {
            let r = Shell.run(docker, args + [item])
            if r.status == 0 { out.removed += 1 } else {
                out.errors.append(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return out
    }

    static func removeContainers(_ c: [Container]) -> Outcome { run(["rm"], items: c.filter { !$0.isRunning }.map(\.id)) }
    static func removeImages(_ i: [Image]) -> Outcome { run(["rmi"], items: i.map(\.reference)) }
    static func removeVolumes(_ v: [Volume]) -> Outcome { run(["volume", "rm"], items: v.map(\.name)) }

    static func pruneBuildCache() -> Outcome {
        guard let docker = DevTools.dockerPath else { return Outcome() }
        let r = Shell.run(docker, ["builder", "prune", "-f"])
        return r.status == 0 ? Outcome(removed: 1) : Outcome(errors: [r.stderr])
    }

    /// Sanal makinedeki boş blokları ana sisteme geri verir (veri silmez).
    static func trimDiskImage() -> Outcome {
        guard let docker = DevTools.dockerPath else { return Outcome() }
        let r = Shell.run(docker, ["run", "--rm", "--privileged", "--pid=host", "alpine:3.20",
                                   "nsenter", "-t", "1", "-m", "--", "fstrim", "/var/lib"])
        return r.status == 0 ? Outcome(removed: 1) : Outcome(errors: [r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)])
    }

    // MARK: Yardımcılar

    private static func s(_ v: Any?) -> String {
        if let v = v as? String { return v }
        if let v { return "\(v)" }
        return ""
    }

    static func jsonLines(_ text: String) -> [[String: Any]] {
        text.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    /// Docker'ın ondalık birimli boyutlarını ("17.1kB", "1.2GB", "0B") bayta çevirir.
    static func parseSize(_ text: String) -> Int64 {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard let r = t.range(of: #"^[\d.]+"#, options: .regularExpression), let n = Double(t[r]) else { return 0 }
        let unit = t[r.upperBound...].trimmingCharacters(in: .whitespaces).uppercased()
        let mult: Double = switch unit {
        case "KB": 1e3
        case "MB": 1e6
        case "GB": 1e9
        case "TB": 1e12
        default: 1
        }
        return Int64(n * mult)
    }

    /// "2026-03-24 00:34:00 +0300 +03"
    static func parseDate(_ text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        let parts = text.split(separator: " ")
        guard parts.count >= 3 else { return nil }
        return f.date(from: parts.prefix(3).joined(separator: " "))
    }
}
