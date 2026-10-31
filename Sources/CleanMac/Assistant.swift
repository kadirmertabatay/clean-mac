import SwiftUI

struct Recommendation: Identifiable {
    enum Level: Int {
        case critical, warning, suggestion, info, good

        var color: Color {
            switch self {
            case .critical: .red
            case .warning: .orange
            case .suggestion: .accentColor
            case .info: .purple
            case .good: .green
            }
        }
    }

    enum Action {
        case open(AppSection)
        case openStaleLargeFiles
        case cleanJunk(String)
        case openFolder(FileNode)
        case fullDiskAccess
        case storageSettings
    }

    let id: String
    let level: Level
    let icon: String
    let title: String
    let detail: String
    var size: Int64?
    var action: Action?
    var actionTitle: String?
}

/// Kural tabanlı, tamamen yerel çalışan öneri motoru.
extension AppState {
    static let staleDays = 180

    var staleLargeFiles: [FileEntry] {
        let cutoff = Date().addingTimeInterval(-Double(Self.staleDays) * 86_400)
        return files.filter { !$0.isProtected && $0.size >= 100_000_000 && ($0.lastUsed ?? .distantPast) < cutoff }
    }

    var visibleDuplicateWaste: Int64 {
        duplicateGroups.reduce(0) { total, g in
            let n = g.files.filter { !$0.isProtected }.count
            return total + g.size * Int64(max(n - 1, 0))
        }
    }

    var safeJunkTotal: Int64 {
        junkCategories.filter { $0.safety == .safe }.reduce(0) { $0 + $1.size }
    }

    var reviewJunkTotal: Int64 {
        junkCategories.filter { $0.safety == .review }.reduce(0) { $0 + $1.size }
    }

    var devArtifactTotal: Int64 { devArtifacts.reduce(0) { $0 + $1.size } }

    var hasAnalysisData: Bool { junkReady || rootNode != nil }

