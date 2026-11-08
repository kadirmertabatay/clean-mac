import SwiftUI

struct AppsView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: InstalledApp.ID?
    @State private var sortOrder = [KeyPathComparator(\InstalledApp.size, order: .reverse)]
    @State private var unusedOnly = false
    @State private var search = ""

    private var filtered: [InstalledApp] {
        let cutoff = Date().addingTimeInterval(-Double(AppState.staleDays) * 86_400)
        return state.apps.filter { app in
            (!unusedOnly || app.lastUsedSort < cutoff)
                && (search.isEmpty || app.name.localizedCaseInsensitiveContains(search))
        }
        .sorted(using: sortOrder)
    }

    var body: some View {
        let items = filtered
        VStack(spacing: 0) {
            PageHeader(title: "Uygulamalar",
                       subtitle: "Kullanmadığın uygulamaları, Library'de bıraktıkları dosyalarla birlikte kaldır") {
                Button {
                    Task { await state.loadApps() }
                } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                    .disabled(state.isLoadingApps)
            }
            Divider()
            if state.isLoadingApps && state.apps.isEmpty {
                ProgressView("Uygulamalar ölçülüyor…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 14) {
                    Toggle("6+ ay açılmayanlar", isOn: $unusedOnly).toggleStyle(.checkbox).fixedSize()
                    Spacer()
                    Text("\(items.count) uygulama · \(items.reduce(Int64(0)) { $0 + $1.size }.formattedBytes)")
                        .foregroundStyle(.secondary)
                    TextField("Ara", text: $search).textFieldStyle(.roundedBorder).frame(width: 180)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider()
                HStack(spacing: 0) {
                    Table(items, selection: $selection, sortOrder: $sortOrder) {
                        TableColumn("Uygulama", value: \.name) { app in
                            HStack(spacing: 8) {
                                FileIconView(url: app.url, size: 22)
                                Text(app.name).lineLimit(1)
                                if app.isApple {
                                    Image(systemName: "apple.logo").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .width(min: 180, ideal: 240)
                        TableColumn("Boyut", value: \.size) { app in
                            Text(app.size.formattedBytes).monospacedDigit()
                        }
                        .width(min: 70, ideal: 90, max: 110)
                        TableColumn("Son Açılma", value: \.lastUsedSort) { app in
                            Text(app.lastUsed.map { $0.formatted(.relative(presentation: .named)) } ?? "Bilinmiyor")
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 100, ideal: 130)
                    }
                    Divider()
                    Group {
                        if let id = selection, let app = state.apps.first(where: { $0.id == id }) {
                            AppDetail(app: app).id(app.id)
                        } else {
                            EmptyStateView(icon: "app.dashed", title: "Bir uygulama seç",
                                           message: "Kaldırmadan önce bıraktığı dosyaları burada görürsün.")
                        }
                    }
                    .frame(width: 340)
                }
            }
        }
        .task { if state.apps.isEmpty && !state.isLoadingApps { await state.loadApps() } }
    }
}

private struct AppDetail: View {
    @EnvironmentObject var state: AppState
    let app: InstalledApp
    @State private var leftovers: [AppLeftover]?
    @State private var selected = Set<String>()
    @State private var confirm = false

    private var total: Int64 {
        app.size + (leftovers ?? []).filter { selected.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                FileIconView(url: app.url, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.title3.bold())
                    Text([app.version.map { "Sürüm \($0)" }, app.bundleID].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            HStack {
                Text("Uygulama").foregroundStyle(.secondary)
                Spacer()
                Text(app.size.formattedBytes).monospacedDigit()
            }
            Divider()
            Text("Kalıntı dosyalar").font(.headline)
            if let leftovers {
                if leftovers.isEmpty {
                    Text("Library'de bu uygulamaya ait dosya bulunamadı.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(leftovers) { l in
                                HStack(spacing: 8) {
                                    Checkbox(state: selected.contains(l.id) ? .on : .off) {
                                        if selected.contains(l.id) { selected.remove(l.id) } else { selected.insert(l.id) }
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(l.kind)
                                        Text(l.url.abbreviatedPath).font(.caption2).foregroundStyle(.secondary)
                                            .lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer()
                                    Text(l.size.formattedBytes).font(.caption).monospacedDigit()
                                }
                                .help(l.url.path)
                            }
                        }
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
            Spacer()
            if app.isApple {
                Label("macOS ile gelen uygulamalar kaldırılmamalı.", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Finder'da Göster") { Finder.reveal([app.url]) }
                Spacer()
                Button("Kaldır (\(total.formattedBytes))", role: .destructive) { confirm = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(app.isApple || leftovers == nil || state.isRemoving)
            }
        }
        .padding(16)
        .task {
            let found = await Task.detached(priority: .userInitiated) { AppInventory.leftovers(for: app) }.value
            leftovers = found
            selected = Set(found.map(\.id))
        }
        .confirmationDialog("\(app.name) kaldırılsın mı?", isPresented: $confirm) {
            Button("Çöp Kutusu'na Taşı (\(total.formattedBytes))", role: .destructive) {
                Task { await state.uninstall(app, leftovers: (leftovers ?? []).filter { selected.contains($0.id) }) }
            }
        } message: {
            Text(app.isRunning
                 ? "Uygulama şu an açık; önce kapatılacak. Uygulama ve seçili \(selected.count) kalıntı Çöp Kutusu'na taşınacak, Geçmiş'ten geri alınabilir."
                 : "Uygulama ve seçili \(selected.count) kalıntı Çöp Kutusu'na taşınacak, Geçmiş'ten geri alınabilir.")
        }
    }
}
