import SwiftUI

struct DuplicatesView: View {
    @EnvironmentObject var state: AppState
    @State private var selected = Set<String>()
    @State private var showProtected = false
    @State private var confirm = false
    @State private var warning: String?

    private static let sizeOptions: [(String, Int64)] = [
        ("1 MB", 1_000_000), ("10 MB", 10_000_000), ("50 MB", 50_000_000), ("100 MB", 100_000_000),
    ]

    private var groups: [DuplicateGroup] {
        state.duplicateGroups.compactMap { g in
            let files = showProtected ? g.files : g.files.filter { !$0.isProtected }
            return files.count > 1 ? DuplicateGroup(id: g.id, size: g.size, files: files) : nil
        }
    }

    var body: some View {
        let groups = groups
        let selectedFiles = groups.flatMap(\.files).filter { selected.contains($0.id) }
        let selectedSize = selectedFiles.reduce(Int64(0)) { $0 + $1.size }

        VStack(spacing: 0) {
            PageHeader(title: "Tekrarlanan Dosyalar", subtitle: "İçeriği birebir aynı olan dosyalar (SHA-256 ile doğrulanır)") {
                Picker("En az", selection: $state.duplicateMinSize) {
                    ForEach(Self.sizeOptions, id: \.1) { Text($0.0).tag($0.1) }
                }
                .frame(width: 130)
                Button {
                    selected = []
                    Task { await state.findDuplicates() }
                } label: { Label(state.duplicatesReady ? "Yeniden Ara" : "Tekrarları Bul", systemImage: "magnifyingglass") }
                    .disabled(state.isScanning || state.isFindingDuplicates)
            }
            Divider()
            if state.isScanning {
                ScanningView()
            } else if state.isFindingDuplicates {
                VStack(spacing: 14) {
                    ProgressView(value: state.duplicateProgress).frame(width: 320)
                    Text("Dosyalar karşılaştırılıyor… \(state.duplicateProgress.formatted(.percent.precision(.fractionLength(0))))")
                    Button("Durdur") { state.cancelScan() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !state.duplicatesReady {
                EmptyStateView(icon: "doc.on.doc", title: "Tekrarlanan dosyaları bul",
                               message: "\(state.scanRoot.abbreviatedPath) içindeki dosyalar boyut ve içerik özetiyle karşılaştırılır. Dosyalar yalnızca okunur, hiçbir şey değiştirilmez.",
                               actionTitle: "Tekrarları Bul") { Task { await state.findDuplicates() } }
            } else if groups.isEmpty {
                EmptyStateView(icon: "checkmark.circle", title: "Tekrarlanan dosya yok",
                               message: "Seçilen boyutun üzerinde aynı içeriğe sahip dosya bulunamadı.")
            } else {
                List {
                    ForEach(groups) { g in
                        Section {
                            ForEach(Array(g.files.enumerated()), id: \.element.id) { i, f in
                                row(f, isOriginal: i == 0)
                            }
                        } header: {
                            HStack {
                                Text("\(g.files.count) kopya · her biri \(g.size.formattedBytes)")
                                Spacer()
                                Text("Boşa giden: \(g.wasted.formattedBytes)").foregroundStyle(.orange)
                            }
                        }
                    }
                }
                Divider()
                HStack(spacing: 12) {
                    Text("\(groups.count) grup · boşa giden \(groups.reduce(Int64(0)) { $0 + $1.wasted }.formattedBytes)")
                        .foregroundStyle(.secondary)
                    Toggle("Sistem dosyaları", isOn: $showProtected)
                        .toggleStyle(.checkbox)
                        .fixedSize()
                        .help("~/Library ve uygulama paketlerinin içindeki kopyaları da göster.")
                    Spacer()
                    Button("Akıllı Seç") { smartSelect(groups) }
                        .help("Her gruptaki en eski dosyayı korur, diğer kopyaları seçer.")
                    Button("Seçimi Temizle") { selected = [] }.disabled(selected.isEmpty)
                    Button("Çöp Kutusu'na Taşı (\(selectedFiles.count))", role: .destructive) {
                        if let problem = validate(groups) { warning = problem } else { confirm = true }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(selectedFiles.isEmpty || state.isRemoving)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .confirmationDialog("\(selectedFiles.count) kopya Çöp Kutusu'na taşınsın mı?", isPresented: $confirm) {
            Button("Çöp Kutusu'na Taşı (\(selectedSize.formattedBytes))", role: .destructive) {
                let targets = selectedFiles.map { RemovalTarget(url: $0.url, size: $0.size) }
                selected = []
                Task { await state.remove(targets, permanently: false) }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Her gruptan en az bir kopya korunacak. Dosyalar Çöp Kutusu'ndan geri alınabilir.")
        }
        .alert("Dikkat", isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } })) {
            Button("Tamam") {}
        } message: {
            Text(warning ?? "")
        }
    }

    private func row(_ f: FileEntry, isOriginal: Bool) -> some View {
        HStack(spacing: 10) {
            Checkbox(state: selected.contains(f.id) ? .on : .off) {
                if selected.contains(f.id) { selected.remove(f.id) } else { selected.insert(f.id) }
            }
            FileIconView(url: f.url, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(f.name).lineLimit(1)
                    if isOriginal {
                        Text("en eski").font(.caption2.bold()).foregroundStyle(.green)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.green.opacity(0.15), in: Capsule())
                    }
                }
                Text(f.parentPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(f.modified?.formatted(date: .abbreviated, time: .shortened) ?? "")
                .font(.caption).foregroundStyle(.secondary)
            Button { Finder.reveal([f.url]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Finder'da göster")
        }
        .padding(.vertical, 2)
    }

    private func smartSelect(_ groups: [DuplicateGroup]) {
        var s = Set<String>()
        for g in groups { for f in g.files.dropFirst() { s.insert(f.id) } }
        selected = s
    }

    private func validate(_ groups: [DuplicateGroup]) -> String? {
        let full = groups.filter { g in g.files.allSatisfy { selected.contains($0.id) } }
        guard !full.isEmpty else { return nil }
        return "\(full.count) grupta tüm kopyalar seçili. Verini kaybetmemek için her gruptan en az bir dosyayı seçimden çıkar."
    }
}
