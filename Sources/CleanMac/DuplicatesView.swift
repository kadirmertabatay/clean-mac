import QuickLook
import SwiftUI

struct DuplicatesView: View {
    @EnvironmentObject var state: AppState
    @State private var selected = Set<String>()
    @State private var showProtected = false
    @State private var confirm = false
    @State private var warning: String?
    @State private var previewURL: URL?

    private static let sizeOptions: [(String, Int64)] = [
        ("1 MB", 1_000_000), ("10 MB", 10_000_000), ("50 MB", 50_000_000), ("100 MB", 100_000_000),
    ]

    private var groups: [DuplicateGroup] {
        state.duplicateGroups.compactMap { g in
            let files = g.files.filter { (showProtected || !$0.isProtected) && !state.isExcluded($0.id) }
            return files.count > 1 ? DuplicateGroup(id: g.id, size: g.size, files: files) : nil
        }
    }

    var body: some View {
        let groups = groups
        let selectedFiles = groups.flatMap(\.files).filter { selected.contains($0.id) }
        let selectedSize = selectedFiles.reduce(Int64(0)) { $0 + $1.size }

        VStack(spacing: 0) {
            PageHeader(title: L("Duplicate Files"), subtitle: L("Files with exactly the same content (verified with SHA-256)")) {
                Picker(L("At least"), selection: $state.duplicateMinSize) {
                    ForEach(Self.sizeOptions, id: \.1) { Text($0.0).tag($0.1) }
                }
                .frame(width: 130)
                Button {
                    selected = []
                    Task { await state.findDuplicates() }
                } label: { Label(state.duplicatesReady ? L("Search Again") : L("Find Duplicates"), systemImage: "magnifyingglass") }
                    .disabled(state.isScanning || state.isFindingDuplicates)
            }
            Divider()
            if state.isScanning {
                ScanningView()
            } else if state.isFindingDuplicates {
                VStack(spacing: 14) {
                    ProgressView(value: state.duplicateProgress).frame(width: 320)
                    Text(L("Comparing files… \(state.duplicateProgress.formatted(.percent.precision(.fractionLength(0))))"))
                    Button(L("Stop")) { state.cancelScan() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !state.duplicatesReady {
                EmptyStateView(icon: "doc.on.doc", title: L("Find duplicate files"),
                               message: L("Files in \(state.scanRoot.abbreviatedPath) are compared by size and a content digest. Files are only read; nothing is changed."),
                               actionTitle: L("Find Duplicates")) { Task { await state.findDuplicates() } }
            } else if groups.isEmpty {
                EmptyStateView(icon: "checkmark.circle", title: L("No duplicate files"),
                               message: L("No files with the same content above the selected size were found."))
            } else {
                List {
                    ForEach(groups) { g in
                        Section {
                            ForEach(Array(g.files.enumerated()), id: \.element.id) { i, f in
                                row(f, isOriginal: i == 0)
                            }
                        } header: {
                            HStack {
                                Text(L("\(g.files.count) copies · \(g.size.formattedBytes) each"))
                                Spacer()
                                Text(L("Wasted: \(g.wasted.formattedBytes)")).foregroundStyle(.orange)
                            }
                        }
                    }
                }
                Divider()
                HStack(spacing: 12) {
                    Text(L("\(groups.count) groups · \(groups.reduce(Int64(0)) { $0 + $1.wasted }.formattedBytes) wasted"))
                        .foregroundStyle(.secondary)
                    Toggle(L("System files"), isOn: $showProtected)
                        .toggleStyle(.checkbox)
                        .fixedSize()
                        .help(L("Also show copies inside ~/Library and app bundles."))
                    Spacer()
                    Button(L("Smart Select")) { smartSelect(groups) }
                        .help(L("Keeps the oldest file in each group and selects the other copies."))
                    Button(L("Clear Selection")) { selected = [] }.disabled(selected.isEmpty)
                    Button(L("Move to Trash (\(selectedFiles.count))"), role: .destructive) {
                        if let problem = validate(groups) { warning = problem } else { confirm = true }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(selectedFiles.isEmpty || state.isRemoving)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .confirmationDialog(L("Move \(selectedFiles.count) copies to the Trash?"), isPresented: $confirm) {
            Button(L("Move to Trash (\(selectedSize.formattedBytes))"), role: .destructive) {
                // For every removed copy, at least one unselected copy from the same group must still exist.
                let targets = groups.flatMap { g -> [RemovalTarget] in
                    let keep = g.files.filter { !selected.contains($0.id) }.map(\.url)
                    return g.files.filter { selected.contains($0.id) }.map {
                        RemovalTarget(url: $0.url, size: $0.size, expectedModified: $0.modified, keepAnyOf: keep)
                    }
                }
                selected = []
                Task { await state.remove(targets, permanently: false) }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("At least one copy from each group will be kept. Files can be restored from the Trash."))
        }
        .quickLookPreview($previewURL)
        .alert(L("Warning"), isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } })) {
            Button(L("OK")) {}
        } message: {
            Text(warning ?? "")
        }
    }

    private func row(_ f: FileEntry, isOriginal: Bool) -> some View {
        HStack(spacing: 10) {
            Checkbox(state: selected.contains(f.id) ? .on : .off) {
                if selected.contains(f.id) { selected.remove(f.id) } else { selected.insert(f.id) }
            }
            FileIconView(url: f.url, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(f.name).lineLimit(1)
                    if isOriginal {
                        Text(L("oldest")).font(.caption2.bold()).foregroundStyle(.green)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.green.opacity(0.15), in: Capsule())
                    }
                }
                Text(f.parentPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(f.modified?.formatted(date: .abbreviated, time: .shortened) ?? "")
                .font(.caption).foregroundStyle(.secondary)
            Button { previewURL = f.url } label: { Image(systemName: "eye") }
                .buttonStyle(.borderless)
                .help(L("Quick Look"))
            Button { Finder.reveal([f.url]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help(L("Show in Finder"))
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(L("Quick Look")) { previewURL = f.url }
            Button(L("Show in Finder")) { Finder.reveal([f.url]) }
            Button(L("Exclude")) { state.addExclusion(f.url) }
            Button(L("Exclude Its Folder")) { state.addExclusion(f.url.deletingLastPathComponent()) }
        }
    }

    private func smartSelect(_ groups: [DuplicateGroup]) {
        var s = Set<String>()
        for g in groups { for f in g.files.dropFirst() { s.insert(f.id) } }
        selected = s
    }

    private func validate(_ groups: [DuplicateGroup]) -> String? {
        let full = groups.filter { g in g.files.allSatisfy { selected.contains($0.id) } }
        guard !full.isEmpty else { return nil }
        return L("All copies are selected in \(full.count) groups. To avoid losing data, deselect at least one file from each group.")
    }
}
