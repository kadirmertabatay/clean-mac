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
                        Text("Geliştirici Temizliği").font(.title.bold())
                        Text("Araçların kendi temizlik komutlarını kullanır; önce ne silineceğini gösterir.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await load() } } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                        .disabled(loading || busy != nil)
                }
                if loading && brew == nil && docker == nil {
                    ProgressView("Araçlar kontrol ediliyor…").frame(maxWidth: .infinity).padding(30)
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
            Button("Devam Et", role: .destructive) { run(action) }
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
                report(await Task.detached { DevTools.brewCleanup() }.value, success: "Homebrew temizlendi.")
            case .simulators:
                busy = "sim"
                report(await Task.detached { DevTools.deleteUnavailableSimulators() }.value, success: "Kullanılmayan simülatörler silindi.")
            case .docker(let all):
                busy = "docker"
                report(await Task.detached { DevTools.dockerPrune(allImages: all) }.value,
                       success: "Docker temizlendi. Sanal disk dosyası Docker ayarlarından küçültülebilir.")
            }
            busy = nil
            state.refreshDisk()
            await load()
        }
    }

    private func report(_ error: String?, success: String) {
        if let error { state.showToast("Hata: \(error)", isError: true) } else { state.showToast(success) }
    }

    private var dialogTitle: String {
        switch pending {
        case .brew: "Homebrew temizlensin mi?"
        case .simulators: "Kullanılmayan simülatörler silinsin mi?"
        case .docker(let all): all ? "Kullanılmayan tüm Docker imajları silinsin mi?" : "Docker temizlensin mi?"
        case .projects(let n): "\(n.count) bağımlılık klasörü Çöp Kutusu'na taşınsın mı?"
        case nil: ""
        }
    }

    private func dialogMessage(_ action: PendingAction) -> String {
        switch action {
        case .brew: "`brew cleanup -s` çalışacak: eski paket sürümleri ve indirme önbelleği silinir. Yüklü paketlerin çalışmaya devam eder."
        case .simulators: "`xcrun simctl delete unavailable` çalışacak: artık yüklü olmayan iOS sürümlerine ait simülatörler kalıcı olarak silinir."
        case .docker(let all): all
            ? "`docker system prune -a` çalışacak: durmuş konteynerler, kullanılmayan ağlar, HİÇBİR konteynerin kullanmadığı tüm imajlar ve derleme önbelleği kalıcı olarak silinir. Birimler (volume) korunur."
            : "`docker system prune` çalışacak: durmuş konteynerler, kullanılmayan ağlar, etiketsiz imajlar ve derleme önbelleği kalıcı olarak silinir. Birimler (volume) korunur."
        case .projects: "Klasörler Çöp Kutusu'na taşınır; projede tekrar çalışırken npm install / pip install ile geri gelir."
        }
    }

    // MARK: Kartlar

    private var projectsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Dokunulmamış projelerin bağımlılıkları", systemImage: "shippingbox").font(.headline)
                    Spacer()
                    Picker("", selection: $staleDays) {
                        Text("30+ gün").tag(30); Text("90+ gün").tag(90); Text("180+ gün").tag(180)
                    }
                    .frame(width: 110)
                }
                if state.rootNode == nil {
                    Text("node_modules, .venv, Pods gibi klasörleri bulmak için önce bir tarama yap.").foregroundStyle(.secondary)
                    Button("Taramayı Başlat") { state.startScan() }
                } else if staleArtifacts.isEmpty {
                    Label("Bu süreden eski proje bağımlılığı yok.", systemImage: "checkmark.circle").foregroundStyle(.green)
                } else {
                    let total = staleArtifacts.reduce(Int64(0)) { $0 + $1.size }
                    ForEach(staleArtifacts.prefix(8)) { n in
                        HStack {
                            Text(n.url.deletingLastPathComponent().lastPathComponent).bold()
                            Text(n.name).foregroundStyle(.secondary)
                            Spacer()
                            if let d = projectActivity[n.url.path] {
                                Text("son değişiklik \(d.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(n.size.formattedBytes).monospacedDigit().frame(width: 80, alignment: .trailing)
                        }
                        .contextMenu {
                            Button("Finder'da Göster") { Finder.reveal([n.url]) }
                            Button("Projeyi Hariç Tut") { state.addExclusion(n.url.deletingLastPathComponent()) }
                        }
                    }
                    if staleArtifacts.count > 8 {
                        Text("… ve \(staleArtifacts.count - 8) klasör daha").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Aktif bir projeyi korumak için satıra sağ tıkla › Hariç Tut.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("\(staleArtifacts.count) klasörü Çöpe Taşı (\(total.formattedBytes))", role: .destructive) {
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
                        Text("Sanal disk: \(d.diskImageSize.formattedBytes)").foregroundStyle(.secondary)
                    }
                    if d.running {
                        ForEach(d.usage) { u in
                            HStack {
                                Text(u.type)
                                Spacer()
                                Text(u.size).monospacedDigit()
                                Text("temizlenebilir: \(u.reclaimable)").font(.caption).foregroundStyle(.secondary)
                                    .frame(width: 170, alignment: .trailing)
                            }
                        }
                        HStack {
                            Text("Temizlikten sonra sanal diski küçültmek için Docker › Settings › Resources › Disk.")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Temizle") { pending = .docker(all: false) }
                            Button("Tüm Kullanılmayan İmajlar", role: .destructive) { pending = .docker(all: true) }
                        }
                        .disabled(busy != nil)
                    } else {
                        Text("Docker çalışmıyor. Sanal disk \(d.diskImageSize.formattedBytes) yer kaplıyor; ne kadarının temizlenebileceğini görmek için Docker Desktop'ı açıp Yenile'ye bas. Docker'ı hiç kullanmıyorsan Uygulamalar ekranından tamamen kaldırabilirsin.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Docker'ı Aç") { Finder.open(URL(fileURLWithPath: "/Applications/Docker.app")) }
                            Button("Uygulamalar") { state.section = .apps }
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
                        if let f = b.freeable { Text("\(f) açılabilir").foregroundStyle(.secondary) }
                    }
                    if b.items.isEmpty {
                        Label("Temizlenecek eski sürüm ya da önbellek yok.", systemImage: "checkmark.circle").foregroundStyle(.green)
                    } else {
                        ForEach(b.items.prefix(5), id: \.self) { Text($0).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle) }
                        if b.items.count > 5 { Text("… ve \(b.items.count - 5) öğe daha").font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            Spacer()
                            Button("brew cleanup çalıştır") { pending = .brew }.disabled(busy != nil)
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
                    Label("Kullanılmayan Xcode simülatörleri", systemImage: "iphone").font(.headline)
                    if sims.isEmpty {
                        Label("Yüklü olmayan iOS sürümlerine ait simülatör yok.", systemImage: "checkmark.circle").foregroundStyle(.green)
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
                            Button("\(sims.count) simülatörü sil (\(sims.reduce(Int64(0)) { $0 + $1.size }.formattedBytes))", role: .destructive) {
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
