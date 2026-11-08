import AppKit
import SwiftUI

@main
struct CleanMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("CleanMac") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 1040, minHeight: 660)
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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $state.section) {
                Section("Asistan") {
                    ForEach([AppSection.assistant, .overview, .storage]) { s in
                        Label(s.title, systemImage: s.icon).tag(s)
                    }
                }
                Section("Araçlar") {
                    ForEach([AppSection.explorer, .largeFiles, .duplicates, .junk, .apps, .developer]) { s in
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
            case .overview: OverviewView()
            case .storage: StorageView()
            case .explorer: ExplorerView()
            case .largeFiles: LargeFilesView()
            case .duplicates: DuplicatesView()
            case .junk: JunkView()
            case .apps: AppsView()
            case .developer: DeveloperView()
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
