import SwiftUI

struct RulesView: View {
    @EnvironmentObject var state: AppState
    @State private var preview: (rule: CleanupRule, targets: [RemovalTarget])?
    @State private var loadingPreview: UUID?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Otomatik Temizlik",
                       subtitle: "Zamanı gelen kurallar önce önizleme hazırlar ve bildirim gönderir; onaylayınca uygulanır. Hariç tutulanlara asla dokunulmaz.") {
                Menu {
                    ForEach(CleanupRule.presets.filter { p in !state.rules.contains { $0.kind == p.kind } }, id: \.kind) { preset in
                        Button("\(preset.interval.title): \(preset.title)") { state.addRule(preset) }
                    }
                } label: { Label("Kural Ekle", systemImage: "plus") }
                    .fixedSize()
            }
            Divider()
            if state.rules.isEmpty {
                EmptyStateView(icon: "calendar.badge.clock", title: "Henüz kural yok",
                               message: "Örneğin \"her hafta uygulama önbelleklerini temizle\" gibi bir kural ekle. Kurallar varsayılan olarak önce sana sorar.",
                               actionTitle: "Önerilen Kuralları Ekle") {
                    CleanupRule.presets.prefix(3).forEach(state.addRule)
                }
            } else {
                List {
                    ForEach(state.rules) { rule in row(rule) }
                }
            }
        }
        .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            if let preview { previewSheet(preview.rule, preview.targets) }
        }
    }

    private func binding<T>(_ rule: CleanupRule, _ keyPath: WritableKeyPath<CleanupRule, T>) -> Binding<T> {
        Binding(get: { state.rules.first { $0.id == rule.id }?[keyPath: keyPath] ?? rule[keyPath: keyPath] },
                set: { value in state.updateRule(rule.id) { $0[keyPath: keyPath] = value } })
    }

    private func row(_ rule: CleanupRule) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: rule.icon).font(.title3).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(rule.title).font(.headline)
                    if let pending = rule.pendingSize {
                        Text("Onay bekliyor · \(pending.formattedBytes)")
                            .font(.caption.bold()).foregroundStyle(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }
                }
                HStack(spacing: 16) {
                    Picker("", selection: binding(rule, \.interval)) {
                        ForEach(CleanupRule.Interval.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    Toggle("Onay istemeden uygula", isOn: binding(rule, \.autoApply)).toggleStyle(.checkbox)
                }
                Text(statusText(rule)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Toggle("", isOn: binding(rule, \.enabled)).toggleStyle(.switch).labelsHidden()
                HStack {
                    Button("Önizle") { Task { await showPreview(rule) } }
                        .disabled(loadingPreview != nil)
                    Button(role: .destructive) { state.deleteRule(rule.id) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func statusText(_ rule: CleanupRule) -> String {
        let last = rule.lastRun.map { "Son çalışma: \($0.formatted(.relative(presentation: .named)))" } ?? "Henüz çalışmadı"
        guard rule.enabled else { return last + " · Kapalı" }
        return last + " · Sonraki: \(rule.nextRun.formatted(date: .abbreviated, time: .omitted))"
    }

    private func showPreview(_ rule: CleanupRule) async {
        loadingPreview = rule.id
        let targets = await Task.detached(priority: .userInitiated) { RuleEngine.targets(for: rule) }.value
        loadingPreview = nil
        preview = (rule, targets.filter { !state.isExcluded($0.url.path) })
    }

    private func previewSheet(_ rule: CleanupRule, _ targets: [RemovalTarget]) -> some View {
        let total = targets.reduce(Int64(0)) { $0 + $1.size }
        return VStack(alignment: .leading, spacing: 12) {
            Text(rule.title).font(.title2.bold())
            Text(targets.isEmpty ? "Şu an temizlenecek bir şey yok." :
                    "\(targets.count) öğe · \(total.formattedBytes) — \(RuleEngine.isPermanent(rule) ? "kalıcı olarak silinecek" : "Çöp Kutusu'na taşınacak")")
                .foregroundStyle(.secondary)
            List(targets.sorted { $0.size > $1.size }, id: \.url) { t in
                HStack {
                    FileIconView(url: t.url, size: 18)
                    Text(t.url.abbreviatedPath).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(t.size.formattedBytes).monospacedDigit()
                }
            }
            .frame(minHeight: 260)
            HStack {
                Spacer()
                Button("Vazgeç") { preview = nil }.keyboardShortcut(.cancelAction)
                Button("Şimdi Uygula") {
                    preview = nil
                    Task { await state.runRule(rule.id, targets: targets) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(targets.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620, height: 480)
    }
}
