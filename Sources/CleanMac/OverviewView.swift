import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Genel Bakış").font(.title.bold())
                diskCard
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    StatCard(icon: "trash", color: .orange, title: "Gereksiz Dosyalar",
                             value: state.junkReady ? state.junkCategories.reduce(Int64(0)) { $0 + $1.size }.formattedBytes : "—",
                             note: state.junkReady ? "Önbellek, günlük, indirmeler" : "Henüz taranmadı") {
                        state.section = .junk
                    }
                    let big = state.files.filter { $0.size >= 100_000_000 && !$0.isProtected }
                    StatCard(icon: "doc.badge.arrow.up", color: .blue, title: "Büyük Dosyalar (>100 MB)",
                             value: state.rootNode == nil ? "—" : big.reduce(Int64(0)) { $0 + $1.size }.formattedBytes,
                             note: state.rootNode == nil ? "Henüz taranmadı" : "\(big.count) dosya") {
                        state.section = .largeFiles
                    }
                    StatCard(icon: "doc.on.doc", color: .purple, title: "Tekrarlanan Dosyalar",
                             value: state.duplicatesReady ? state.visibleDuplicateWaste.formattedBytes : "—",
                             note: state.duplicatesReady ? "\(state.duplicateGroups.count) grup, boşa giden alan" : "Henüz aranmadı") {
                        state.section = .duplicates
                    }
                    StatCard(icon: "shippingbox", color: .teal, title: "Proje Bağımlılıkları",
                             value: state.rootNode == nil ? "—" : state.devArtifactTotal.formattedBytes,
                             note: state.rootNode == nil ? "Henüz taranmadı" : "\(state.devArtifacts.count) klasör (node_modules vb.)") {
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
                        Text("\(d.used.formattedBytes) / \(d.total.formattedBytes) kullanılıyor")
                            .foregroundStyle(.secondary)
                    }
                    UsageBar(fraction: d.usedFraction, color: usageColor(d.usedFraction), height: 18)
                    HStack(spacing: 18) {
                        legend(usageColor(d.usedFraction), "Kullanılan", d.used)
                        legend(.secondary.opacity(0.3), "Boş", d.available)
                        Spacer()
                        Text(d.freeFraction.formatted(.percent.precision(.fractionLength(0))) + " boş")
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
                Text("\(root.url.abbreviatedPath) içinde en büyük öğeler").font(.title3.bold())
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
