import QuickLook
import Charts
import SwiftUI

struct ExplorerView: View {
    @EnvironmentObject var state: AppState
    @State private var selection = Set<FileNode.ID>()
    @State private var pendingRemoval: [FileNode] = []
    @State private var previewURL: URL?
    @AppStorage("explorerTreemap") private var treemapMode = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L("Folder Explorer"), subtitle: subtitle) {
                Picker("", selection: $treemapMode) {
                    Image(systemName: "list.bullet").help(L("List")).tag(false)
                    Image(systemName: "square.grid.2x2").help("Treemap").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                ScanScopeMenu { state.startScan() }
                Button {
                    state.startScan()
                } label: { Label(state.rootNode == nil ? L("Scan") : L("Scan Again"), systemImage: "arrow.clockwise") }
                    .disabled(state.isScanning)
            }
            Divider()
            if state.isScanning {
                ScanningView()
            } else if let node = state.currentNode {
                breadcrumb(node)
                Divider()
                if treemapMode {
                    TreemapView(node: node) { pendingRemoval = [$0] }
                } else {
                    HStack(spacing: 0) {
                        list(node)
                        Divider()
                        DistributionChart(node: node).frame(width: 300)
                    }
                }
            } else {
                EmptyStateView(icon: "folder.badge.gearshape", title: L("No scan yet"),
                               message: L("Scan a folder to see, as a tree, how much space each folder and file takes up."),
                               actionTitle: L("Start Scan")) { state.startScan() }
            }
        }
        .confirmationDialog(L("Move the selected items to the Trash?"),
                            isPresented: Binding(get: { !pendingRemoval.isEmpty }, set: { if !$0 { pendingRemoval = [] } })) {
            Button(L("Move to Trash"), role: .destructive) {
                let targets = pendingRemoval.map { RemovalTarget(url: $0.url, size: $0.size) }
                pendingRemoval = []
                selection = []
                Task { await state.remove(targets, permanently: false) }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            let total = pendingRemoval.reduce(Int64(0)) { $0 + $1.size }
            Text(L("\(pendingRemoval.count) items (\(total.formattedBytes)) will be moved to the Trash. You can restore them from there if needed."))
        }
    }

    private var subtitle: String {
        guard let s = state.lastScan else { return L("Explore how much space your folders take up") }
        var text = L("\(s.root.abbreviatedPath) · \(s.totalFiles.formatted()) files · \(String(format: "%.1f", s.duration)) s")
        if s.unreadable > 0 { text += L(" · \(s.unreadable) folders couldn’t be read") }
        return text
    }

    private func breadcrumb(_ node: FileNode) -> some View {
        var chain: [FileNode] = []
        var n: FileNode? = node
        while let c = n {
            chain.insert(c, at: 0)
            n = c.parent
        }
        return HStack(spacing: 6) {
            Button {
                if let p = node.parent { navigate(to: p) }
            } label: { Image(systemName: "chevron.left") }
                .disabled(node.parent == nil)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(chain.enumerated()), id: \.element.id) { i, c in
                        if i > 0 {
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        Button(c.name) { navigate(to: c) }
                            .buttonStyle(.plain)
                            .fontWeight(c === node ? .semibold : .regular)
                            .foregroundStyle(c === node ? Color.primary : Color.secondary)
                    }
                }
            }
            Text(L("\(node.size.formattedBytes) · \(node.fileCount.formatted()) files"))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func navigate(to node: FileNode) {
        state.currentNode = node
        selection = []
    }

    private func resolve(_ ids: Set<FileNode.ID>, in node: FileNode) -> [FileNode] {
        node.children.filter { ids.contains($0.id) && !$0.isAggregate }
    }

    private func list(_ node: FileNode) -> some View {
        List(node.children, selection: $selection) { child in
            ExplorerRow(node: child, parentSize: node.size, isExcluded: state.isExcluded(child.url.path))
        }
        .contextMenu(forSelectionType: FileNode.ID.self) { ids in
            let nodes = resolve(ids, in: node)
            if !nodes.isEmpty {
                if nodes.count == 1, let n = nodes.first, n.canDrillDown {
                    Button(L("Open")) { navigate(to: n) }
                }
                if nodes.count == 1, let n = nodes.first { Button(L("Quick Look")) { previewURL = n.url } }
                Button(L("Show in Finder")) { Finder.reveal(nodes.map(\.url)) }
                Button(L("Copy Path")) { Finder.copyPaths(nodes.map(\.url)) }
                Divider()
                if nodes.allSatisfy({ state.excludedPaths.contains($0.url.path) }) {
                    Button(L("Remove from Exclusions")) { nodes.forEach { state.removeExclusion($0.url.path) } }
                } else {
                    Button(L("Exclude (don’t suggest or delete)")) { nodes.forEach { state.addExclusion($0.url) } }
                }
                Divider()
                Button(L("Move to Trash…"), role: .destructive) { pendingRemoval = nodes }
            }
        } primaryAction: { ids in
            let nodes = resolve(ids, in: node)
            guard nodes.count == 1, let n = nodes.first else { return }
            if n.canDrillDown { navigate(to: n) } else { Finder.reveal([n.url]) }
        }
        .onDeleteCommand {
            let nodes = resolve(selection, in: node)
            if !nodes.isEmpty { pendingRemoval = nodes }
        }
        .onKeyPress(.space) {
            guard let n = resolve(selection, in: node).first else { return .ignored }
            previewURL = n.url
            return .handled
        }
        .quickLookPreview($previewURL)
    }
}

