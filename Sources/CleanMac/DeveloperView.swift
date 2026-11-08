import SwiftUI

struct DeveloperView: View {
    @EnvironmentObject var state: AppState
    @State private var brew: DevTools.BrewReport?
    @State private var simulators: [DevTools.Simulator]?
    @State private var docker: DevTools.DockerReport?
    @State private var projectActivity: [String: Date] = [:]
    @State private var loading = false
    @State private var busy: String?
    @State private var staleDays = 30
    @State private var pending: PendingAction?

    enum PendingAction: Identifiable {
        case brew, simulators, docker(all: Bool), projects([FileNode])
        var id: String {
            switch self {
            case .brew: "brew"
            case .simulators: "sim"
            case .docker(let all): "docker\(all)"
            case .projects: "projects"
            }
        }
    }

    private var staleArtifacts: [FileNode] {
        let cutoff = Date().addingTimeInterval(-Double(staleDays) * 86_400)
        return state.visibleDevArtifacts.filter { (projectActivity[$0.url.path] ?? .distantFuture) < cutoff }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Developer Cleanup")).font(.title.bold())
                        Text(L("Uses each tool’s own cleanup command and shows what will be deleted first.")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await load() } } label: { Label(L("Refresh"), systemImage: "arrow.clockwise") }
                        .disabled(loading || busy != nil)
                }
                if loading && brew == nil && docker == nil {
                    ProgressView(L("Checking tools…")).frame(maxWidth: .infinity).padding(30)
                }
                projectsCard
                dockerCard
                brewCard
                simulatorCard
            }
            .padding(24)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .task { if brew == nil && docker == nil && simulators == nil { await load() } }
        .confirmationDialog(dialogTitle, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            presenting: pending) { action in
            Button(L("Continue"), role: .destructive) { run(action) }
        } message: { action in
            Text(dialogMessage(action))
        }
    }

    private func load() async {
        loading = true
        async let b = Task.detached { DevTools.brewDryRun() }.value
        async let s = Task.detached { DevTools.unavailableSimulators() }.value
        async let d = Task.detached { DevTools.dockerReport() }.value
        let artifacts = state.visibleDevArtifacts.map(\.url)
        async let p = Task.detached {
            Dictionary(uniqueKeysWithValues: artifacts.compactMap { u in DevTools.projectLastActivity(u).map { (u.path, $0) } })
        }.value
        (brew, simulators, docker, projectActivity) = await (b, s, d, p)
        loading = false
    }

    private func run(_ action: PendingAction) {
        pending = nil
        Task {
            switch action {
            case .projects(let nodes):
                busy = "projects"
                await state.remove(nodes.map { RemovalTarget(url: $0.url, size: $0.size) }, permanently: false)
            case .brew:
                busy = "brew"
                report(await Task.detached { DevTools.brewCleanup() }.value, success: L("Homebrew cleaned up."))
            case .simulators:
                busy = "sim"
                report(await Task.detached { DevTools.deleteUnavailableSimulators() }.value, success: L("Unused simulators deleted."))
            case .docker(let all):
                busy = "docker"
                report(await Task.detached { DevTools.dockerPrune(allImages: all) }.value,
                       success: L("Docker cleaned up. The virtual disk file can be shrunk in Docker’s settings."))
            }
            busy = nil
            state.refreshDisk()
            await load()
        }
    }

    private func report(_ error: String?, success: String) {
        if let error { state.showToast(L("Error: \(error)"), isError: true) } else { state.showToast(success) }
    }

    private var dialogTitle: String {
        switch pending {
        case .brew: L("Clean up Homebrew?")
        case .simulators: L("Delete unused simulators?")
        case .docker(let all): all ? L("Delete all unused Docker images?") : L("Clean up Docker?")
        case .projects(let n): L("Move \(n.count) dependency folders to the Trash?")
        case nil: ""
        }
    }

    private func dialogMessage(_ action: PendingAction) -> String {
        switch action {
        case .brew: L("Runs `brew cleanup -s`: old package versions and the download cache are deleted. Your installed packages keep working.")
        case .simulators: L("Runs `xcrun simctl delete unavailable`: simulators for iOS versions that are no longer installed are deleted permanently.")
        case .docker(let all): all
            ? L("Runs `docker system prune -a`: stopped containers, unused networks, ALL images not used by any container, and the build cache are deleted permanently. Volumes are kept.")
            : L("Runs `docker system prune`: stopped containers, unused networks, dangling images and the build cache are deleted permanently. Volumes are kept.")
        case .projects: L("The folders are moved to the Trash; they come back with npm install / pip install when you work on the project again.")
        }
    }

    // MARK: Cards

    private var projectsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(L("Dependencies of untouched projects"), systemImage: "shippingbox").font(.headline)
                    Spacer()
                    Picker("", selection: $staleDays) {
                        Text(L("30+ days")).tag(30); Text(L("90+ days")).tag(90); Text(L("180+ days")).tag(180)
                    }
                    .frame(width: 110)
                }
                if state.rootNode == nil {
                    Text(L("Run a scan first to find folders like node_modules, .venv and Pods.")).foregroundStyle(.secondary)
                    Button(L("Start Scan")) { state.startScan() }
                } else if staleArtifacts.isEmpty {
                    Label(L("No project dependencies older than this."), systemImage: "checkmark.circle").foregroundStyle(.green)
                } else {
                    let total = staleArtifacts.reduce(Int64(0)) { $0 + $1.size }
                    ForEach(staleArtifacts.prefix(8)) { n in
                        HStack {
                            Text(n.url.deletingLastPathComponent().lastPathComponent).bold()
                            Text(n.name).foregroundStyle(.secondary)
                            Spacer()
                            if let d = projectActivity[n.url.path] {
                                Text(L("last changed \(d.formatted(.relative(presentation: .named)))")).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(n.size.formattedBytes).monospacedDigit().frame(width: 80, alignment: .trailing)
                        }
                        .contextMenu {
                            Button(L("Show in Finder")) { Finder.reveal([n.url]) }
                            Button(L("Exclude Project")) { state.addExclusion(n.url.deletingLastPathComponent()) }
                        }
                    }
                    if staleArtifacts.count > 8 {
                        Text(L("… and \(staleArtifacts.count - 8) more folders")).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(L("To protect an active project, right-click its row › Exclude.")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Move \(staleArtifacts.count) Folders to Trash (\(total.formattedBytes))"), role: .destructive) {
                            pending = .projects(staleArtifacts)
                        }
                        .disabled(busy != nil)
                    }
                }
            }
        }
    }

    @ViewBuilder private var dockerCard: some View {
        if let d = docker {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Docker", systemImage: "cube.box").font(.headline)
                        Spacer()
                        Text(L("Virtual disk: \(d.diskImageSize.formattedBytes)")).foregroundStyle(.secondary)
                    }
                    if d.running {
                        ForEach(d.usage) { u in
                            HStack {
                                Text(u.type)
                                Spacer()
                                Text(u.size).monospacedDigit()
                                Text(L("reclaimable: \(u.reclaimable)")).font(.caption).foregroundStyle(.secondary)
                                    .frame(width: 170, alignment: .trailing)
                            }
                        }
                        HStack {
                            Text(L("To shrink the virtual disk after cleaning up, use Docker › Settings › Resources › Disk."))
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(L("Docker Tab")) { state.section = .docker }
                            Button(L("Clean")) { pending = .docker(all: false) }
                            Button(L("All Unused Images"), role: .destructive) { pending = .docker(all: true) }
                        }
                        .disabled(busy != nil)
                    } else {
                        Text(L("Docker isn’t running. Its virtual disk takes up \(d.diskImageSize.formattedBytes); open Docker Desktop and press Refresh to see how much can be cleaned. If you don’t use Docker at all, you can remove it completely from the Apps screen."))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(L("Open Docker")) { Finder.open(URL(fileURLWithPath: "/Applications/Docker.app")) }
                            Button(L("Apps")) { state.section = .apps }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var brewCard: some View {
        if let b = brew {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Homebrew", systemImage: "mug").font(.headline)
                        Spacer()
                        if let f = b.freeable { Text(L("\(f) can be freed")).foregroundStyle(.secondary) }
                    }
                    if b.items.isEmpty {
                        Label(L("No old versions or caches to clean up."), systemImage: "checkmark.circle").foregroundStyle(.green)
                    } else {
                        ForEach(b.items.prefix(5), id: \.self) { Text($0).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle) }
                        if b.items.count > 5 { Text(L("… and \(b.items.count - 5) more items")).font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            Spacer()
                            Button(L("Run brew cleanup")) { pending = .brew }.disabled(busy != nil)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var simulatorCard: some View {
        if let sims = simulators, DevTools.hasSimctl {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label(L("Unused Xcode simulators"), systemImage: "iphone").font(.headline)
                    if sims.isEmpty {
                        Label(L("No simulators for uninstalled iOS versions."), systemImage: "checkmark.circle").foregroundStyle(.green)
                    } else {
                        ForEach(sims.prefix(6)) { s in
                            HStack {
                                Text(s.name)
                                Text(s.runtime).foregroundStyle(.secondary)
                                Spacer()
                                Text(s.size.formattedBytes).monospacedDigit()
                            }
                        }
                        HStack {
                            Spacer()
                            Button(L("Delete \(sims.count) Simulators (\(sims.reduce(Int64(0)) { $0 + $1.size }.formattedBytes))"), role: .destructive) {
                                pending = .simulators
                            }
                            .disabled(busy != nil)
                        }
                    }
                }
            }
        }
    }
}
