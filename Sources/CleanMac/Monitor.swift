import SwiftUI
import UserNotifications

/// Preference keys and defaults.
enum Prefs {
    static let menuBarEnabled = "menuBarEnabled"
    static let lowSpaceAlerts = "lowSpaceAlerts"
    static let lowSpaceThreshold = "lowSpaceThreshold"   // percent
    static let lastLowSpaceAlert = "lastLowSpaceAlert"
    static let showSplash = "showSplash"

    static func register() {
        UserDefaults.standard.register(defaults: [menuBarEnabled: true, lowSpaceAlerts: true, lowSpaceThreshold: 10, showSplash: true])
    }
}

/// Monitors free space periodically; sends at most one notification a day when it drops below the threshold.
@MainActor
final class SpaceMonitor {
    static let shared = SpaceMonitor()
    private var timer: Timer?

    func start(state: AppState) {
        guard timer == nil else { return }
        check(state)
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak state] _ in
            MainActor.assumeIsolated {
                guard let state else { return }
                SpaceMonitor.shared.check(state)
            }
        }
    }

    func check(_ state: AppState) {
        state.refreshDisk()
        Task { await state.checkRules() }
        let d = UserDefaults.standard
        guard d.bool(forKey: Prefs.lowSpaceAlerts), let disk = state.disk else { return }
        let threshold = Double(d.integer(forKey: Prefs.lowSpaceThreshold)) / 100
        guard Self.shouldAlert(freeFraction: disk.freeFraction, threshold: threshold,
                               lastAlert: d.object(forKey: Prefs.lastLowSpaceAlert) as? Date) else { return }
        d.set(Date(), forKey: Prefs.lastLowSpaceAlert)
        let content = UNMutableNotificationContent()
        content.title = L("Disk space is low")
        content.body = L("Only \(disk.available.formattedBytes) (\(disk.freeFraction.formatted(.percent.precision(.fractionLength(0))))) of free space left. Open CleanMac for cleanup suggestions.")
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "lowSpace", content: content, trigger: nil))
    }

    static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated static func shouldAlert(freeFraction: Double, threshold: Double, lastAlert: Date?, now: Date = Date()) -> Bool {
        guard freeFraction < threshold else { return false }
        guard let lastAlert else { return true }
        return now.timeIntervalSince(lastAlert) > 86_400
    }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        if let d = state.disk {
            Label(d.available.compactBytes, systemImage: d.usedFraction > 0.9 ? "externaldrive.badge.exclamationmark" : "internaldrive")
        } else {
            Image(systemName: "internaldrive")
        }
    }
}

struct MenuBarContent: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let d = state.disk {
                HStack {
                    Text(d.name).font(.headline)
                    Spacer()
                    Text(d.freeFraction.formatted(.percent.precision(.fractionLength(0))) + L(" free")).foregroundStyle(.secondary)
                }
                UsageBar(fraction: d.usedFraction, color: usageColor(d.usedFraction), height: 8)
                Text(L("\(d.available.formattedBytes) free · \(d.total.formattedBytes)")).font(.caption).foregroundStyle(.secondary)
            }
            if state.junkReady {
                let junk = state.safeJunkTotal
                if junk > 100_000_000 {
                    Button {
                        open(.junk)
                    } label: {
                        Label(L("\(junk.formattedBytes) safe to clean"), systemImage: "sparkles")
                    }
                    .buttonStyle(.link)
                }
            }
            Divider()
            Button(L("Open CleanMac")) { open(.assistant) }
            Button(L("Start Full Analysis")) {
                open(.assistant)
                Task { await state.runFullAnalysis() }
            }
            .disabled(state.isAnalyzing || state.isScanning)
            Divider()
            SettingsLink { Text(L("Settings…")) }
            Button(L("Quit")) { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 270)
        .onAppear { state.refreshDisk() }
    }

    private func open(_ section: AppSection) {
        state.section = section
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @AppStorage(Prefs.menuBarEnabled) private var menuBarEnabled = true
    @AppStorage(Prefs.lowSpaceAlerts) private var lowSpaceAlerts = true
    @AppStorage(Prefs.lowSpaceThreshold) private var threshold = 10
    @AppStorage("permanentDelete") private var permanentDelete = false
    @AppStorage(Prefs.showSplash) private var showSplash = true
    @State private var language = AppLanguage.current

    var body: some View {
        Form {
            Section(L("Language")) {
                Picker(L("Language"), selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: language) { AppLanguage.save(language) }
                if language != AppLanguage.active {
                    HStack {
                        Text(L("Restart CleanMac to apply the new language."))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Restart Now")) { AppLanguage.relaunch() }
                    }
                }
            }
            Section(L("Appearance")) {
                Toggle(L("Show the welcome screen at launch"), isOn: $showSplash)
            }
            Section(L("Menu bar")) {
                Toggle(L("Show free space in the menu bar"), isOn: $menuBarEnabled)
                Text(L("When on, CleanMac keeps running in the menu bar even after the window is closed."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Alerts")) {
                Toggle(L("Notify me when free space is low"), isOn: $lowSpaceAlerts)
                    .onChange(of: lowSpaceAlerts) { if lowSpaceAlerts { SpaceMonitor.requestPermission() } }
                Picker(L("Threshold"), selection: $threshold) {
                    ForEach([5, 10, 15, 20, 25], id: \.self) { Text(L("Below \($0)% free space")).tag($0) }
                }
                .disabled(!lowSpaceAlerts)
                Text(L("Free space is checked every 5 minutes; at most one notification is sent per day."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Cleanup")) {
                Toggle(L("Delete junk files permanently (skip the Trash)"), isOn: $permanentDelete)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }
}

extension Int64 {
    /// Short format for the menu bar, e.g. "24 GB".
    var compactBytes: String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useGB, .useMB]
        f.isAdaptive = false
        return f.string(fromByteCount: self)
    }
}
