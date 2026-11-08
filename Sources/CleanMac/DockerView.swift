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
        case summary = "Özet", images = "İmajlar", containers = "Konteynerler", volumes = "Birimler", cache = "Derleme Önbelleği"
        var id: String { rawValue }
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
                Button { Task { await state.loadDocker() } } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                    .disabled(state.isLoadingDocker || busy)
            }
            if state.dockerSnapshot != nil {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            }
            Divider()
            if state.isLoadingDocker && state.dockerSnapshot == nil {
                ProgressView("Docker okunuyor…").frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Button("Sil", role: .destructive) { execute(p) }
        } message: { p in Text(p.message) }
    }

    private var subtitle: String {
        guard let s = state.dockerSnapshot else { return "Docker Desktop çalışmıyor" }
        return "Çalışıyor · \(Set(s.images.map(\.imageID)).count) imaj · \(s.containers.count) konteyner · \(s.volumes.count) birim"
    }

    private func execute(_ p: Pending) {
        pending = nil
        busy = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { p.action() }.value
            busy = false
            imageSel = []; containerSel = []; volumeSel = []
            if outcome.errors.isEmpty {
                state.showToast("\(outcome.removed) öğe silindi.")
            } else {
                state.showToast("\(outcome.removed) silindi, \(outcome.errors.count) hata: \(outcome.errors[0])", isError: true)
            }
            await state.loadDocker()
            state.refreshDisk()
        }
    }

    // MARK: Docker kapalı

    private var notRunning: some View {
        VStack(spacing: 14) {
            Image(systemName: "cube.box").font(.system(size: 46, weight: .light)).foregroundStyle(.secondary)
            Text("Docker Desktop çalışmıyor").font(.title2.bold())
            Text("İmajları, konteynerleri ve birimleri görmek için Docker'ın açık olması gerekir. Sanal disk şu an \(DiskScanner.allocatedSize(of: DockerService.diskImageURL).formattedBytes) yer kaplıyor.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 440)
            Button {
                starting = true
                Task {
                    await state.startDocker()
                    starting = false
                }
            } label: {
                if starting { ProgressView().controlSize(.small) } else { Text("Docker'ı Başlat") }
            }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(starting)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Özet

    private func summary(_ s: DockerService.Snapshot, _ f: DockerService.Findings) -> some View {
        let unusedImageBytes = Dictionary(grouping: f.dangling + f.unusedImages, by: \.imageID).values.reduce(Int64(0)) { $0 + ($1.first?.size ?? 0) }
        let reclaim = unusedImageBytes + f.stoppedContainers.reduce(0) { $0 + $1.size }
            + f.orphanVolumes.reduce(0) { $0 + $1.size } + f.reclaimableCache.reduce(0) { $0 + $1.size }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    tile("Sanal disk (macOS'ta)", s.diskImageSize.formattedBytes, .blue)
                    tile("İçerik", s.usedTotal.formattedBytes, .purple)
                    tile("Temizlenebilir", reclaim.formattedBytes, .orange)
                }
                finding(icon: "questionmark.square.dashed", title: "Etiketsiz (sarkan) imajlar", items: f.dangling.map(\.displayName),
                        size: Dictionary(grouping: f.dangling, by: \.imageID).values.reduce(0) { $0 + ($1.first?.size ?? 0) },
                        explanation: "Yeni bir derleme aynı adı aldığında geride kalan eski katmanlar. Güvenle silinebilir.") {
                    Pending(title: "\(f.dangling.count) etiketsiz imaj silinsin mi?", message: "Hiçbir konteyner kullanmıyor.",
                            action: { DockerService.removeImages(f.dangling) })
                }
                finding(icon: "clock.arrow.circlepath", title: "Eski sürümler", items: f.oldVersions.map(\.displayName),
                        size: f.oldVersions.reduce(0) { $0 + $1.size },
                        explanation: "Aynı deponun daha yeni bir sürümü varken kullanılmayan eski imajlar.") {
                    Pending(title: "\(f.oldVersions.count) eski sürüm silinsin mi?", message: f.oldVersions.map(\.displayName).joined(separator: "\n"),
                            action: { DockerService.removeImages(f.oldVersions) })
                }
                finding(icon: "doc.on.doc", title: "Aynı imajın birden fazla etiketi", items: f.duplicateTags.map { $0.map(\.displayName).joined(separator: " = ") },
                        size: nil,
                        explanation: "Aynı içeriğe işaret eden etiketler; ek yer kaplamazlar. Fazladan etiketleri İmajlar sekmesinden kaldırabilirsin.", action: nil)
                finding(icon: "square.stack.3d.down.right", title: "Kullanılmayan imajlar", items: f.unusedImages.map(\.displayName),
                        size: Dictionary(grouping: f.unusedImages, by: \.imageID).values.reduce(0) { $0 + ($1.first?.size ?? 0) },
                        explanation: "Hiçbir konteynerin (çalışan ya da durmuş) kullanmadığı imajlar. Gerekirse yeniden indirilebilir.") {
                    Pending(title: "\(f.unusedImages.count) kullanılmayan imaj silinsin mi?", message: "Gerektiğinde docker pull ile yeniden indirilebilir.",
                            action: { DockerService.removeImages(f.unusedImages) })
                }
                finding(icon: "stop.circle", title: "Durmuş konteynerler", items: f.stoppedContainers.map { "\($0.name) (\($0.image))" },
                        size: f.stoppedContainers.reduce(0) { $0 + $1.size },
                        explanation: "Çalışmayan konteynerler. İçlerine yazılmış ama birime kaydedilmemiş veriler silinir.") {
                    Pending(title: "\(f.stoppedContainers.count) durmuş konteyner silinsin mi?",
                            message: "Konteyner içindeki (birim dışı) değişiklikler kaybolur.",
                            action: { DockerService.removeContainers(f.stoppedContainers) })
                }
                finding(icon: "externaldrive.badge.xmark", title: "Hiçbir konteynere bağlı olmayan birimler",
                        items: f.orphanVolumes.map { "\($0.displayName) · \($0.size.formattedBytes)" },
                        size: f.orphanVolumes.reduce(0) { $0 + $1.size },
                        explanation: "Anonim birimler genellikle silinmiş konteynerlerden kalır. Adlı birimler veritabanı gibi kalıcı veriler içerebilir; Birimler sekmesinden tek tek seçmeni öneririm.") {
                    let anon = f.orphanVolumes.filter(\.isAnonymous)
                    return anon.isEmpty ? nil : Pending(title: "\(anon.count) anonim birim silinsin mi?",
                                                        message: "Yalnızca anonim birimler silinir; adlı birimlere dokunulmaz. Bu işlem geri alınamaz.",
                                                        action: { DockerService.removeVolumes(anon) })
                }
                finding(icon: "hammer", title: "Derleme önbelleği", items: f.reclaimableCache.prefix(5).map { "\($0.description.isEmpty ? $0.id : $0.description)" },
                        size: f.reclaimableCache.reduce(0) { $0 + $1.size },
                        explanation: "docker build ara katmanları. Silinirse sonraki derleme biraz uzun sürer.") {
                    Pending(title: "Kullanılmayan derleme önbelleği temizlensin mi?", message: "`docker builder prune` çalışacak.",
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
                        Button("Temizle") { pending = action() }.disabled(busy)
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
                    Text("Sanal disk alanı").font(.headline)
                    Text("Docker'ın sanal diski macOS'ta \(s.diskImageSize.formattedBytes) kaplıyor, içeriği \(s.usedTotal.formattedBytes). Silinen verinin yeri her zaman hemen geri verilmez; \"Küçült\" sanal makinedeki boş blokları macOS'a iade eder (veri silmez, küçük bir alpine imajı kullanır).")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Küçült") {
                    busy = true
                    Task {
                        let before = s.diskImageSize
                        let r = await Task.detached { DockerService.trimDiskImage() }.value
                        busy = false
                        await state.loadDocker()
                        let after = state.dockerSnapshot?.diskImageSize ?? before
                        if let e = r.errors.first { state.showToast("Küçültülemedi: \(e)", isError: true) }
                        else { state.showToast("Sanal disk \(before.formattedBytes) → \(after.formattedBytes)") }
                        state.refreshDisk()
                    }
                }
                .disabled(busy)
            }
        }
    }

    // MARK: Sekmeler

    private func imagesTab(_ s: DockerService.Snapshot, _ f: DockerService.Findings) -> some View {
        let old = Set(f.oldVersions.map(\.id))
        let dupIDs = Set(f.duplicateTags.flatMap { $0.map(\.imageID) })
        let rows = s.images.filter { !unusedOnly || $0.containers == 0 }
        let selected = rows.filter { imageSel.contains($0.id) }
        return VStack(spacing: 0) {
            Table(rows, selection: $imageSel) {
                TableColumn("İmaj") { i in
                    HStack(spacing: 6) {
                        Text(i.displayName).lineLimit(1).truncationMode(.middle)
                        if i.isDangling { badge("etiketsiz", .orange) }
                        if old.contains(i.id) { badge("eski sürüm", .orange) }
                        if dupIDs.contains(i.imageID) { badge("aynı imaj", .purple) }
                        if i.containers == 0 && !i.isDangling { badge("kullanılmıyor", .secondary) }
                    }
                }
                TableColumn("Kimlik") { i in Text(i.shortID).font(.caption.monospaced()).foregroundStyle(.secondary) }.width(110)
                TableColumn("Boyut") { i in Text(i.size.formattedBytes).monospacedDigit() }.width(90)
                TableColumn("Konteyner") { i in Text("\(i.containers)") }.width(80)
                TableColumn("Oluşturma") { i in Text(i.createdSince).foregroundStyle(.secondary) }.width(120)
            }
            bottomBar(toggle: true, count: selected.count, size: selected.reduce(0) { $0 + $1.size }) {
                pending = Pending(title: "\(selected.count) imaj silinsin mi?",
                                  message: "Etiketli imajlarda yalnızca seçilen etiket kaldırılır; başka etiketi olmayan imajın katmanları silinir. Konteynerin kullandığı imajlar silinemez.\n\n" + selected.map(\.displayName).joined(separator: "\n"),
                                  action: { DockerService.removeImages(selected) })
            }
        }
    }

    private func containersTab(_ s: DockerService.Snapshot) -> some View {
        let rows = s.containers.filter { !unusedOnly || !$0.isRunning }
        let selected = rows.filter { containerSel.contains($0.id) && !$0.isRunning }
        return VStack(spacing: 0) {
            Table(rows, selection: $containerSel) {
                TableColumn("Ad") { c in
                    HStack(spacing: 6) {
                        Circle().fill(c.isRunning ? Color.green : Color.secondary).frame(width: 8, height: 8)
                        Text(c.name)
                    }
                }
                TableColumn("İmaj") { c in Text(c.image).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                TableColumn("Durum") { c in Text(c.status).foregroundStyle(.secondary) }.width(170)
                TableColumn("Boyut") { c in Text(c.size.formattedBytes).monospacedDigit() }.width(90)
            }
            bottomBar(toggle: true, count: selected.count, size: selected.reduce(0) { $0 + $1.size },
                      note: "Çalışan konteynerler silinemez; önce Docker'da durdur.") {
                pending = Pending(title: "\(selected.count) konteyner silinsin mi?",
                                  message: "Konteyner içindeki (birim dışı) değişiklikler kaybolur.\n\n" + selected.map(\.name).joined(separator: "\n"),
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
                TableColumn("Birim") { v in
                    HStack(spacing: 6) {
                        Text(v.displayName).lineLimit(1).truncationMode(.middle)
                        if v.links == 0 { badge("bağlantısız", .orange) }
                        if !v.isAnonymous { badge("adlı", .blue) }
                    }
                }
                TableColumn("Boyut") { v in Text(v.size.formattedBytes).monospacedDigit() }.width(90)
                TableColumn("Bağlı konteyner") { v in Text("\(v.links)") }.width(120)
            }
            bottomBar(toggle: true, count: selected.count, size: selected.reduce(0) { $0 + $1.size },
                      note: "Birimler kalıcı verilerdir (ör. veritabanı). Silmek geri alınamaz.") {
                pending = Pending(title: "\(selected.count) birim kalıcı olarak silinsin mi?",
                                  message: (named.isEmpty ? "" : "⚠️ \(named.count) ADLI birim seçili; veritabanı gibi önemli veriler içerebilir.\n\n")
                                    + "Bu işlem geri alınamaz. Bir konteynerin kullandığı birimler silinemez.\n\n" + selected.map(\.displayName).joined(separator: "\n"),
                                  action: { DockerService.removeVolumes(selected) })
            }
        }
    }

    private func cacheTab(_ s: DockerService.Snapshot) -> some View {
        VStack(spacing: 0) {
            if s.buildCache.isEmpty {
                EmptyStateView(icon: "checkmark.circle", title: "Derleme önbelleği boş", message: "docker build ara katmanı yok.")
            } else {
                Table(s.buildCache) {
                    TableColumn("Açıklama") { c in Text(c.description.isEmpty ? c.id : c.description).lineLimit(1).truncationMode(.middle) }
                    TableColumn("Boyut") { c in Text(c.size.formattedBytes).monospacedDigit() }.width(90)
                    TableColumn("Kullanımda") { c in Text(c.inUse ? "Evet" : "Hayır").foregroundStyle(c.inUse ? .primary : .secondary) }.width(90)
                    TableColumn("Son kullanım") { c in Text(c.lastUsed).foregroundStyle(.secondary) }.width(130)
                }
                HStack {
                    Spacer()
                    Button("Kullanılmayanları Temizle", role: .destructive) {
                        pending = Pending(title: "Kullanılmayan derleme önbelleği temizlensin mi?", message: "`docker builder prune` çalışacak.",
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
            if toggle { Toggle("Yalnızca kullanılmayanlar", isOn: $unusedOnly).toggleStyle(.checkbox).fixedSize() }
            if let note { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            Spacer()
            if count > 0 { Text("Seçili: \(count) · \(size.formattedBytes)").bold() }
            Button("Sil", role: .destructive, action: onDelete)
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
