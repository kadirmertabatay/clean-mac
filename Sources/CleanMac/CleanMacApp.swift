import AppKit
import SwiftUI

@main
struct CleanMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()
    @AppStorage(Prefs.menuBarEnabled) private var menuBarEnabled = true

    init() {
        Prefs.register()
    }

    var body: some Scene {
        WindowGroup("CleanMac", id: "main") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 1040, minHeight: 660)
                .task { SpaceMonitor.shared.start(state: state) }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Analiz") {
                Button("Tam Analizi Başlat") { Task { await state.runFullAnalysis() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Klasör Seç ve Tara…") { if state.chooseScanRoot() { state.startScan() } }
                    .keyboardShortcut("o")
                Button("Taramayı Durdur") { state.cancelScan() }
                    .keyboardShortcut(".")
            }
        }

        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarContent(state: state)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if UserDefaults.standard.bool(forKey: Prefs.lowSpaceAlerts) { SpaceMonitor.requestPermission() }
    }

    /// Menü çubuğu simgesi açıkken pencere kapansa da uygulama çalışmaya devam eder.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: Prefs.menuBarEnabled)
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $state.section) {
                Section("Asistan") {
                    ForEach([AppSection.assistant, .smart, .overview, .storage, .growth]) { s in
                        Label(s.title, systemImage: s.icon).tag(s)
                    }
                }
                Section("Araçlar") {
                    ForEach([AppSection.explorer, .largeFiles, .duplicates, .photos, .junk, .apps, .developer, .docker, .rules]
                        .filter { $0 != .docker || AppState.dockerInstalled }) { s in
                        Label(s.title, systemImage: s.icon)
                            .badge(badge(for: s))
                            .tag(s)
                    }
                }
                Section("Güvenlik") {
                    ForEach([AppSection.history, .exclusions]) { s in
                        Label(s.title, systemImage: s.icon)
                            .badge(badge(for: s))
                            .tag(s)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
            .safeAreaInset(edge: .bottom) { diskFooter }
        } detail: {
            switch state.section ?? .assistant {
            case .assistant: AssistantView()
            case .smart: SmartCleanView()
            case .overview: OverviewView()
            case .storage: StorageView()
            case .growth: GrowthView()
            case .explorer: ExplorerView()
            case .largeFiles: LargeFilesView()
            case .duplicates: DuplicatesView()
            case .photos: SimilarPhotosView()
            case .junk: JunkView()
            case .apps: AppsView()
            case .developer: DeveloperView()
            case .docker: DockerView()
            case .rules: RulesView()
            case .history: HistoryView()
            case .exclusions: ExclusionsView()
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = state.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 70)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: state.toast)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshDisk()
        }
    }

    private func badge(for section: AppSection) -> Text? {
        switch section {
        case .junk where state.junkReady:
            let total = state.junkCategories.reduce(Int64(0)) { $0 + $1.size }
            return total > 0 ? Text(total.formattedBytes) : nil
        case .duplicates where state.duplicatesReady:
            return state.duplicateGroups.isEmpty ? nil : Text("\(state.duplicateGroups.count)")
        case .rules:
            let pending = state.rules.filter { $0.pendingSize != nil }.count
            return pending > 0 ? Text("\(pending)") : nil
        case .exclusions:
            return state.excludedPaths.isEmpty ? nil : Text("\(state.excludedPaths.count)")
        default:
            return nil
        }
    }

    @ViewBuilder private var diskFooter: some View {
        if let d = state.disk {
            VStack(alignment: .leading, spacing: 6) {
                Label(d.name, systemImage: "internaldrive").font(.caption.bold())
                UsageBar(fraction: d.usedFraction, color: usageColor(d.usedFraction))
                Text("\(d.available.formattedBytes) boş · \(d.total.formattedBytes)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }
}
