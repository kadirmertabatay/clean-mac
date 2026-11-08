import Foundation

/// Looks up a user-facing string in the app's string catalog (`Resources/Localizable.xcstrings`).
/// English is the source language; other languages (currently Turkish) are translations in the catalog.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key)
}

/// Base locations used by the app.
/// The `CLEANMAC_HOME` environment variable overrides the home folder (for screenshots with demo data and for tests);
/// `CLEANMAC_DATA_DIR` overrides the folder that holds the history and scan summaries.
enum Paths {
    static let home: URL = {
        if let custom = ProcessInfo.processInfo.environment["CLEANMAC_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()

    /// If the home folder is overridden, only its Applications folder is read (real apps don't show up in demo mode).
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
    /// The path with the home folder abbreviated to "~".
    var abbreviatedPath: String {
        let home = Paths.home.path
        let p = path
        if p == home { return "~" }
        if p.hasPrefix(home + "/") { return "~" + String(p.dropFirst(home.count)) }
        return p
    }
}

// MARK: - File kinds

enum FileKind: String, CaseIterable, Identifiable {
    case video, audio, image, archive, diskImage, document, application, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: L("Video")
        case .audio: L("Audio")
        case .image: L("Image")
        case .archive: L("Archive")
        case .diskImage: L("Disk Image / Installer")
        case .document: L("Document")
        case .application: L("App")
        case .other: L("Other")
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

// MARK: - File found by a scan

struct FileEntry: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let modified: Date?
    let accessed: Date?
    /// Is it inside ~/Library, a system folder or a package (.app, .photoslibrary…)?
    let isProtected: Bool

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var kind: FileKind { FileKind.of(url.pathExtension.lowercased()) }
    var kindTitle: String { kind.title }
    var parentPath: String { url.deletingLastPathComponent().abbreviatedPath }
    var modifiedSort: Date { modified ?? .distantPast }

    /// The more recent of the last-opened and modification dates.
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

// MARK: - Folder tree

final class FileNode: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    /// Virtual node that aggregates small files into a single row.
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

    /// Removes a child node and updates sizes up to the parent folders.
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

// MARK: - Disk info

struct DiskInfo {
    let name: String
    let total: Int64
    /// Available capacity for "important usage" (includes purgeable space).
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
    /// Modification date at scan time; the file isn't deleted if it changed since then.
    var expectedModified: Date?
    /// If not empty, at least one of these must still exist before deletion (the kept copy of a duplicate).
    var keepAnyOf: [URL] = []
}

struct OperationResult {
    var succeeded: [URL] = []
    var failed: [String] = []
    /// Items skipped because they changed after the scan or failed a safety check.
    var skipped: [String] = []
    var freed: Int64 = 0
    var records: [HistoryRecord] = []
}

/// A single record in the cleanup history.
struct HistoryRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    let originalPath: String
    /// Location in the Trash; nil for permanently deleted items.
    let trashPath: String?
    let size: Int64
    let date: Date
    var restored = false

    var name: String { URL(fileURLWithPath: originalPath).lastPathComponent }
    var isPermanent: Bool { trashPath == nil }
}

extension FileManager {
    /// Whether the file is cloud-only (iCloud); reading such files triggers a download.
    static func isDataless(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        return (st.st_flags & UInt32(SF_DATALESS)) != 0 || (st.st_blocks == 0 && st.st_size > 0)
    }
}
