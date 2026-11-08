import SwiftUI

struct GrowthView: View {
    @EnvironmentObject var state: AppState
    @State private var baselineIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Ne Büyüdü?", subtitle: "Her taramanın özeti saklanır; alanın nereye gittiğini önceki taramalarla karşılaştırarak bul.") {
                Button { state.startScan() } label: { Label("Şimdi Tara", systemImage: "arrow.clockwise") }
                    .disabled(state.isScanning)
            }
            Divider()
            if state.isScanning {
                ScanningView()
            } else if state.rootNode == nil {
                EmptyStateView(icon: "chart.line.uptrend.xyaxis", title: "Önce bir tarama gerekli",
                               message: "Karşılaştırma için \(state.scanRoot.abbreviatedPath) en az iki kez taranmalı. İlk taramadan sonra özet saklanır.",
                               actionTitle: "Taramayı Başlat") { state.startScan() }
            } else if state.scanSnapshots.count < 2 {
                EmptyStateView(icon: "clock.badge.checkmark", title: "İlk özet kaydedildi",
                               message: "\(state.scanRoot.abbreviatedPath) için ilk tarama özeti saklandı. Birkaç gün sonra tekrar tara; neyin büyüdüğünü burada göreceksin.")
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
                    Picker("Karşılaştır:", selection: $baselineIndex) {
                        ForEach(Array(baselines.enumerated()), id: \.offset) { i, s in
                            Text(s.date.formatted(date: .abbreviated, time: .shortened) + " (\(s.date.formatted(.relative(presentation: .named))))").tag(i)
                        }
                    }
                    .frame(maxWidth: 420)
                    Spacer()
                }
                HStack(spacing: 14) {
                    deltaTile("Toplam değişim", diff.totalDelta)
                    deltaTile("Büyüyen klasörler", diff.grown.first.map(\.delta) ?? 0, note: diff.grown.first?.url.abbreviatedPath ?? "—")
                    deltaTile("Yeni büyük dosyalar", diff.newFiles.reduce(0) { $0 + $1.new }, note: "\(diff.newFiles.count) dosya")
                }
                section("En çok büyüyenler", icon: "arrow.up.right", color: .orange, items: diff.grown, empty: "50 MB'tan fazla büyüyen klasör yok.")
                section("Yeni büyük dosyalar (100 MB+)", icon: "doc.badge.plus", color: .blue, items: diff.newFiles, empty: "Yeni büyük dosya yok.")
                section("Küçülenler", icon: "arrow.down.right", color: .green, items: diff.shrunk, empty: "Küçülen klasör yok.")
                if !diff.goneFiles.isEmpty {
                    section("Kaybolan büyük dosyalar", icon: "doc.badge.minus", color: .secondary, items: diff.goneFiles, empty: "")
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
                                Button("Finder'da Göster") { Finder.reveal([item.url]) }
                                Button("Klasör Gezgini'nde Aç") { open(item.path) }
                            }
                            .onTapGesture(count: 2) { open(item.path) }
                        }
                        if items.count > 15 {
                            Text("… ve \(items.count - 15) öğe daha").font(.caption).foregroundStyle(.secondary)
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
