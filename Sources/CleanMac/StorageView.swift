import SwiftUI

struct StorageView: View {
    @EnvironmentObject var state: AppState
    @State private var pendingSnapshots: [LocalSnapshot] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Storage Breakdown")).font(.title.bold())
                        Text(L("How disk space is split across volumes, and the space the scan can’t see")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await state.loadStorage() }
                    } label: { Label(L("Refresh"), systemImage: "arrow.clockwise") }
                        .disabled(state.isLoadingStorage)
                }
                if let r = state.storage {
                    containerCard(r)
                    gapCard(r)
                    snapshotsCard(r)
                    volumesCard(r)
                } else if state.isLoadingStorage {
                    ProgressView(L("Reading volumes…")).frame(maxWidth: .infinity).padding(40)
                } else {
                    EmptyStateView(icon: "internaldrive", title: L("Couldn’t get volume information"),
                                   message: L("Couldn’t read the diskutil output."))
                }
            }
            .padding(24)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .task { if state.storage == nil { await state.loadStorage() } }
        .confirmationDialog(L("Delete \(pendingSnapshots.count) snapshots?"),
                            isPresented: Binding(get: { !pendingSnapshots.isEmpty }, set: { if !$0 { pendingSnapshots = [] } })) {
            Button(L("Delete"), role: .destructive) {
                let snaps = pendingSnapshots
                pendingSnapshots = []
                Task { await state.deleteSnapshots(snaps) }
            }
        } message: {
            Text(L("Local Time Machine snapshots provide restore points while your backup disk isn’t connected. Deleting them frees space; your backups on the external disk aren’t touched. An administrator password may be requested."))
        }
    }

    private static let palette: [Color] = [.blue, .purple, .orange, .teal, .pink, .green, .yellow]

    private func containerCard(_ r: StorageReport) -> some View {
        let segments = r.volumes.filter { $0.used > 50_000_000 }
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(L("Startup disk"), systemImage: "internaldrive.fill").font(.title3.bold())
                    Spacer()
                    Text(L("\(r.capacity.formattedBytes) capacity")).foregroundStyle(.secondary)
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
                           + [(Color.gray.opacity(0.45), L("Purgeable (freed by macOS)"), r.purgeable),
                              (Color.secondary.opacity(0.15), L("Free"), r.free)])
            }
        }
    }

    @ViewBuilder private func gapCard(_ r: StorageReport) -> some View {
        if let data = r.dataVolume, let root = state.rootNode, root.url.path == "/" {
            // The sealed system volume is compressed, so the /System size from the scan is used.
            let system = root.children.first { $0.url.path == "/System" }?.size ?? 0
            let scannedData = max(root.size - system, 0)
            let gap = data.used - scannedData
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L("Space on the Data volume not visible to the scan: \(max(gap, 0).formattedBytes)"), systemImage: "eye.slash")
                        .font(.headline)
                    Text(L("The Data volume uses \(data.used.formattedBytes); the scan could see \(scannedData.formattedBytes) of it. The difference usually comes from unreadable folders (\(state.lastScan?.unreadable ?? 0) folders), other users’ files, the Spotlight index and system caches."))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !state.hasFullDiskAccess {
                        Button(L("Give Full Disk Access (to see more)")) { Finder.openFullDiskAccessSettings() }
                    }
                }
            }
        } else {
            Card {
                Label {
                    Text(.init(L("To calculate the hidden space on the Data volume, set the Scope to **Entire Mac** and scan.")))
                } icon: { Image(systemName: "info.circle") }
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func snapshotsCard(_ r: StorageReport) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(L("Local Time Machine snapshots"), systemImage: "clock.arrow.circlepath").font(.headline)
                    Spacer()
                    if r.snapshots.count > 1 {
                        Button(L("Delete All"), role: .destructive) { pendingSnapshots = r.snapshots }
                    }
                }
                if r.snapshots.isEmpty {
                    Label(L("No local snapshots."), systemImage: "checkmark.circle").foregroundStyle(.green)
                } else {
                    Text(L("macOS deletes snapshots automatically as the disk fills up, but they can hold space for a long time. macOS doesn’t report their sizes."))
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(r.snapshots) { s in
                        HStack {
                            Image(systemName: "camera.metering.center.weighted").foregroundStyle(.secondary)
                            Text(s.date?.formatted(date: .abbreviated, time: .shortened) ?? s.dateString)
                            Spacer()
                            Button(L("Delete"), role: .destructive) { pendingSnapshots = [s] }
                        }
                    }
                }
            }
        }
    }

    private func volumesCard(_ r: StorageReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Volumes")).font(.title3.bold())
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
