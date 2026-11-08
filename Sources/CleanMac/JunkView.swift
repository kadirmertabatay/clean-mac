import SwiftUI

struct JunkView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("permanentDelete") private var permanentDelete = false
    @State private var selected = Set<String>()
    @State private var expanded = Set<String>()
    @State private var confirm = false

    private struct Target {
        let target: RemovalTarget
        let permanentOnly: Bool
    }

    private var targets: [Target] {
        var out: [Target] = []
        for c in state.junkCategories {
            for i in c.items where selected.contains(i.id) {
                out.append(Target(target: RemovalTarget(url: i.url, size: i.size), permanentOnly: c.permanentOnly))
            }
        }
        for n in state.visibleDevArtifacts where selected.contains(n.url.path) {
            out.append(Target(target: RemovalTarget(url: n.url, size: n.size), permanentOnly: false))
        }
        return out
    }

    var body: some View {
        let targets = targets
        let total = targets.reduce(Int64(0)) { $0 + $1.target.size }

        VStack(spacing: 0) {
            PageHeader(title: L("Junk Files"), subtitle: L("Caches, logs, developer leftovers and forgotten downloads")) {
                Button {
                    selected = []
                    Task { await state.scanJunk() }
                } label: { Label(L("Scan Again"), systemImage: "arrow.clockwise") }
                    .disabled(state.isScanningJunk)
            }
            Divider()
            if state.isScanningJunk && !state.junkReady {
                ProgressView(L("Scanning known locations…")).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !state.junkReady {
                EmptyStateView(icon: "trash", title: L("Scan for junk files"),
                               message: L("Find files left behind by caches, logs and developer tools."),
                               actionTitle: L("Scan")) { Task { await state.scanJunk() } }
            } else {
                List {
                    ForEach(state.junkCategories) { category in
                        categoryRow(category)
                    }
                    devArtifactsSection
                }
                Divider()
                HStack(spacing: 12) {
                    Toggle(L("Delete permanently (skip the Trash)"), isOn: $permanentDelete)
                        .toggleStyle(.checkbox)
                        .fixedSize()
                        .help(L("When off, items are moved to the Trash and can be restored."))
                    Spacer()
                    Button(L("Select All Safe Items")) {
                        for c in state.junkCategories where c.safety == .safe && !c.permanentOnly {
                            c.items.forEach { selected.insert($0.id) }
                        }
                    }
                    if !selected.isEmpty { Button(L("Clear Selection")) { selected = [] } }
                    Button(total > 0 ? L("Clean (\(total.formattedBytes))") : L("Clean"), role: .destructive) { confirm = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(targets.isEmpty || state.isRemoving)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .task {
            if !state.junkReady && !state.isScanningJunk { await state.scanJunk() }
        }
        .confirmationDialog(L("Clean \(targets.count) items?"), isPresented: $confirm) {
            Button(L("Clean (\(total.formattedBytes))"), role: .destructive) { clean(targets) }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            let permanentCount = targets.filter { $0.permanentOnly || permanentDelete }.count
            if permanentCount == targets.count {
                Text(L("The items will be deleted permanently. This can’t be undone."))
            } else if permanentCount > 0 {
                Text(L("\(targets.count - permanentCount) items will be moved to the Trash, and \(permanentCount) items in the Trash will be deleted permanently."))
            } else {
                Text(L("The items will be moved to the Trash and can be restored from there. The space is freed when the Trash is emptied."))
            }
        }
    }

    private func clean(_ targets: [Target]) {
        let permanent = targets.filter { $0.permanentOnly || permanentDelete }.map(\.target)
        let toTrash = targets.filter { !($0.permanentOnly || permanentDelete) }.map(\.target)
        selected = []
        Task {
            if !toTrash.isEmpty { await state.remove(toTrash, permanently: false) }
            if !permanent.isEmpty { await state.remove(permanent, permanently: true) }
        }
    }

    private func checkState(_ c: JunkCategory) -> Checkbox.CheckState {
        let n = c.items.filter { selected.contains($0.id) }.count
        return n == 0 ? .off : n == c.items.count ? .on : .mixed
    }

    private func toggle(_ c: JunkCategory) {
        if checkState(c) == .on {
            c.items.forEach { selected.remove($0.id) }
        } else {
            c.items.forEach { selected.insert($0.id) }
        }
    }

    private func toggleItem(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func categoryRow(_ c: JunkCategory) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expanded.contains(c.id) },
            set: { if $0 { expanded.insert(c.id) } else { expanded.remove(c.id) } }
        )) {
            ForEach(c.items.prefix(300)) { item in
                HStack(spacing: 10) {
                    Checkbox(state: selected.contains(item.id) ? .on : .off) { toggleItem(item.id) }
                    FileIconView(url: item.url, size: 18)
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if let d = item.date {
                        Text(d.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(item.size.formattedBytes).monospacedDigit().frame(width: 80, alignment: .trailing)
                    Button { Finder.reveal([item.url]) } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.borderless)
                }
                .padding(.leading, 8)
                .contextMenu {
                    Button(L("Show in Finder")) { Finder.reveal([item.url]) }
                    Button(L("Exclude (don’t suggest or delete)")) {
                        selected.remove(item.id)
                        state.addExclusion(item.url)
                    }
                }
            }
            if c.items.count > 300 {
                Text(L("… and \(c.items.count - 300) more items (all are included when the category is selected)"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } label: {
            HStack(spacing: 12) {
                Checkbox(state: checkState(c)) { toggle(c) }
                    .disabled(c.items.isEmpty)
                Image(systemName: c.icon)
                    .font(.title3)
                    .foregroundStyle(c.safety == .safe ? Color.green : Color.orange)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(c.title).font(.headline)
                        SafetyBadge(safety: c.safety)
                    }
                    Text(c.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if c.items.isEmpty && !c.deniedPaths.isEmpty {
                    Button {
                        Finder.openFullDiskAccessSettings()
                    } label: {
                        Label(L("No access"), systemImage: "lock.fill").font(.callout).foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .help(L("This location couldn’t be read. Give CleanMac Full Disk Access to see it. (Click to open settings)"))
                } else if c.items.isEmpty {
                    Label(L("All clean"), systemImage: "checkmark").font(.callout).foregroundStyle(.green)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(c.size.formattedBytes).font(.headline).monospacedDigit()
                        Text(L("\(c.items.count) items")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder private var devArtifactsSection: some View {
        if state.rootNode == nil {
            Section(L("Project Dependencies")) {
                Text(L("Run a scan from the Folder Explorer first to find folders like node_modules, .venv and Pods."))
                    .foregroundStyle(.secondary)
            }
        } else if !state.visibleDevArtifacts.isEmpty {
            Section {
                ForEach(state.visibleDevArtifacts) { node in
                    HStack(spacing: 10) {
                        Checkbox(state: selected.contains(node.url.path) ? .on : .off) { toggleItem(node.url.path) }
                        Image(systemName: "shippingbox").foregroundStyle(.teal).frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.name)
                            Text(node.url.deletingLastPathComponent().abbreviatedPath)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(node.size.formattedBytes).monospacedDigit().frame(width: 80, alignment: .trailing)
                        Button { Finder.reveal([node.url]) } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.borderless)
                    }
                    .contextMenu {
                        Button(L("Show in Finder")) { Finder.reveal([node.url]) }
                        Button(L("Exclude Project (active project)")) {
                            selected.remove(node.url.path)
                            state.addExclusion(node.url.deletingLastPathComponent())
                        }
                    }
                }
            } header: {
                HStack {
                    Text(L("Project Dependencies (in \(state.scanRoot.abbreviatedPath))"))
                    SafetyBadge(safety: .review)
                    Spacer()
                    Text(state.devArtifactTotal.formattedBytes)
                }
            }
        }
    }
}
