import SwiftUI

struct GrowthView: View {
    @EnvironmentObject var state: AppState
    @State private var baselineIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L("What Grew?"), subtitle: L("A summary of every scan is kept; compare with earlier scans to find where your space went.")) {
                Button { state.startScan() } label: { Label(L("Scan Now"), systemImage: "arrow.clockwise") }
                    .disabled(state.isScanning)
            }
            Divider()
            if state.isScanning {
                ScanningView()
            } else if state.rootNode == nil {
                EmptyStateView(icon: "chart.line.uptrend.xyaxis", title: L("A scan is needed first"),
                               message: L("\(state.scanRoot.abbreviatedPath) needs to be scanned at least twice to compare. A summary is saved after the first scan."),
                               actionTitle: L("Start Scan")) { state.startScan() }
            } else if state.scanSnapshots.count < 2 {
                EmptyStateView(icon: "clock.badge.checkmark", title: L("First summary saved"),
                               message: L("The first scan summary for \(state.scanRoot.abbreviatedPath) was saved. Scan again in a few days to see what grew here."))
            } else {
                content
            }
        }
        .onChange(of: state.scanSnapshots.count) { baselineIndex = 0 }
    }

    private var content: some View {
        let current = state.scanSnapshots[0]
        let baselines = Array(state.scanSnapshots.dropFirst())
        let base = baselines[min(baselineIndex, baselines.count - 1)]
        let diff = GrowthDiff.compute(old: base, new: current)

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Picker(L("Compare:"), selection: $baselineIndex) {
                        ForEach(Array(baselines.enumerated()), id: \.offset) { i, s in
                            Text(s.date.formatted(date: .abbreviated, time: .shortened) + L(" (\(s.date.formatted(.relative(presentation: .named))))")).tag(i)
                        }
                    }
                    .frame(maxWidth: 420)
                    Spacer()
                }
                HStack(spacing: 14) {
                    deltaTile(L("Total change"), diff.totalDelta)
                    deltaTile(L("Folders that grew"), diff.grown.first.map(\.delta) ?? 0, note: diff.grown.first?.url.abbreviatedPath ?? "—")
                    deltaTile(L("New large files"), diff.newFiles.reduce(0) { $0 + $1.new }, note: L("\(diff.newFiles.count) files"))
                }
                section(L("Grew the most"), icon: "arrow.up.right", color: .orange, items: diff.grown, empty: L("No folders grew by more than 50 MB."))
                section(L("New large files (100 MB+)"), icon: "doc.badge.plus", color: .blue, items: diff.newFiles, empty: L("No new large files."))
                section(L("Shrank"), icon: "arrow.down.right", color: .green, items: diff.shrunk, empty: L("No folders shrank."))
                if !diff.goneFiles.isEmpty {
                    section(L("Large files that disappeared"), icon: "doc.badge.minus", color: .secondary, items: diff.goneFiles, empty: "")
                }
            }
            .padding(24)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
    }

    private func deltaTile(_ title: String, _ delta: Int64, note: String? = nil) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text((delta > 0 ? "+" : delta < 0 ? "−" : "") + abs(delta).formattedBytes)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(delta > 0 ? Color.orange : delta < 0 ? Color.green : Color.primary)
                if let note { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            }
        }
    }

    private func section(_ title: String, icon: String, color: Color, items: [GrowthItem], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(color)
            Card {
                if items.isEmpty {
                    Text(empty).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(items.prefix(15)) { item in
                            HStack(spacing: 10) {
                                FileIconView(url: item.url, size: 18)
                                Text(item.url.abbreviatedPath).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text("\(item.old.formattedBytes) → \(item.new.formattedBytes)")
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                Text((item.delta > 0 ? "+" : "−") + abs(item.delta).formattedBytes)
                                    .monospacedDigit().bold()
                                    .foregroundStyle(item.delta > 0 ? Color.orange : Color.green)
                                    .frame(width: 90, alignment: .trailing)
                            }
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button(L("Show in Finder")) { Finder.reveal([item.url]) }
                                Button(L("Open in Folder Explorer")) { open(item.path) }
                            }
                            .onTapGesture(count: 2) { open(item.path) }
                        }
                        if items.count > 15 {
                            Text(L("… and \(items.count - 15) more items")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func open(_ path: String) {
        guard let node = state.rootNode?.find(path: path) else { Finder.reveal([URL(fileURLWithPath: path)]); return }
        state.currentNode = node.canDrillDown ? node : node.parent
        state.section = .explorer
    }
}
