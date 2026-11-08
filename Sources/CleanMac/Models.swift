import Foundation

/// Uygulamanın kullandığı temel konumlar.
/// `CLEANMAC_HOME` ortam değişkeni ana klasörü değiştirir (demo verisiyle ekran görüntüsü almak ve testler için);
/// `CLEANMAC_DATA_DIR` geçmiş ve tarama özetlerinin tutulduğu klasörü değiştirir.
enum Paths {
    static let home: URL = {
        if let custom = ProcessInfo.processInfo.environment["CLEANMAC_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()

    /// Ana klasör değiştirildiyse yalnızca onun Applications klasörüne bakılır (demo modunda gerçek uygulamalar görünmez).
    static var applicationDirectories: [URL] {
        let user = home.appendingPathComponent("Applications")
        return ProcessInfo.processInfo.environment["CLEANMAC_HOME"] == nil ? [URL(fileURLWithPath: "/Applications"), user] : [user]
    }

    static let dataDirectory: URL = {
        if let custom = ProcessInfo.processInfo.environment["CLEANMAC_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CleanMac")
    }()
}

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension URL {
    /// Ana klasörü "~" ile kısaltılmış yol.
    var abbreviatedPath: String {
        let home = Paths.home.path
        let p = path
        if p == home { return "~" }
        if p.hasPrefix(home + "/") { return "~" + String(p.dropFirst(home.count)) }
        return p
    }
}

// MARK: - Dosya türleri

enum FileKind: String, CaseIterable, Identifiable {
    case video, audio, image, archive, diskImage, document, application, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: "Video"
        case .audio: "Ses"
        case .image: "Görsel"
        case .archive: "Arşiv"
        case .diskImage: "Disk İmajı / Kurulum"
        case .document: "Belge"
        case .application: "Uygulama"
        case .other: "Diğer"
        }
    }

    var icon: String {
        switch self {
        case .video: "film"
        case .audio: "music.note"
        case .image: "photo"
        case .archive: "doc.zipper"
        case .diskImage: "opticaldiscdrive"
        case .document: "doc.richtext"
        case .application: "app"
        case .other: "doc"
        }
    }

    static func of(_ ext: String) -> FileKind {
        switch ext {
        case "mp4", "mov", "mkv", "avi", "m4v", "webm", "wmv", "flv", "mpg", "mpeg", "mts": .video
        case "mp3", "wav", "aac", "flac", "m4a", "aiff", "aif", "ogg", "alac": .audio
        case "jpg", "jpeg", "png", "heic", "gif", "tiff", "tif", "raw", "cr2", "cr3", "nef", "arw", "dng", "psd", "webp", "bmp": .image
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst": .archive
        case "dmg", "iso", "pkg", "mpkg", "xip", "img", "vmdk", "qcow2", "vdi", "ipsw", "raw-disk": .diskImage
        case "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "key", "pages", "numbers", "txt", "csv", "epub": .document
        case "app": .application
        default: .other
        }
    }
}

// MARK: - Taramada bulunan dosya

struct FileEntry: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let modified: Date?
    let accessed: Date?
    /// ~/Library, sistem klasörleri veya bir paket (.app, .photoslibrary…) içinde mi?
    let isProtected: Bool

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var kind: FileKind { FileKind.of(url.pathExtension.lowercased()) }
    var kindTitle: String { kind.title }
    var parentPath: String { url.deletingLastPathComponent().abbreviatedPath }
    var modifiedSort: Date { modified ?? .distantPast }

    /// Son açılma ya da değiştirilme tarihinden yeni olanı.
    var lastUsed: Date? {
        switch (accessed, modified) {
        case let (a?, m?): max(a, m)
        case let (a?, nil): a
        case let (nil, m?): m
        default: nil
        }
    }
    var lastUsedSort: Date { lastUsed ?? .distantPast }

    static func == (l: FileEntry, r: FileEntry) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

// MARK: - Klasör ağacı

final class FileNode: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    /// Küçük dosyaların tek satırda toplandığı sanal düğüm.
    let isAggregate: Bool
    var size: Int64
    var fileCount: Int
    var children: [FileNode] = []
    weak var parent: FileNode?

    init(url: URL, name: String? = nil, isDirectory: Bool, isPackage: Bool = false,
         isAggregate: Bool = false, size: Int64 = 0, fileCount: Int = 0) {
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isAggregate = isAggregate
        self.size = size
        self.fileCount = fileCount
    }

    var canDrillDown: Bool { isDirectory && !isAggregate && !children.isEmpty }

    func find(path target: String) -> FileNode? {
        if url.path == target { return self }
        for c in children where !c.isAggregate {
            let cp = c.url.path
            if cp == target { return c }
            if c.isDirectory, target.hasPrefix(cp + "/") { return c.find(path: target) }
        }
        return nil
    }

    /// Alt düğümü kaldırır ve boyutları üst klasörlere kadar günceller.
    func removeChild(_ child: FileNode) {
        guard let i = children.firstIndex(where: { $0 === child }) else { return }
        children.remove(at: i)
        var n: FileNode? = self
        while let cur = n {
            cur.size -= child.size
            cur.fileCount -= child.fileCount
            n = cur.parent
        }
    }
}

// MARK: - Disk bilgisi

struct DiskInfo {
    let name: String
    let total: Int64
    /// "Önemli kullanım" için kullanılabilir alan (temizlenebilir alan dahil).
    let available: Int64

    var used: Int64 { max(total - available, 0) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    var freeFraction: Double { 1 - usedFraction }

    static func current() -> DiskInfo? {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                         .volumeAvailableCapacityKey, .volumeLocalizedNameKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return nil }
        let total = Int64(v.volumeTotalCapacity ?? 0)
        let available = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
        return DiskInfo(name: v.volumeLocalizedName ?? "Macintosh HD", total: total, available: available)
    }
}

struct RemovalTarget {
    let url: URL
    let size: Int64
    /// Taramadaki değiştirilme tarihi; dosya o zamandan beri değiştiyse silinmez.
    var expectedModified: Date?
    /// Boş değilse, silmeden önce bunlardan en az birinin hâlâ var olması gerekir (tekrarlarda korunan kopya).
    var keepAnyOf: [URL] = []
}

struct OperationResult {
    var succeeded: [URL] = []
    var failed: [String] = []
    /// Taramadan sonra değiştiği ya da güvenlik kontrolünden geçemediği için atlananlar.
    var skipped: [String] = []
    var freed: Int64 = 0
    var records: [HistoryRecord] = []
}

/// Temizlik geçmişindeki tek bir kayıt.
struct HistoryRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    let originalPath: String
    /// Çöp Kutusu'ndaki konumu; kalıcı silinenlerde nil.
    let trashPath: String?
    let size: Int64
    let date: Date
    var restored = false

    var name: String { URL(fileURLWithPath: originalPath).lastPathComponent }
    var isPermanent: Bool { trashPath == nil }
}

extension FileManager {
    /// Dosyanın yalnızca bulutta (iCloud) durup durmadığı; bu dosyaları okumak indirmeyi tetikler.
    static func isDataless(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        return (st.st_flags & UInt32(SF_DATALESS)) != 0 || (st.st_blocks == 0 && st.st_size > 0)
    }
}
