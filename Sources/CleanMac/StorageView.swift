import SwiftUI

struct StorageView: View {
    @EnvironmentObject var state: AppState
    @State private var pendingSnapshots: [LocalSnapshot] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Depolama Dökümü").font(.title.bold())
                        Text("Disk alanının birimlere göre dağılımı ve taramanın göremediği alanlar").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await state.loadStorage() }
                    } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                        .disabled(state.isLoadingStorage)
                }
                if let r = state.storage {
                    containerCard(r)
                    gapCard(r)
                    snapshotsCard(r)
                    volumesCard(r)
                } else if state.isLoadingStorage {
                    ProgressView("Birimler okunuyor…").frame(maxWidth: .infinity).padding(40)
                } else {
                    EmptyStateView(icon: "internaldrive", title: "Birim bilgisi alınamadı",
                                   message: "diskutil çıktısı okunamadı.")
                }
            }
            .padding(24)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .task { if state.storage == nil { await state.loadStorage() } }
        .confirmationDialog("\(pendingSnapshots.count) anlık görüntü silinsin mi?",
                            isPresented: Binding(get: { !pendingSnapshots.isEmpty }, set: { if !$0 { pendingSnapshots = [] } })) {
            Button("Sil", role: .destructive) {
                let snaps = pendingSnapshots
                pendingSnapshots = []
                Task { await state.deleteSnapshots(snaps) }
            }
        } message: {
            Text("Yerel Time Machine anlık görüntüleri, yedekleme diskin bağlı değilken geri dönüş noktası sağlar. Silmek yer açar; harici diskteki yedeklerine dokunulmaz. Yönetici parolası istenebilir.")
        }
    }

    private static let palette: [Color] = [.blue, .purple, .orange, .teal, .pink, .green, .yellow]

    private func containerCard(_ r: StorageReport) -> some View {
        let segments = r.volumes.filter { $0.used > 50_000_000 }
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Başlangıç diski", systemImage: "internaldrive.fill").font(.title3.bold())
                    Spacer()
                    Text("\(r.capacity.formattedBytes) kapasite").foregroundStyle(.secondary)
                }
                GeometryReader { g in
                    HStack(spacing: 1) {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { i, v in
                            Self.palette[i % Self.palette.count]
                                .frame(width: g.size.width * CGFloat(v.used) / CGFloat(max(r.capacity, 1)))
                        }
                        Color.gray.opacity(0.45)
                            .frame(width: g.size.width * CGFloat(r.purgeable) / CGFloat(max(r.capacity, 1)))
                        Color.secondary.opacity(0.15)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(height: 22)
                FlowLegend(items: segments.enumerated().map { (Self.palette[$0.offset % Self.palette.count], $0.element.title, $0.element.used) }
                           + [(Color.gray.opacity(0.45), "Temizlenebilir (macOS boşaltır)", r.purgeable),
                              (Color.secondary.opacity(0.15), "Boş", r.free)])
            }
        }
    }

    @ViewBuilder private func gapCard(_ r: StorageReport) -> some View {
        if let data = r.dataVolume, let root = state.rootNode, root.url.path == "/" {
            // Mühürlü sistem birimi sıkıştırıldığı için taramadaki /System boyutu esas alınır.
            let system = root.children.first { $0.url.path == "/System" }?.size ?? 0
            let scannedData = max(root.size - system, 0)
            let gap = data.used - scannedData
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Veri biriminde taramada görünmeyen alan: \(max(gap, 0).formattedBytes)", systemImage: "eye.slash")
                        .font(.headline)
                    Text("Veri birimi \(data.used.formattedBytes) kullanıyor, tarama bunun \(scannedData.formattedBytes) kadarını görebildi. Fark genellikle okunamayan klasörlerden (\(state.lastScan?.unreadable ?? 0) klasör), başka kullanıcıların dosyalarından, Spotlight dizininden ve sistem önbelleklerinden gelir.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !state.hasFullDiskAccess {
                        Button("Tam Disk Erişimi ver (daha fazlasını görmek için)") { Finder.openFullDiskAccessSettings() }
                    }
                }
            }
        } else {
            Card {
                Label {
                    Text("Veri birimindeki görünmeyen alanı hesaplamak için Kapsam'ı **Tüm Mac** yapıp tarama yap.")
                } icon: { Image(systemName: "info.circle") }
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func snapshotsCard(_ r: StorageReport) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Yerel Time Machine anlık görüntüleri", systemImage: "clock.arrow.circlepath").font(.headline)
                    Spacer()
                    if r.snapshots.count > 1 {
                        Button("Tümünü Sil", role: .destructive) { pendingSnapshots = r.snapshots }
                    }
                }
                if r.snapshots.isEmpty {
                    Label("Yerel anlık görüntü yok.", systemImage: "checkmark.circle").foregroundStyle(.green)
                } else {
                    Text("Anlık görüntüler disk dolarken macOS tarafından kendiliğinden silinir, ancak uzun süre yer tutabilir. Boyutları macOS tarafından raporlanmaz.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(r.snapshots) { s in
                        HStack {
                            Image(systemName: "camera.metering.center.weighted").foregroundStyle(.secondary)
                            Text(s.date?.formatted(date: .abbreviated, time: .shortened) ?? s.dateString)
                            Spacer()
                            Button("Sil", role: .destructive) { pendingSnapshots = [s] }
                        }
                    }
                }
            }
        }
    }

    private func volumesCard(_ r: StorageReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Birimler").font(.title3.bold())
            Card {
                VStack(spacing: 12) {
                    ForEach(r.volumes) { v in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.title).font(.headline)
                                Text(v.explanation).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(v.used.formattedBytes).monospacedDigit().font(.headline)
                        }
                        if v.id != r.volumes.last?.id { Divider() }
                    }
                }
            }
        }
    }
}

private struct FlowLegend: View {
    let items: [(Color, String, Int64)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(item.0).frame(width: 10, height: 10)
                    Text(item.1).foregroundStyle(.secondary).lineLimit(1)
                    Text(item.2.formattedBytes).bold()
                }
                .font(.caption)
            }
        }
    }
}