    var recommendations: [Recommendation] {
        var recs: [Recommendation] = []

        if let d = disk {
            let pct = d.freeFraction.formatted(.percent.precision(.fractionLength(0)))
            if d.freeFraction < 0.10 {
                recs.append(.init(id: "disk", level: .critical, icon: "exclamationmark.octagon.fill",
                                  title: "Disk neredeyse dolu",
                                  detail: "Yalnızca \(d.available.formattedBytes) (\(pct)) boş alan kaldı. macOS'un rahat çalışması için en az %15 boş alan önerilir. Aşağıdaki önerilerle başla.",
                                  action: .storageSettings, actionTitle: "Depolama Ayarları"))
            } else if d.freeFraction < 0.20 {
                recs.append(.init(id: "disk", level: .warning, icon: "exclamationmark.triangle.fill",
                                  title: "Boş alan azalıyor",
                                  detail: "\(d.available.formattedBytes) (\(pct)) boş alan var. Biraz temizlik iyi olur."))
            } else {
                recs.append(.init(id: "disk", level: .good, icon: "checkmark.seal.fill",
                                  title: "Disk durumu iyi",
                                  detail: "\(d.total.formattedBytes) diskin \(d.available.formattedBytes) (\(pct)) kısmı boş."))
            }
        }

        if !hasFullDiskAccess {
            recs.append(.init(id: "fda", level: .info, icon: "lock.shield",
                              title: "Tam Disk Erişimi verilmemiş",
                              detail: "Çöp Kutusu, Mail ve cihaz yedekleri gibi bazı klasörler okunamıyor. Daha doğru sonuç için CleanMac'e Tam Disk Erişimi verebilirsin (isteğe bağlı).",
                              action: .fullDiskAccess, actionTitle: "Ayarları Aç"))
        }

        if junkReady {
            for c in junkCategories where c.size >= 50_000_000 {
                let safe = c.safety == .safe
                recs.append(.init(
                    id: "junk-\(c.id)", level: safe ? .suggestion : .info, icon: c.icon,
                    title: "\(c.title): \(c.size.formattedBytes)",
                    detail: safe ? c.detail : c.detail + " Öğeleri tek tek gözden geçirmeni öneririm.",
                    size: c.size,
                    action: safe ? .cleanJunk(c.id) : .open(.junk),
                    actionTitle: safe ? (c.permanentOnly ? "Boşalt" : "Temizle") : "İncele"))
            }
        }

        if rootNode != nil {
            if devArtifactTotal >= 200_000_000 {
                recs.append(.init(id: "dev", level: .suggestion, icon: "shippingbox.fill",
                                  title: "\(devArtifacts.count) proje bağımlılık klasörü: \(devArtifactTotal.formattedBytes)",
                                  detail: "node_modules, .venv, Pods gibi klasörler. Üzerinde çalışmadığın projelerinkini silebilirsin; gerektiğinde npm install / pip install ile geri gelir.",
                                  size: devArtifactTotal, action: .open(.junk), actionTitle: "İncele"))
            }
            let stale = staleLargeFiles
            if !stale.isEmpty {
                let total = stale.reduce(Int64(0)) { $0 + $1.size }
                recs.append(.init(id: "stale", level: .suggestion, icon: "clock.badge.questionmark",
                                  title: "\(Self.staleDays / 30)+ aydır kullanılmayan \(stale.count) büyük dosya: \(total.formattedBytes)",
                                  detail: "Uzun süredir açılmayan 100 MB üzeri dosyalar. Harici diske ya da buluta taşımayı düşünebilirsin.",
                                  size: total, action: .openStaleLargeFiles, actionTitle: "Göster"))
            }
            let huge = files.filter { !$0.isProtected && $0.size >= 1_000_000_000 }.sorted { $0.size > $1.size }
            if !huge.isEmpty {
                let names = huge.prefix(3).map { "\($0.name) (\($0.size.formattedBytes))" }.joined(separator: ", ")
                recs.append(.init(id: "huge", level: .info, icon: "doc.badge.arrow.up",
                                  title: "1 GB üzeri \(huge.count) dosya var",
                                  detail: "En büyükleri: \(names).",
                                  size: huge.reduce(0) { $0 + $1.size }, action: .open(.largeFiles), actionTitle: "Listele"))
            }
            if let root = rootNode, let top = root.children.first(where: { !$0.isAggregate && $0.isDirectory }) {
                recs.append(.init(id: "top", level: .info, icon: "folder.fill",
                                  title: "En çok yer kaplayan klasör: \(top.url.abbreviatedPath)",
                                  detail: "\(top.size.formattedBytes) · \(top.fileCount.formatted()) dosya. İçine bakıp neyin büyüdüğünü görebilirsin.",
                                  size: top.size, action: .openFolder(top), actionTitle: "Aç"))
            }
        }

        if duplicatesReady, visibleDuplicateWaste >= 50_000_000 {
            recs.append(.init(id: "dups", level: .suggestion, icon: "doc.on.doc.fill",
                              title: "Tekrarlanan dosyalar \(visibleDuplicateWaste.formattedBytes) boşa yer kaplıyor",
                              detail: "Aynı içeriğe sahip birden fazla kopya bulundu. Her gruptan birini saklayıp diğerlerini kaldırabilirsin.",
                              size: visibleDuplicateWaste, action: .open(.duplicates), actionTitle: "İncele"))
        }

        return recs.sorted {
            if $0.level != $1.level { return $0.level.rawValue < $1.level.rawValue }
            return ($0.size ?? 0) > ($1.size ?? 0)
        }
    }
}