private struct ExplorerRow: View {
    let node: FileNode
    let parentSize: Int64
    var isExcluded = false

    private var fraction: Double { parentSize > 0 ? Double(node.size) / Double(parentSize) : 0 }

    var body: some View {
        HStack(spacing: 10) {
            if node.isAggregate {
                Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary).frame(width: 22)
            } else {
                FileIconView(url: node.url, size: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(node.name).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(node.isAggregate ? .secondary : .primary)
                    if isExcluded {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                            .help(L("Excluded: never suggested or deleted"))
                    }
                }
                if node.isDirectory {
                    Text(L("\(node.fileCount.formatted()) files")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            UsageBar(fraction: fraction, color: fraction > 0.5 ? .orange : .accentColor).frame(width: 140)
            Text(fraction.formatted(.percent.precision(.fractionLength(1))))
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            Text(node.size.formattedBytes).monospacedDigit().frame(width: 84, alignment: .trailing)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                .opacity(node.canDrillDown ? 1 : 0)
        }
        .padding(.vertical, 3)
    }
}

private struct DistributionChart: View {
    let node: FileNode

    struct Slice: Identifiable {
        let id: String
        let size: Int64
    }

    private var slices: [Slice] {
        let items = node.children.filter { $0.size > 0 }
        var out = items.prefix(6).map { Slice(id: $0.name, size: $0.size) }
        let rest = items.dropFirst(6).reduce(Int64(0)) { $0 + $1.size }
        if rest > 0 { out.append(Slice(id: L("Other"), size: rest)) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Distribution")).font(.headline)
            if slices.isEmpty {
                Text(L("This folder is empty.")).foregroundStyle(.secondary)
            } else {
                Chart(slices) { s in
                    SectorMark(angle: .value(L("Size"), Double(s.size)), innerRadius: .ratio(0.58), angularInset: 1.5)
                        .cornerRadius(3)
                        .foregroundStyle(by: .value(L("Item"), s.id))
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                .chartBackground { _ in
                    VStack(spacing: 2) {
                        Text(node.size.formattedBytes).font(.title3.bold())
                        Text(L("total")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 340)
            }
            Spacer()
            Text(L("Tip: double-click a folder to open it; right-click to show it in Finder or move it to the Trash."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }
}
