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
            PageHeader(title: L("Apps"),
                       subtitle: L("Remove apps you don’t use, together with the files they left in Library")) {
                Button {
                    Task { await state.loadApps() }
                } label: { Label(L("Refresh"), systemImage: "arrow.clockwise") }
                    .disabled(state.isLoadingApps)
            }
            Divider()
            if state.isLoadingApps && state.apps.isEmpty {
                ProgressView(L("Measuring apps…")).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 14) {
                    Toggle(L("Not opened in 6+ months"), isOn: $unusedOnly).toggleStyle(.checkbox).fixedSize()
                    Spacer()
                    Text(L("\(items.count) apps · \(items.reduce(Int64(0)) { $0 + $1.size }.formattedBytes)"))
                        .foregroundStyle(.secondary)
                    TextField(L("Search"), text: $search).textFieldStyle(.roundedBorder).frame(width: 180)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider()
                HStack(spacing: 0) {
                    Table(items, selection: $selection, sortOrder: $sortOrder) {
                        TableColumn(L("App"), value: \.name) { app in
                            HStack(spacing: 8) {
                                FileIconView(url: app.url, size: 22)
                                Text(app.name).lineLimit(1)
                                if app.isApple {
                                    Image(systemName: "apple.logo").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .width(min: 180, ideal: 240)
                        TableColumn(L("Size"), value: \.size) { app in
                            Text(app.size.formattedBytes).monospacedDigit()
                        }
                        .width(min: 70, ideal: 90, max: 110)
                        TableColumn(L("Last Opened"), value: \.lastUsedSort) { app in
                            Text(app.lastUsed.map { $0.formatted(.relative(presentation: .named)) } ?? L("Unknown"))
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 100, ideal: 130)
                    }
                    Divider()
                    Group {
                        if let id = selection, let app = state.apps.first(where: { $0.id == id }) {
                            AppDetail(app: app).id(app.id)
                        } else {
                            EmptyStateView(icon: "app.dashed", title: L("Select an app"),
                                           message: L("See the files it left behind before you remove it."))
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
                    Text([app.version.map { L("Version \($0)") }, app.bundleID].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            HStack {
                Text(L("App")).foregroundStyle(.secondary)
                Spacer()
                Text(app.size.formattedBytes).monospacedDigit()
            }
            Divider()
            Text(L("Leftover files")).font(.headline)
            if let leftovers {
                if leftovers.isEmpty {
                    Text(L("No files belonging to this app were found in Library.")).font(.caption).foregroundStyle(.secondary)
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
                Label(L("Apps that ship with macOS shouldn’t be removed."), systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(L("Show in Finder")) { Finder.reveal([app.url]) }
                Spacer()
                Button(L("Uninstall (\(total.formattedBytes))"), role: .destructive) { confirm = true }
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
        .confirmationDialog(L("Uninstall \(app.name)?"), isPresented: $confirm) {
            Button(L("Move to Trash (\(total.formattedBytes))"), role: .destructive) {
                Task { await state.uninstall(app, leftovers: (leftovers ?? []).filter { selected.contains($0.id) }) }
            }
        } message: {
            Text(app.isRunning
                 ? L("The app is running and will be quit first. The app and \(selected.count) selected leftovers will be moved to the Trash and can be restored from History.")
                 : L("The app and \(selected.count) selected leftovers will be moved to the Trash and can be restored from History."))
        }
    }
}
