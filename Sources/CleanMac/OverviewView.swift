import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("Overview")).font(.title.bold())
                diskCard
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    StatCard(icon: "trash", color: .orange, title: L("Junk Files"),
                             value: state.junkReady ? state.junkCategories.reduce(Int64(0)) { $0 + $1.size }.formattedBytes : "—",
                             note: state.junkReady ? L("Caches, logs, downloads") : L("Not scanned yet")) {
                        state.section = .junk
                    }
                    let big = state.files.filter { $0.size >= 100_000_000 && !$0.isProtected && !state.isExcluded($0.id) }
                    StatCard(icon: "doc.badge.arrow.up", color: .blue, title: L("Large Files (>100 MB)"),
                             value: state.rootNode == nil ? "—" : big.reduce(Int64(0)) { $0 + $1.size }.formattedBytes,
                             note: state.rootNode == nil ? L("Not scanned yet") : L("\(big.count) files")) {
                        state.section = .largeFiles
                    }
                    StatCard(icon: "doc.on.doc", color: .purple, title: L("Duplicate Files"),
                             value: state.duplicatesReady ? state.visibleDuplicateWaste.formattedBytes : "—",
                             note: state.duplicatesReady ? L("\(state.duplicateGroups.count) groups, wasted space") : L("Not searched yet")) {
                        state.section = .duplicates
                    }
                    StatCard(icon: "shippingbox", color: .teal, title: L("Project Dependencies"),
                             value: state.rootNode == nil ? "—" : state.devArtifactTotal.formattedBytes,
                             note: state.rootNode == nil ? L("Not scanned yet") : L("\(state.visibleDevArtifacts.count) folders (node_modules etc.)")) {
                        state.section = .junk
                    }
                }
                topFolders
            }
            .padding(24)
        }
    }

    @ViewBuilder private var diskCard: some View {
        if let d = state.disk {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(d.name, systemImage: "internaldrive.fill").font(.title3.bold())
                        Spacer()
                        Text(L("\(d.used.formattedBytes) of \(d.total.formattedBytes) used"))
                            .foregroundStyle(.secondary)
                    }
                    UsageBar(fraction: d.usedFraction, color: usageColor(d.usedFraction), height: 18)
                    HStack(spacing: 18) {
                        legend(usageColor(d.usedFraction), L("Used"), d.used)
                        legend(.secondary.opacity(0.3), L("Free"), d.available)
                        Spacer()
                        Text(d.freeFraction.formatted(.percent.precision(.fractionLength(0))) + L(" free"))
                            .font(.headline)
                    }
                }
            }
        }
    }

    private func legend(_ color: Color, _ title: String, _ value: Int64) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title).foregroundStyle(.secondary)
            Text(value.formattedBytes).bold()
        }
    }

    @ViewBuilder private var topFolders: some View {
        if let root = state.rootNode {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Largest items in \(root.url.abbreviatedPath)")).font(.title3.bold())
                Card {
                    VStack(spacing: 10) {
                        ForEach(root.children.filter { !$0.isAggregate }.prefix(10)) { child in
                            Button {
                                if child.canDrillDown { state.currentNode = child } else { state.currentNode = root }
                                state.section = .explorer
                            } label: {
                                HStack(spacing: 10) {
                                    FileIconView(url: child.url, size: 20)
                                    Text(child.name).lineLimit(1).frame(width: 220, alignment: .leading)
                                    UsageBar(fraction: root.size > 0 ? Double(child.size) / Double(root.size) : 0)
                                    Text(child.size.formattedBytes).monospacedDigit().frame(width: 80, alignment: .trailing)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

private struct StatCard: View {
    let icon: String
    let color: Color
    let title: String
    let value: String
    let note: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: icon).font(.title2).foregroundStyle(color)
                    Text(title).font(.subheadline).foregroundStyle(.secondary)
                    Text(value).font(.system(size: 24, weight: .bold, design: .rounded))
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
