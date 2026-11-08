import SwiftUI
import UserNotifications

/// Ayar anahtarları ve varsayılanları.
enum Prefs {
    static let menuBarEnabled = "menuBarEnabled"
    static let lowSpaceAlerts = "lowSpaceAlerts"
    static let lowSpaceThreshold = "lowSpaceThreshold"   // yüzde
    static let lastLowSpaceAlert = "lastLowSpaceAlert"
    static let showSplash = "showSplash"

    static func register() {
        UserDefaults.standard.register(defaults: [menuBarEnabled: true, lowSpaceAlerts: true, lowSpaceThreshold: 10, showSplash: true])
    }
}

/// Boş alanı periyodik olarak izler; eşiğin altına düşünce günde en fazla bir kez bildirim gönderir.
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
        content.title = "Disk alanı azaldı"
        content.body = "Yalnızca \(disk.available.formattedBytes) (\(disk.freeFraction.formatted(.percent.precision(.fractionLength(0))))) boş alan kaldı. Temizlik önerileri için CleanMac'i aç."
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
                    Text(d.freeFraction.formatted(.percent.precision(.fractionLength(0))) + " boş").foregroundStyle(.secondary)
                }
                UsageBar(fraction: d.usedFraction, color: usageColor(d.usedFraction), height: 8)
                Text("\(d.available.formattedBytes) boş · \(d.total.formattedBytes)").font(.caption).foregroundStyle(.secondary)
            }
            if state.junkReady {
                let junk = state.safeJunkTotal
                if junk > 100_000_000 {
                    Button {
                        open(.junk)
                    } label: {
                        Label("\(junk.formattedBytes) güvenle temizlenebilir", systemImage: "sparkles")
                    }
                    .buttonStyle(.link)
                }
            }
            Divider()
            Button("CleanMac'i Aç") { open(.assistant) }
            Button("Tam Analizi Başlat") {
                open(.assistant)
                Task { await state.runFullAnalysis() }
            }
            .disabled(state.isAnalyzing || state.isScanning)
            Divider()
            SettingsLink { Text("Ayarlar…") }
            Button("Çıkış") { NSApp.terminate(nil) }
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

    var body: some View {
        Form {
            Section("Görünüm") {
                Toggle("Açılışta karşılama ekranını göster", isOn: $showSplash)
            }
            Section("Menü çubuğu") {
                Toggle("Menü çubuğunda boş alanı göster", isOn: $menuBarEnabled)
                Text("Açıkken pencere kapatılsa da CleanMac menü çubuğunda çalışmaya devam eder.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Uyarılar") {
                Toggle("Boş alan azalınca bildirim gönder", isOn: $lowSpaceAlerts)
                    .onChange(of: lowSpaceAlerts) { if lowSpaceAlerts { SpaceMonitor.requestPermission() } }
                Picker("Eşik", selection: $threshold) {
                    ForEach([5, 10, 15, 20, 25], id: \.self) { Text("%\($0) boş alanın altı").tag($0) }
                }
                .disabled(!lowSpaceAlerts)
                Text("Boş alan 5 dakikada bir kontrol edilir; günde en fazla bir bildirim gönderilir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Temizlik") {
                Toggle("Gereksiz dosyaları kalıcı sil (Çöp Kutusu'nu atla)", isOn: $permanentDelete)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }
}

extension Int64 {
    /// Menü çubuğu için kısa biçim, ör. "24 GB".
    var compactBytes: String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useGB, .useMB]
        f.isAdaptive = false
        return f.string(fromByteCount: self)
    }
}
