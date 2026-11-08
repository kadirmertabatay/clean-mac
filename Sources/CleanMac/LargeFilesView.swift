import QuickLook
import SwiftUI

struct LargeFilesView: View {
    @EnvironmentObject var state: AppState
    @State private var minSize: Int64 = 100_000_000
    @State private var kind: FileKind?
    @State private var search = ""
    @State private var showProtected = false
    @State private var selection = Set<FileEntry.ID>()
    @State private var sortOrder = [KeyPathComparator(\FileEntry.size, order: .reverse)]
    @State private var confirm = false
    @State private var previewURL: URL?

    private static let sizeOptions: [(String, Int64)] = [
        ("10 MB", 10_000_000), ("50 MB", 50_000_000), ("100 MB", 100_000_000),
        ("500 MB", 500_000_000), ("1 GB", 1_000_000_000),
    ]

    private var filtered: [FileEntry] {
        let cutoff = Date().addingTimeInterval(-Double(AppState.staleDays) * 86_400)
        return state.files.filter { f in
            f.size >= minSize
                && (showProtected || !f.isProtected)
                && !state.isExcluded(f.id)
                && (kind == nil || f.kind == kind)
                && (search.isEmpty || f.name.localizedCaseInsensitiveContains(search))
                && (!state.largeFilesStaleOnly || (f.lastUsed ?? .distantPast) < cutoff)
        }
        .sorted(using: sortOrder)
    }

    var body: some View {
        let items = filtered
        let selected = items.filter { selection.contains($0.id) }
        let selectedSize = selected.reduce(Int64(0)) { $0 + $1.size }

        VStack(spacing: 0) {
            PageHeader(title: L("Large Files"), subtitle: L("Review the files taking up space by size, type and last use")) {
                Button {
                    state.startScan()
                } label: { Label(state.rootNode == nil ? L("Scan") : L("Scan Again"), systemImage: "arrow.clockwise") }
                    .disabled(state.isScanning)
            }
            Divider()
            if state.isScanning {
                ScanningView()
            } else if state.rootNode == nil {
                EmptyStateView(icon: "doc.badge.arrow.up", title: L("A scan is needed first"),
                               message: L("Let’s scan \(state.scanRoot.abbreviatedPath) to list large files."),
                               actionTitle: L("Start Scan")) { state.startScan() }
            } else {
                filterBar
                Divider()
                Table(items, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn(L("Name"), value: \.name) { f in
                        HStack(spacing: 8) {
                            FileIconView(url: f.url, size: 18)
                            Text(f.name).lineLimit(1).truncationMode(.middle)
                        }
                        .help(f.url.path)
                    }
                    .width(min: 200, ideal: 300)
                    TableColumn(L("Size"), value: \.size) { f in
                        Text(f.size.formattedBytes).monospacedDigit()
                    }
                    .width(min: 70, ideal: 90, max: 120)
                    TableColumn(L("Kind"), value: \.kindTitle) { f in
                        Label(f.kind.title, systemImage: f.kind.icon).foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 130, max: 180)
                    TableColumn(L("Last Used"), value: \.lastUsedSort) { f in
                        Text(f.lastUsed.map { $0.formatted(.relative(presentation: .named)) } ?? "—")
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 90, ideal: 120, max: 160)
                    TableColumn(L("Location"), value: \.parentPath) { f in
                        Text(f.parentPath).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .contextMenu(forSelectionType: FileEntry.ID.self) { ids in
                    let urls = items.filter { ids.contains($0.id) }.map(\.url)
                    if !urls.isEmpty {
                        if urls.count == 1, let u = urls.first {
                            Button(L("Quick Look")) { previewURL = u }
                            Button(L("Open")) { Finder.open(u) }
                        }
                        Button(L("Show in Finder")) { Finder.reveal(urls) }
                        Button(L("Copy Path")) { Finder.copyPaths(urls) }
                        Button(L("Archive to External Disk…")) {
                            let entries = items.filter { ids.contains($0.id) }
                            if let dest = state.chooseArchiveDestination() { Task { await state.archive(entries, to: dest) } }
                        }
                        Divider()
                        Button(L("Exclude (don’t suggest or delete)")) { urls.forEach(state.addExclusion) }
                        if urls.count == 1, let u = urls.first {
                            Button(L("Exclude Its Folder")) { state.addExclusion(u.deletingLastPathComponent()) }
                        }
                        Divider()
                        Button(L("Move to Trash…"), role: .destructive) {
                            selection = Set(urls.map(\.path))
                            confirm = true
                        }
                    }
                } primaryAction: { ids in
                    Finder.reveal(items.filter { ids.contains($0.id) }.map(\.url))
                }
                .onDeleteCommand { if !selected.isEmpty { confirm = true } }
                .onKeyPress(.space) {
                    guard let first = selected.first else { return .ignored }
                    previewURL = first.url
                    return .handled
                }
                .quickLookPreview($previewURL)
                Divider()
                HStack(spacing: 12) {
                    Text(L("\(items.count.formatted()) files · \(items.reduce(Int64(0)) { $0 + $1.size }.formattedBytes)"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let p = state.archiveProgress {
                        ProgressView(value: Double(p.done), total: Double(max(p.total, 1))).frame(width: 120)
                        Text(L("Archiving: \(p.current)")).font(.caption).lineLimit(1).truncationMode(.middle).frame(maxWidth: 200)
                    } else if !selected.isEmpty {
                        Text(L("Selected: \(selected.count) · \(selectedSize.formattedBytes)")).bold()
                        Button(L("Show in Finder")) { Finder.reveal(selected.map(\.url)) }
                        Button(L("Archive to External Disk…")) {
                            if let dest = state.chooseArchiveDestination() {
                                let entries = selected
                                selection = []
                                Task { await state.archive(entries, to: dest) }
                            }
                        }
                        .help(L("Copies, verifies with SHA-256, then moves the original to the Trash."))
                    }
                    Button(L("Move to Trash"), role: .destructive) { confirm = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(selected.isEmpty || state.isRemoving)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .confirmationDialog(L("Move \(selected.count) files to the Trash?"), isPresented: $confirm) {
            Button(L("Move to Trash (\(selectedSize.formattedBytes))"), role: .destructive) {
                let targets = selected.map { RemovalTarget(url: $0.url, size: $0.size, expectedModified: $0.modified) }
                selection = []
                Task { await state.remove(targets, permanently: false) }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Files can be restored from the Trash. The space is freed when the Trash is emptied."))
        }
    }

    private var filterBar: some View {
        HStack(spacing: 14) {
            Picker(L("At least"), selection: $minSize) {
                ForEach(Self.sizeOptions, id: \.1) { Text($0.0).tag($0.1) }
            }
            .frame(width: 140)
            Picker(L("Kind"), selection: $kind) {
                Text(L("All")).tag(FileKind?.none)
                Divider()
                ForEach(FileKind.allCases) { Label($0.title, systemImage: $0.icon).tag(FileKind?.some($0)) }
            }
            .frame(width: 200)
            Toggle(L("Unused for 6+ months"), isOn: $state.largeFilesStaleOnly)
                .fixedSize()
            Toggle(L("System files"), isOn: $showProtected)
                .fixedSize()
                .help(L("Files inside ~/Library and app bundles. Deleting them can break apps."))
            Spacer()
            TextField(L("Search"), text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120, maxWidth: 200)
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
