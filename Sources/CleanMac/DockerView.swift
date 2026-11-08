import SwiftUI

struct DockerView: View {
    @EnvironmentObject var state: AppState
    @State private var tab = Tab.summary
    @State private var imageSel = Set<String>()
    @State private var containerSel = Set<String>()
    @State private var volumeSel = Set<String>()
    @State private var unusedOnly = false
    @State private var pending: Pending?
    @State private var busy = false
    @State private var starting = false

    enum Tab: String, CaseIterable, Identifiable {
        case summary, images, containers, volumes, cache
        var id: String { rawValue }
        var title: String {
            switch self {
            case .summary: L("Summary")
            case .images: L("Images")
            case .containers: L("Containers")
            case .volumes: L("Volumes")
            case .cache: L("Build Cache")
            }
        }
    }

    struct Pending: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let action: () -> DockerService.Outcome
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Docker", subtitle: subtitle) {
                Button { Task { await state.loadDocker() } } label: { Label(L("Refresh"), systemImage: "arrow.clockwise") }
                    .disabled(state.isLoadingDocker || busy)
            }
            if state.dockerSnapshot != nil {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            }
            Divider()
            if state.isLoadingDocker && state.dockerSnapshot == nil {
                ProgressView(L("Reading Docker…")).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let snap = state.dockerSnapshot {
                let f = DockerService.analyze(snap)
                switch tab {
                case .summary: summary(snap, f)
                case .images: imagesTab(snap, f)
                case .containers: containersTab(snap)
                case .volumes: volumesTab(snap)
                case .cache: cacheTab(snap)
                }
            } else {
                notRunning
            }
        }
        .task { if state.dockerSnapshot == nil { await state.loadDocker() } }
        .overlay { if busy { ProgressView().controlSize(.large).padding(30).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .confirmationDialog(pending?.title ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            presenting: pending) { p in
            Button(L("Delete"), role: .destructive) { execute(p) }
        } message: { p in Text(p.message) }
    }

    private var subtitle: String {
        guard let s = state.dockerSnapshot else { return L("Docker Desktop isn’t running") }
        return L("Running · \(Set(s.images.map(\.imageID)).count) images · \(s.containers.count) containers · \(s.volumes.count) volumes")
    }

    private func execute(_ p: Pending) {
        pending = nil
        busy = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { p.action() }.value
            busy = false
            imageSel = []; containerSel = []; volumeSel = []
            if outcome.errors.isEmpty {
                state.showToast(L("\(outcome.removed) items deleted."))
            } else {
                state.showToast(L("\(outcome.removed) deleted, \(outcome.errors.count) errors: \(outcome.errors[0])"), isError: true)
            }
            await state.loadDocker()
            state.refreshDisk()
        }
    }

    // MARK: Docker stopped

    private var notRunning: some View {
        VStack(spacing: 14) {
            Image(systemName: "cube.box").font(.system(size: 46, weight: .light)).foregroundStyle(.secondary)
            Text(L("Docker Desktop isn’t running")).font(.title2.bold())
            Text(L("Docker needs to be running to show images, containers and volumes. Its virtual disk currently takes up \(DiskScanner.allocatedSize(of: DockerService.diskImageURL).formattedBytes)."))
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 440)
            Button {
                starting = true
                Task {
                    await state.startDocker()
                    starting = false
                }
            } label: {
                if starting { ProgressView().controlSize(.small) } else { Text(L("Start Docker")) }
            }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(starting)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Summary

    private func summary(_ s: DockerService.Snapshot, _ f: DockerService.Findings) -> some View {
        let unusedImageBytes = Dictionary(grouping: f.dangling + f.unusedImages, by: \.imageID).values.reduce(Int64(0)) { $0 + ($1.first?.size ?? 0) }
        let reclaim = unusedImageBytes + f.stoppedContainers.reduce(0) { $0 + $1.size }
            + f.orphanVolumes.reduce(0) { $0 + $1.size } + f.reclaimableCache.reduce(0) { $0 + $1.size }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    tile(L("Virtual disk (on macOS)"), s.diskImageSize.formattedBytes, .blue)
                    tile(L("Contents"), s.usedTotal.formattedBytes, .purple)
                    tile(L("Reclaimable"), reclaim.formattedBytes, .orange)
                }
                finding(icon: "questionmark.square.dashed", title: L("Dangling (untagged) images"), items: f.dangling.map(\.displayName),
                        size: Dictionary(grouping: f.dangling, by: \.imageID).values.reduce(0) { $0 + ($1.first?.size ?? 0) },
                        explanation: L("Old layers left behind when a new build takes the same name. Safe to delete.")) {
                    Pending(title: L("Delete \(f.dangling.count) untagged images?"), message: L("Not used by any container."),
                            action: { DockerService.removeImages(f.dangling) })
                }
                finding(icon: "clock.arrow.circlepath", title: L("Old versions"), items: f.oldVersions.map(\.displayName),
                        size: f.oldVersions.reduce(0) { $0 + $1.size },
                        explanation: L("Old images that aren’t used while a newer version of the same repository exists.")) {
                    Pending(title: L("Delete \(f.oldVersions.count) old versions?"), message: f.oldVersions.map(\.displayName).joined(separator: "\n"),
                            action: { DockerService.removeImages(f.oldVersions) })
                }
                finding(icon: "doc.on.doc", title: L("Multiple tags for the same image"), items: f.duplicateTags.map { $0.map(\.displayName).joined(separator: " = ") },
                        size: nil,
                        explanation: L("Tags that point to the same content; they take no extra space. You can remove extra tags from the Images tab."), action: nil)
                finding(icon: "square.stack.3d.down.right", title: L("Unused images"), items: f.unusedImages.map(\.displayName),
                        size: Dictionary(grouping: f.unusedImages, by: \.imageID).values.reduce(0) { $0 + ($1.first?.size ?? 0) },
                        explanation: L("Images not used by any container (running or stopped). They can be pulled again if needed.")) {
                    Pending(title: L("Delete \(f.unusedImages.count) unused images?"), message: L("They can be pulled again with docker pull when needed."),
                            action: { DockerService.removeImages(f.unusedImages) })
                }
                finding(icon: "stop.circle", title: L("Stopped containers"), items: f.stoppedContainers.map { "\($0.name) (\($0.image))" },
                        size: f.stoppedContainers.reduce(0) { $0 + $1.size },
                        explanation: L("Containers that aren’t running. Data written inside them but not saved to a volume is deleted.")) {
                    Pending(title: L("Delete \(f.stoppedContainers.count) stopped containers?"),
                            message: L("Changes inside the containers (outside volumes) will be lost."),
                            action: { DockerService.removeContainers(f.stoppedContainers) })
                }
                finding(icon: "externaldrive.badge.xmark", title: L("Volumes not attached to any container"),
                        items: f.orphanVolumes.map { "\($0.displayName) · \($0.size.formattedBytes)" },
                        size: f.orphanVolumes.reduce(0) { $0 + $1.size },
                        explanation: L("Anonymous volumes are usually left over from deleted containers. Named volumes may hold persistent data like databases; I recommend selecting them one by one in the Volumes tab.")) {
                    let anon = f.orphanVolumes.filter(\.isAnonymous)
                    return anon.isEmpty ? nil : Pending(title: L("Delete \(anon.count) anonymous volumes?"),
                                                        message: L("Only anonymous volumes are deleted; named volumes aren’t touched. This can’t be undone."),
                                                        action: { DockerService.removeVolumes(anon) })
                }
                finding(icon: "hammer", title: L("Build cache"), items: f.reclaimableCache.prefix(5).map { "\($0.description.isEmpty ? $0.id : $0.description)" },
                        size: f.reclaimableCache.reduce(0) { $0 + $1.size },
                        explanation: L("Intermediate docker build layers. If deleted, the next build takes a little longer.")) {
                    Pending(title: L("Clean up the unused build cache?"), message: L("Runs `docker builder prune`."),
                            action: { DockerService.pruneBuildCache() })
                }
                slackCard(s, f)
            }
            .padding(24)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
    }

    private func tile(_ title: String, _ value: String, _ color: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(color)
            }
        }
    }

    private func finding(icon: String, title: String, items: [String], size: Int64?, explanation: String,
                         action: (() -> Pending?)?) -> some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(items.isEmpty ? Color.green : Color.orange).frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title).font(.headline)
                        if items.isEmpty { Image(systemName: "checkmark").foregroundStyle(.green) } else { Text("\(items.count)").foregroundStyle(.secondary) }
                    }
                    Text(explanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !items.isEmpty {
                        Text(items.prefix(4).joined(separator: ", ") + (items.count > 4 ? " …" : ""))
                            .font(.caption.monospaced()).lineLimit(2).truncationMode(.tail)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    if let size, !items.isEmpty { Text(size.formattedBytes).font(.headline).monospacedDigit() }
                    if let action, !items.isEmpty {
                        Button(L("Clean")) { pending = action() }.disabled(busy)
                    }
                }
            }
        }
    }

    @ViewBuilder private func slackCard(_ s: DockerService.Snapshot, _ f: DockerService.Findings) -> some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.down.right.and.arrow.up.left").font(.title3)
                    .foregroundStyle(f.diskImageSlack > 2_000_000_000 ? Color.orange : Color.green).frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Virtual disk space")).font(.headline)
                    Text(L("Docker’s virtual disk takes up \(s.diskImageSize.formattedBytes) on macOS, with \(s.usedTotal.formattedBytes) of content. Space from deleted data isn’t always returned right away; “Shrink” gives free blocks in the virtual machine back to macOS (it doesn’t delete data and uses a small alpine image)."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(L("Shrink")) {
                    busy = true
                    Task {
                        let before = s.diskImageSize
                        let r = await Task.detached { DockerService.trimDiskImage() }.value
                        busy = false
                        await state.loadDocker()
                        let after = state.dockerSnapshot?.diskImageSize ?? before
                        if let e = r.errors.first { state.showToast(L("Couldn’t shrink: \(e)"), isError: true) }
                        else { state.showToast(L("Virtual disk \(before.formattedBytes) → \(after.formattedBytes)")) }
                        state.refreshDisk()
                    }
                }
                .disabled(busy)
            }
        }
    }

    // MARK: Tabs

    private func imagesTab(_ s: DockerService.Snapshot, _ f: DockerService.Findings) -> some View {
        let old = Set(f.oldVersions.map(\.id))
        let dupIDs = Set(f.duplicateTags.flatMap { $0.map(\.imageID) })
        let rows = s.images.filter { !unusedOnly || $0.containers == 0 }
        let selected = rows.filter { imageSel.contains($0.id) }
        return VStack(spacing: 0) {
            Table(rows, selection: $imageSel) {
                TableColumn(L("Docker Image")) { i in
                    HStack(spacing: 6) {
                        Text(i.displayName).lineLimit(1).truncationMode(.middle)
                        if i.isDangling { badge(L("untagged"), .orange) }
                        if old.contains(i.id) { badge(L("old version"), .orange) }
                        if dupIDs.contains(i.imageID) { badge(L("same image"), .purple) }
                        if i.containers == 0 && !i.isDangling { badge(L("unused"), .secondary) }
                    }
                }
                TableColumn(L("ID")) { i in Text(i.shortID).font(.caption.monospaced()).foregroundStyle(.secondary) }.width(110)
                TableColumn(L("Size")) { i in Text(i.size.formattedBytes).monospacedDigit() }.width(90)
                TableColumn(L("Container")) { i in Text("\(i.containers)") }.width(80)
                TableColumn(L("Created")) { i in Text(i.createdSince).foregroundStyle(.secondary) }.width(120)
            }
            bottomBar(toggle: true, count: selected.count, size: selected.reduce(0) { $0 + $1.size }) {
                pending = Pending(title: L("Delete \(selected.count) images?"),
                                  message: L("For tagged images only the selected tag is removed; the layers of an image with no other tags are deleted. Images used by a container can’t be deleted.\n\n") + selected.map(\.displayName).joined(separator: "\n"),
                                  action: { DockerService.removeImages(selected) })
            }
        }
    }

    private func containersTab(_ s: DockerService.Snapshot) -> some View {
        let rows = s.containers.filter { !unusedOnly || !$0.isRunning }
        let selected = rows.filter { containerSel.contains($0.id) && !$0.isRunning }
        return VStack(spacing: 0) {
            Table(rows, selection: $containerSel) {
                TableColumn(L("Name")) { c in
                    HStack(spacing: 6) {
                        Circle().fill(c.isRunning ? Color.green : Color.secondary).frame(width: 8, height: 8)
                        Text(c.name)
                    }
                }
                TableColumn(L("Docker Image")) { c in Text(c.image).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                TableColumn(L("Status")) { c in Text(c.status).foregroundStyle(.secondary) }.width(170)
                TableColumn(L("Size")) { c in Text(c.size.formattedBytes).monospacedDigit() }.width(90)
            }
            bottomBar(toggle: true, count: selected.count, size: selected.reduce(0) { $0 + $1.size },
                      note: L("Running containers can’t be deleted; stop them in Docker first.")) {
                pending = Pending(title: L("Delete \(selected.count) containers?"),
                                  message: L("Changes inside the containers (outside volumes) will be lost.\n\n") + selected.map(\.name).joined(separator: "\n"),
                                  action: { DockerService.removeContainers(selected) })
            }
        }
    }

    private func volumesTab(_ s: DockerService.Snapshot) -> some View {
        let rows = s.volumes.filter { !unusedOnly || $0.links == 0 }
        let selected = rows.filter { volumeSel.contains($0.id) }
        let named = selected.filter { !$0.isAnonymous }
        return VStack(spacing: 0) {
            Table(rows, selection: $volumeSel) {
                TableColumn(L("Volume")) { v in
                    HStack(spacing: 6) {
                        Text(v.displayName).lineLimit(1).truncationMode(.middle)
                        if v.links == 0 { badge(L("unattached"), .orange) }
                        if !v.isAnonymous { badge(L("named"), .blue) }
                    }
                }
                TableColumn(L("Size")) { v in Text(v.size.formattedBytes).monospacedDigit() }.width(90)
                TableColumn(L("Attached containers")) { v in Text("\(v.links)") }.width(120)
            }
            bottomBar(toggle: true, count: selected.count, size: selected.reduce(0) { $0 + $1.size },
                      note: L("Volumes hold persistent data (e.g. databases). Deleting them can’t be undone.")) {
                pending = Pending(title: L("Permanently delete \(selected.count) volumes?"),
                                  message: (named.isEmpty ? "" : L("⚠️ \(named.count) NAMED volumes selected; they may contain important data like databases.\n\n"))
                                    + L("This can’t be undone. Volumes used by a container can’t be deleted.\n\n") + selected.map(\.displayName).joined(separator: "\n"),
                                  action: { DockerService.removeVolumes(selected) })
            }
        }
    }

    private func cacheTab(_ s: DockerService.Snapshot) -> some View {
        VStack(spacing: 0) {
            if s.buildCache.isEmpty {
                EmptyStateView(icon: "checkmark.circle", title: L("Build cache is empty"), message: L("No intermediate docker build layers."))
            } else {
                Table(s.buildCache) {
                    TableColumn(L("Description")) { c in Text(c.description.isEmpty ? c.id : c.description).lineLimit(1).truncationMode(.middle) }
                    TableColumn(L("Size")) { c in Text(c.size.formattedBytes).monospacedDigit() }.width(90)
                    TableColumn(L("In Use")) { c in Text(c.inUse ? L("Yes") : L("No")).foregroundStyle(c.inUse ? .primary : .secondary) }.width(90)
                    TableColumn(L("Last Used")) { c in Text(c.lastUsed).foregroundStyle(.secondary) }.width(130)
                }
                HStack {
                    Spacer()
                    Button(L("Clean Up Unused"), role: .destructive) {
                        pending = Pending(title: L("Clean up the unused build cache?"), message: L("Runs `docker builder prune`."),
                                          action: { DockerService.pruneBuildCache() })
                    }
                    .disabled(busy)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
    }

    private func bottomBar(toggle: Bool, count: Int, size: Int64, note: String? = nil, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            if toggle { Toggle(L("Unused only"), isOn: $unusedOnly).toggleStyle(.checkbox).fixedSize() }
            if let note { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            Spacer()
            if count > 0 { Text(L("Selected: \(count) · \(size.formattedBytes)")).bold() }
            Button(L("Delete"), role: .destructive, action: onDelete)
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(count == 0 || busy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2.bold()).foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
    }
}
