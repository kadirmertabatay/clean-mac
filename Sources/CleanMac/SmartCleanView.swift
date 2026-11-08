import SwiftUI

struct SmartCleanView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("smartLevel") private var levelRaw = SmartLevel.safe.rawValue
    @State private var appSearch = ""
    @State private var showAllApps = false
    @State private var plan: SmartPlan?
    @State private var selected = Set<String>()
    @State private var expanded = Set<String>()
    @State private var building = false
    @State private var confirm = false

    private var level: SmartLevel { SmartLevel(rawValue: levelRaw) ?? .safe }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                step(1, "Nelere dokunulmasın?", "Seçtiklerine ait hiçbir dosya silinmez — önbellekleri ve verileri dahil.") { protectionsCard }
                step(2, "Ne kadar kapsamlı olsun?", level.detail) { levelPicker }
                step(3, "Plan", plan == nil ? "Planı hazırla; hiçbir şey sen onaylamadan silinmez." : "Gözden geçir, istemediklerini çıkar, sonra uygula.") { planCard }
            }
            .padding(24)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .task {
            if state.apps.isEmpty { await state.loadApps() }
            if ScreenshotMode.isActive && plan == nil { await build() }
        }
        .confirmationDialog("Akıllı Silme planı uygulansın mı?", isPresented: $confirm) {
            Button("Uygula (\(selectedSize.formattedBytes))", role: .destructive) {
                guard let plan else { return }
                let sel = selected
                Task {
                    await state.applySmartPlan(plan, selected: sel)
                    self.plan = nil
                    selected = []
                }
            }
        } message: {
            Text("\(selected.count) öğe Çöp Kutusu'na taşınacak\(UserDefaults.standard.bool(forKey: "permanentDelete") ? " (önbellekler kalıcı silinir)" : ""). Geçmiş ekranından geri alınabilir. Korunan alanlara dokunulmaz.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "wand.and.sparkles")
                .font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(LinearGradient(colors: [.indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 6) {
                Text("Akıllı Silme").font(.title.bold())
                Text("Önce neyin korunacağını söyle, ben de geri kalanından güvenle silinebilecekleri tek bir plan halinde çıkarayım. Korumaların Otomatik Temizlik kurallarında ve asistanın hızlı temizleme düğmelerinde de geçerlidir.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func step<Content: View>(_ n: Int, _ title: String, _ subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(n)").font(.headline).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(Color.accentColor, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title3.bold())
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
    }

    // MARK: 1. Korumalar

    private var protectionsCard: some View {
        let catalog = state.protectionCatalog
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Protection.Group.allCases, id: \.self) { group in
                    let items = catalog.filter { $0.group == group }
                    if !items.isEmpty { protectionGroup(group, items) }
                }
                if state.isLoadingApps {
                    HStack { ProgressView().controlSize(.small); Text("Uygulamalar okunuyor…").foregroundStyle(.secondary) }
                }
                let active = state.activeProtections
                if !active.isEmpty {
                    Divider()
                    Label("Korunuyor: " + active.map(\.title).joined(separator: ", "), systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        }
    }

    @ViewBuilder private func protectionGroup(_ group: Protection.Group, _ items: [Protection]) -> some View {
        let filtered = group == .apps
            ? items.filter { appSearch.isEmpty || $0.title.localizedCaseInsensitiveContains(appSearch) }
            : items
        let visible = group == .apps && !showAllApps && appSearch.isEmpty ? Array(filtered.prefix(12)) : filtered
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.rawValue).font(.headline)
                Spacer()
                if group == .apps {
                    TextField("Uygulama ara", text: $appSearch).textFieldStyle(.roundedBorder).frame(width: 180)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(visible) { p in chip(p) }
            }
            if group == .apps && appSearch.isEmpty && filtered.count > 12 {
                Button(showAllApps ? "Daha az göster" : "Tüm uygulamaları göster (\(filtered.count))") { showAllApps.toggle() }
                    .buttonStyle(.link)
            }
        }
    }

    private func chip(_ p: Protection) -> some View {
        let on = state.smartProtectionIDs.contains(p.id)
        return Button {
            state.setProtection(p.id, !on)
            plan = nil
        } label: {
            HStack(spacing: 8) {
                if let url = p.appURL { FileIconView(url: url, size: 18) } else {
                    Image(systemName: p.icon).frame(width: 18).foregroundStyle(on ? Color.white : Color.accentColor)
                }
                Text(p.title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: on ? "lock.fill" : "lock.open").font(.caption)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .foregroundStyle(on ? Color.white : Color.primary)
            .background(on ? Color.accentColor : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(on ? "Korunuyor — silinmeyecek" : "Korunmuyor — tıkla ve koru")
    }

    // MARK: 2. Kapsam

    private var levelPicker: some View {
        Picker("", selection: Binding(get: { level }, set: { levelRaw = $0.rawValue; plan = nil })) {
            ForEach(SmartLevel.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 420)
    }

    // MARK: 3. Plan

    private var selectedSize: Int64 {
        (plan?.groups.flatMap(\.items) ?? []).filter { selected.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    @ViewBuilder private var planCard: some View {
        if let plan {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    if plan.groups.isEmpty {
                        Label("Bu kapsamda ve korumalarla silinecek bir şey bulunamadı.", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                    ForEach(plan.groups) { g in groupRow(g) }
                    if !plan.protected.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Korunduğu için atlananlar", systemImage: "lock.shield").font(.headline)
                            ForEach(plan.protected, id: \.title) { p in
                                HStack {
                                    Text(p.title)
                                    Spacer()
                                    Text("\(p.count) öğe · \(p.size.formattedBytes)").foregroundStyle(.secondary).monospacedDigit()
                                }
                                .font(.callout)
                            }
                        }
                    }
                    Divider()
                    HStack {
                        Button("Yeniden Hazırla") { Task { await build() } }.disabled(building)
                        Spacer()
                        Text("Seçili: \(selected.count) öğe · \(selectedSize.formattedBytes)").bold()
                        Button("Planı Uygula") { confirm = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(selected.isEmpty || state.isRemoving)
                    }
                }
            }
        } else {
            HStack(spacing: 12) {
                Button {
                    Task { await build() }
                } label: {
                    Label("Planı Hazırla", systemImage: "list.bullet.clipboard")
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(building || state.isScanning)
                if building {
                    ProgressView().controlSize(.small)
                    Text(state.smartStep).foregroundStyle(.secondary)
                    Button("Durdur") { state.cancelScan() }
                }
            }
        }
    }

    private func build() async {
        building = true
        plan = await state.buildSmartPlan(level: level)
        selected = Set(plan?.groups.flatMap { $0.items.map(\.id) } ?? [])
        building = false
    }

    private func groupRow(_ g: SmartPlanGroup) -> some View {
        let ids = g.items.map(\.id)
        let n = ids.filter { selected.contains($0) }.count
        return DisclosureGroup(isExpanded: Binding(get: { expanded.contains(g.id) },
                                                   set: { if $0 { expanded.insert(g.id) } else { expanded.remove(g.id) } })) {
            ForEach(g.items.prefix(200)) { item in
                HStack(spacing: 8) {
                    Checkbox(state: selected.contains(item.id) ? .on : .off) {
                        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                    }
                    FileIconView(url: item.url, size: 16)
                    Text(item.url.abbreviatedPath).font(.caption).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(item.size.formattedBytes).font(.caption).monospacedDigit()
                }
                .contextMenu {
                    Button("Finder'da Göster") { Finder.reveal([item.url]) }
                    Button("Hariç Tut") {
                        state.addExclusion(item.url)
                        selected.remove(item.id)
                    }
                }
            }
            if g.items.count > 200 {
                Text("… ve \(g.items.count - 200) öğe daha").font(.caption).foregroundStyle(.secondary)
            }
        } label: {
            HStack(spacing: 10) {
                Checkbox(state: n == 0 ? .off : n == ids.count ? .on : .mixed) {
                    if n == ids.count { ids.forEach { selected.remove($0) } } else { ids.forEach { selected.insert($0) } }
                }
                Image(systemName: g.icon).foregroundStyle(Color.accentColor).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.title).font(.headline)
                    Text(g.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(g.size.formattedBytes).font(.headline).monospacedDigit()
                    Text("\(g.items.count) öğe").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
