import SwiftUI

struct JunkView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("permanentDelete") private var permanentDelete = false
    @State private var selected = Set<String>()
    @State private var expanded = Set<String>()
    @State private var confirm = false

    private struct Target {
        let target: RemovalTarget
        let permanentOnly: Bool
    }

    private var targets: [Target] {
        var out: [Target] = []
        for c in state.junkCategories {
            for i in c.items where selected.contains(i.id) {
                out.append(Target(target: RemovalTarget(url: i.url, size: i.size), permanentOnly: c.permanentOnly))
            }
        }
        for n in state.visibleDevArtifacts where selected.contains(n.url.path) {
            out.append(Target(target: RemovalTarget(url: n.url, size: n.size), permanentOnly: false))
        }
        return out
    }

    var body: some View {
        let targets = targets
        let total = targets.reduce(Int64(0)) { $0 + $1.target.size }

        VStack(spacing: 0) {
            PageHeader(title: "Gereksiz Dosyalar", subtitle: "Önbellekler, günlükler, geliştirici artıkları ve unutulmuş indirmeler") {
                Button {
                    selected = []
                    Task { await state.scanJunk() }
                } label: { Label("Yeniden Tara", systemImage: "arrow.clockwise") }
                    .disabled(state.isScanningJunk)
            }
            Divider()
            if state.isScanningJunk && !state.junkReady {
                ProgressView("Bilinen konumlar taranıyor…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !state.junkReady {
                EmptyStateView(icon: "trash", title: "Gereksiz dosyaları tara",
                               message: "Önbellek, günlük ve geliştirici araçlarının bıraktığı dosyaları bul.",
                               actionTitle: "Tara") { Task { await state.scanJunk() } }
            } else {
                List {
                    ForEach(state.junkCategories) { category in
                        categoryRow(category)
                    }
                    devArtifactsSection
                }
                Divider()
                HStack(spacing: 12) {
                    Toggle("Kalıcı olarak sil (Çöp Kutusu'nu atla)", isOn: $permanentDelete)
                        .toggleStyle(.checkbox)
                        .fixedSize()
                        .help("Kapalıyken öğeler Çöp Kutusu'na taşınır ve geri alınabilir.")
                    Spacer()
                    Button("Güvenli olanların hepsini seç") {
                        for c in state.junkCategories where c.safety == .safe && !c.permanentOnly {
                            c.items.forEach { selected.insert($0.id) }
                        }
                    }
                    if !selected.isEmpty { Button("Seçimi Temizle") { selected = [] } }
                    Button(total > 0 ? "Temizle (\(total.formattedBytes))" : "Temizle", role: .destructive) { confirm = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(targets.isEmpty || state.isRemoving)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .task {
            if !state.junkReady && !state.isScanningJunk { await state.scanJunk() }
        }
        .confirmationDialog("\(targets.count) öğe temizlensin mi?", isPresented: $confirm) {
            Button("Temizle (\(total.formattedBytes))", role: .destructive) { clean(targets) }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            let permanentCount = targets.filter { $0.permanentOnly || permanentDelete }.count
            if permanentCount == targets.count {
                Text("Öğeler kalıcı olarak silinecek. Bu işlem geri alınamaz.")
            } else if permanentCount > 0 {
                Text("\(targets.count - permanentCount) öğe Çöp Kutusu'na taşınacak, Çöp Kutusu'ndaki \(permanentCount) öğe kalıcı olarak silinecek.")
            } else {
                Text("Öğeler Çöp Kutusu'na taşınacak ve oradan geri alınabilir. Alan, çöp boşaltıldığında açılır.")
            }
        }
    }

    private func clean(_ targets: [Target]) {
        let permanent = targets.filter { $0.permanentOnly || permanentDelete }.map(\.target)
        let toTrash = targets.filter { !($0.permanentOnly || permanentDelete) }.map(\.target)
        selected = []
        Task {
            if !toTrash.isEmpty { await state.remove(toTrash, permanently: false) }
            if !permanent.isEmpty { await state.remove(permanent, permanently: true) }
        }
    }

    private func checkState(_ c: JunkCategory) -> Checkbox.CheckState {
        let n = c.items.filter { selected.contains($0.id) }.count
        return n == 0 ? .off : n == c.items.count ? .on : .mixed
    }

    private func toggle(_ c: JunkCategory) {
        if checkState(c) == .on {
            c.items.forEach { selected.remove($0.id) }
        } else {
            c.items.forEach { selected.insert($0.id) }
        }
    }

    private func toggleItem(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func categoryRow(_ c: JunkCategory) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expanded.contains(c.id) },
            set: { if $0 { expanded.insert(c.id) } else { expanded.remove(c.id) } }
        )) {
            ForEach(c.items.prefix(300)) { item in
                HStack(spacing: 10) {
                    Checkbox(state: selected.contains(item.id) ? .on : .off) { toggleItem(item.id) }
                    FileIconView(url: item.url, size: 18)
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if let d = item.date {
                        Text(d.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(item.size.formattedBytes).monospacedDigit().frame(width: 80, alignment: .trailing)
                    Button { Finder.reveal([item.url]) } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.borderless)
                }
                .padding(.leading, 8)
                .contextMenu {
                    Button("Finder'da Göster") { Finder.reveal([item.url]) }
                    Button("Hariç Tut (önerme, silme)") {
                        selected.remove(item.id)
                        state.addExclusion(item.url)
                    }
                }
            }
            if c.items.count > 300 {
                Text("… ve \(c.items.count - 300) öğe daha (kategori seçildiğinde hepsi dahil edilir)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } label: {
            HStack(spacing: 12) {
                Checkbox(state: checkState(c)) { toggle(c) }
                    .disabled(c.items.isEmpty)
                Image(systemName: c.icon)
                    .font(.title3)
                    .foregroundStyle(c.safety == .safe ? Color.green : Color.orange)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(c.title).font(.headline)
                        SafetyBadge(safety: c.safety)
                    }
                    Text(c.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if c.items.isEmpty && !c.deniedPaths.isEmpty {
                    Button {
                        Finder.openFullDiskAccessSettings()
                    } label: {
                        Label("İzin yok", systemImage: "lock.fill").font(.callout).foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Bu konum okunamadı. Görmek için CleanMac'e Tam Disk Erişimi ver. (Tıkla: ayarları aç)")
                } else if c.items.isEmpty {
                    Label("Temiz", systemImage: "checkmark").font(.callout).foregroundStyle(.green)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(c.size.formattedBytes).font(.headline).monospacedDigit()
                        Text("\(c.items.count) öğe").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder private var devArtifactsSection: some View {
        if state.rootNode == nil {
            Section("Proje Bağımlılıkları") {
                Text("node_modules, .venv, Pods gibi klasörleri bulmak için önce Klasör Gezgini'nden bir tarama yap.")
                    .foregroundStyle(.secondary)
            }
        } else if !state.visibleDevArtifacts.isEmpty {
            Section {
                ForEach(state.visibleDevArtifacts) { node in
                    HStack(spacing: 10) {
                        Checkbox(state: selected.contains(node.url.path) ? .on : .off) { toggleItem(node.url.path) }
                        Image(systemName: "shippingbox").foregroundStyle(.teal).frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.name)
                            Text(node.url.deletingLastPathComponent().abbreviatedPath)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(node.size.formattedBytes).monospacedDigit().frame(width: 80, alignment: .trailing)
                        Button { Finder.reveal([node.url]) } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.borderless)
                    }
                    .contextMenu {
                        Button("Finder'da Göster") { Finder.reveal([node.url]) }
                        Button("Projeyi Hariç Tut (aktif proje)") {
                            selected.remove(node.url.path)
                            state.addExclusion(node.url.deletingLastPathComponent())
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Proje Bağımlılıkları (\(state.scanRoot.abbreviatedPath) içinde)")
                    SafetyBadge(safety: .review)
                    Spacer()
                    Text(state.devArtifactTotal.formattedBytes)
                }
            }
        }
    }
}
