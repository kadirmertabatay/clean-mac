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
                step(1, L("What should never be touched?"), L("No file belonging to your choices is deleted, including their caches and data.")) { protectionsCard }
                step(2, L("How thorough?"), level.detail) { levelPicker }
                step(3, "Plan", plan == nil ? L("Prepare the plan; nothing is deleted without your approval.") : L("Review it, remove what you don’t want, then apply.")) { planCard }
            }
            .padding(24)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .task {
            if state.apps.isEmpty { await state.loadApps() }
            if ScreenshotMode.isActive && plan == nil { await build() }
        }
        .confirmationDialog(L("Apply the Smart Cleanup plan?"), isPresented: $confirm) {
            Button(L("Apply (\(selectedSize.formattedBytes))"), role: .destructive) {
                guard let plan else { return }
                let sel = selected
                Task {
                    await state.applySmartPlan(plan, selected: sel)
                    self.plan = nil
                    selected = []
                }
            }
        } message: {
            Text(L("\(selected.count) items will be moved to the Trash\(UserDefaults.standard.bool(forKey: "permanentDelete") ? L(" (caches are deleted permanently)") : ""). They can be restored from History. Protected areas aren’t touched."))
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
                Text(L("Smart Cleanup")).font(.title.bold())
                Text(L("Tell me what to protect, and I’ll turn everything else that can be safely deleted into a single plan. Your protections also apply to Auto Cleanup rules and the assistant’s quick clean buttons."))
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

    // MARK: 1. Protections

    private var protectionsCard: some View {
        let catalog = state.protectionCatalog
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Protection.Group.allCases, id: \.self) { group in
                    let items = catalog.filter { $0.group == group }
                    if !items.isEmpty { protectionGroup(group, items) }
                }
                if state.isLoadingApps {
                    HStack { ProgressView().controlSize(.small); Text(L("Reading apps…")).foregroundStyle(.secondary) }
                }
                let active = state.activeProtections
                if !active.isEmpty {
                    Divider()
                    Label(L("Protected: ") + active.map(\.title).joined(separator: ", "), systemImage: "lock.fill")
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
                Text(group.title).font(.headline)
                Spacer()
                if group == .apps {
                    TextField(L("Search apps"), text: $appSearch).textFieldStyle(.roundedBorder).frame(width: 180)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(visible) { p in chip(p) }
            }
            if group == .apps && appSearch.isEmpty && filtered.count > 12 {
                Button(showAllApps ? L("Show less") : L("Show all apps (\(filtered.count))")) { showAllApps.toggle() }
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
        .help(on ? L("Protected — won’t be deleted") : L("Not protected — click to protect"))
    }

    // MARK: 2. Scope

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
                        Label(L("Nothing to delete with this scope and these protections."), systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                    ForEach(plan.groups) { g in groupRow(g) }
                    if !plan.protected.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Label(L("Skipped because protected"), systemImage: "lock.shield").font(.headline)
                            ForEach(plan.protected, id: \.title) { p in
                                HStack {
                                    Text(p.title)
                                    Spacer()
                                    Text(L("\(p.count) items · \(p.size.formattedBytes)")).foregroundStyle(.secondary).monospacedDigit()
                                }
                                .font(.callout)
                            }
                        }
                    }
                    Divider()
                    HStack {
                        Button(L("Prepare Again")) { Task { await build() } }.disabled(building)
                        Spacer()
                        Text(L("Selected: \(selected.count) items · \(selectedSize.formattedBytes)")).bold()
                        Button(L("Apply Plan")) { confirm = true }
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
                    Label(L("Prepare Plan"), systemImage: "list.bullet.clipboard")
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(building || state.isScanning)
                if building {
                    ProgressView().controlSize(.small)
                    Text(state.smartStep).foregroundStyle(.secondary)
                    Button(L("Stop")) { state.cancelScan() }
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
                    Button(L("Show in Finder")) { Finder.reveal([item.url]) }
                    Button(L("Exclude")) {
                        state.addExclusion(item.url)
                        selected.remove(item.id)
                    }
                }
            }
            if g.items.count > 200 {
                Text(L("… and \(g.items.count - 200) more items")).font(.caption).foregroundStyle(.secondary)
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
                    Text(L("\(g.items.count) items")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