struct AssistantView: View {
    @EnvironmentObject var state: AppState
    @State private var pendingClean: JunkCategory?
    @AppStorage("permanentDelete") private var permanentDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if state.isAnalyzing { progressCard }
                if state.hasAnalysisData { summary }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Öneriler").font(.title2.bold())
                    ForEach(state.recommendations) { rec in
                        RecommendationRow(rec: rec) { handle($0) }
                    }
                    if !state.hasAnalysisData && !state.isAnalyzing {
                        Text("Analizi başlattığında Mac'ine özel öneriler burada görünecek.")
                            .foregroundStyle(.secondary)
                    }
                }
                tips
            }
            .padding(24)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog(pendingClean.map { "\($0.title) temizlensin mi?" } ?? "",
                            isPresented: Binding(get: { pendingClean != nil }, set: { if !$0 { pendingClean = nil } }),
                            presenting: pendingClean) { category in
            Button(category.permanentOnly ? "Çöpü Boşalt" : "Temizle (\(category.size.formattedBytes))", role: .destructive) {
                Task { await state.cleanJunkCategory(category.id) }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { category in
            Text(category.permanentOnly || permanentDelete
                 ? "\(category.items.count) öğe kalıcı olarak silinecek. Bu işlem geri alınamaz."
                 : "\(category.items.count) öğe Çöp Kutusu'na taşınacak. Yer açmak için daha sonra çöpü boşaltman gerekir.")
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 8) {
                Text("Merhaba! Ben depolama asistanın.").font(.title.bold())
                Text("Mac'ini tarayıp neyin yer kapladığını bulurum, güvenle silinebilecekleri önerir ve tekrar eden dosyaları gösteririm. Her şey bu bilgisayarda çalışır; sen onaylamadan hiçbir dosya silinmez ve varsayılan olarak her şey Çöp Kutusu'na taşınır.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button {
                        Task { await state.runFullAnalysis() }
                    } label: {
                        Label(state.lastAnalysis == nil ? "Tam Analizi Başlat" : "Analizi Yenile", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(state.isAnalyzing || state.isScanning)

                    Button("Farklı klasör seç…") {
                        if state.chooseScanRoot() { Task { await state.runFullAnalysis() } }
                    }
                    .controlSize(.large)
                    .disabled(state.isAnalyzing || state.isScanning)

                    Text("Taranacak: \(state.scanRoot.abbreviatedPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    private var progressCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(state.analysisStep).font(.headline)
                    Spacer()
                    Button("Durdur") { state.cancelScan() }
                }
                if let p = state.scanProgress {
                    Text("\(p.files.formatted()) dosya · \(p.bytes.formattedBytes) — \(URL(fileURLWithPath: p.currentPath).abbreviatedPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if state.isFindingDuplicates {
                    ProgressView(value: state.duplicateProgress)
                }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            SummaryTile(title: "Güvenle temizlenebilir", value: state.safeJunkTotal, color: .green,
                        note: "Önbellek, günlük, geliştirici artıkları")
            SummaryTile(title: "Gözden geçirilebilir", value: state.reviewJunkTotal + state.devArtifactTotal + state.visibleDuplicateWaste,
                        color: .orange, note: "İndirmeler, bağımlılıklar, tekrarlar")
            if let d = state.disk {
                SummaryTile(title: "Şu an boş alan", value: d.available, color: usageColor(d.usedFraction),
                            note: "\(d.total.formattedBytes) diskin")
            }
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("İpuçları").font(.title2.bold())
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    tip("internaldrive", "Sistem Ayarları › Genel › Depolama bölümündeki önerileri de kontrol et.")
                    tip("icloud", "iCloud Drive'da \"Mac Depolamasını Optimize Et\" açıksa az kullanılan dosyalar yerelden kaldırılır.")
                    tip("clock.arrow.circlepath", "Time Machine yerel anlık görüntüleri: Terminal'de `tmutil listlocalsnapshots /`")
                    tip("shippingbox", "Docker kullanıyorsan `docker system prune -a` kullanılmayan imajları temizler.")
                    tip("iphone", "Eski simülatörler için: `xcrun simctl delete unavailable`")
                }
            }
        }
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        Label { Text(.init(text)) } icon: { Image(systemName: icon).foregroundStyle(Color.accentColor) }
    }

    private func handle(_ action: Recommendation.Action) {
        switch action {
        case .open(let s): state.section = s
        case .openStaleLargeFiles:
            state.largeFilesStaleOnly = true
            state.section = .largeFiles
        case .cleanJunk(let id): pendingClean = state.junkCategories.first { $0.id == id }
        case .openFolder(let node):
            state.currentNode = node
            state.section = .explorer
        case .fullDiskAccess: Finder.openFullDiskAccessSettings()
        case .storageSettings: Finder.openStorageSettings()
        }
    }
}

private struct SummaryTile: View {
    let title: String
    let value: Int64
    let color: Color
    let note: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text(value.formattedBytes).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(color)
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct RecommendationRow: View {
    let rec: Recommendation
    let onAction: (Recommendation.Action) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: rec.icon)
                .font(.title3)
                .foregroundStyle(rec.level.color)
                .frame(width: 36, height: 36)
                .background(rec.level.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 4) {
                Text(rec.title).font(.headline)
                Text(rec.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if let action = rec.action, let title = rec.actionTitle {
                Button(title) { onAction(action) }
                    .controlSize(.regular)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(rec.level.color.opacity(0.25)))
    }
}
