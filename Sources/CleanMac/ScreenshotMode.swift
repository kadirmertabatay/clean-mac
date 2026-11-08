import AppKit
import SwiftUI

/// Belgelerdeki ekran görüntülerini üreten otomatik mod.
///
/// Yalnızca `CLEANMAC_SCREENSHOTS=<klasör>` ortam değişkeniyle açılır; normal kullanımda hiçbir etkisi yoktur.
/// Pencereyi sabit bir boyuta getirir, tam analizi çalıştırır, ekranları sırayla gezer ve her birinin
/// görüntüsünü pencerenin kendi çiziminden alır (ekran kaydı izni gerekmez). Hiçbir şey silinmez.
/// Değiştirdiği ayarları bitince eski haline döndürür. Kullanım için `scripts/screenshots.sh`'a bakın.
@MainActor
enum ScreenshotMode {
    static let outputDirectory = ProcessInfo.processInfo.environment["CLEANMAC_SCREENSHOTS"].map { URL(fileURLWithPath: $0) }
    static var isActive: Bool { outputDirectory != nil }
    /// Yalnızca bir tarama yapıp çıkar ("Ne Büyüdü?" ekranı için önceki bir tarama oluşturur).
    static let warmupOnly = ProcessInfo.processInfo.environment["CLEANMAC_SCREENSHOTS_WARMUP"] != nil

    static let windowSize = CGSize(width: 1280, height: 820)
    private static let touchedDefaults = ["explorerTreemap", "smartLevel", "smartProtections", "cleanupRules"]

    static func run(state: AppState) async {
        guard let dir = outputDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let saved = touchedDefaults.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        defer {
            for (key, value) in saved { UserDefaults.standard.set(value, forKey: key) }
            NSApp.terminate(nil)
        }

        if ProcessInfo.processInfo.environment["CLEANMAC_SCREENSHOTS_APPEARANCE"] != "light" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else {
            NSApp.appearance = NSAppearance(named: .aqua)
        }
        await sleep(0.4)
        guard let window = mainWindow() else { print("screenshots: pencere bulunamadı"); return }
        window.setContentSize(windowSize)
        // Görüntüler 2x olsun diye pencereyi en yüksek çözünürlüklü ekranın ortasına taşır.
        if let screen = NSScreen.screens.max(by: { $0.backingScaleFactor < $1.backingScaleFactor }) {
            let area = screen.visibleFrame, frame = window.frame
            window.setFrameOrigin(NSPoint(x: area.midX - frame.width / 2, y: max(area.minY, area.midY - frame.height / 2)))
        } else {
            window.center()
        }

        if warmupOnly {
            await state.scan()
            return
        }

        await sleep(1.1)
        capture(window, "splash", in: dir)
        await sleep(2.6)

        UserDefaults.standard.set(false, forKey: "explorerTreemap")
        UserDefaults.standard.set(SmartLevel.balanced.rawValue, forKey: "smartLevel")
        await state.runFullAnalysis()
        await state.findSimilarPhotos()
        if let chrome = state.protectionCatalog.first(where: { $0.id == "app.com.google.chrome" }) {
            state.setProtection(chrome.id, true)
        }

        await prepareRules(state)

        let shots: [(AppSection, String, Double)] = [
            (.assistant, "assistant", 1.5),
            (.smart, "smart-cleanup", 6),
            (.overview, "overview", 1.5),
            (.storage, "storage", 2.5),
            (.growth, "growth", 1.5),
            (.explorer, "explorer", 1.5),
            (.largeFiles, "large-files", 1.5),
            (.duplicates, "duplicates", 1.5),
            (.photos, "similar-photos", 3),
            (.junk, "junk", 2),
            (.apps, "apps", 2.5),
            (.rules, "rules", 1.5),
        ]
        for (section, name, wait) in shots {
            state.section = section
            await sleep(wait)
            focus(window)
            capture(window, name, in: dir)
        }

        state.section = .explorer
        UserDefaults.standard.set(true, forKey: "explorerTreemap")
        await sleep(2)
        focus(window)
        capture(window, "treemap", in: dir)
        print("screenshots: \(dir.path)")
    }

    /// Otomatik Temizlik ekranı için önerilen kuralları (yalnızca önizlemeli, otomatik uygulamasız) ekler ve
    /// demo klasöründe bekleyen boyutlarını hesaplar. Hiçbir kural çalıştırılmaz; kurallar bitince geri yüklenir.
    private static func prepareRules(_ state: AppState) async {
        for rule in state.rules { state.deleteRule(rule.id) }
        CleanupRule.presets.prefix(3).filter { !$0.autoApply }.forEach(state.addRule)
        for rule in state.rules {
            let size = await Task.detached { RuleEngine.targets(for: rule).reduce(Int64(0)) { $0 + $1.size } }.value
            state.updateRule(rule.id) {
                $0.pendingSize = size > 0 ? size : nil
                $0.lastRun = Date().addingTimeInterval(-6 * 86_400)
            }
        }
    }

    /// Başka bir uygulama öne geçtiyse pencereyi yeniden etkin yapar (etkin olmayan pencere soluk görünür).
    private static func focus(_ window: NSWindow) {
        guard !window.isKeyWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows
            .filter { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true }
            .max { $0.frame.width < $1.frame.width }
            ?? NSApp.windows.filter(\.isVisible).max { $0.frame.width < $1.frame.width }
    }

    /// Pencereyi başlık çubuğu dahil, gerçek görünümüyle (saydam kenar çubuğu, yuvarlak köşeler) PNG olarak kaydeder.
    /// Bir uygulama kendi penceresini ekran kaydı izni olmadan yakalayabilir. API yeni SDK'larda gizlendiği için
    /// çalışma anında bulunur; bulunamazsa pencerenin kendi çizimine geri dönülür.
    private static func capture(_ window: NSWindow, _ name: String, in dir: URL) {
        guard let image = windowServerImage(window) ?? viewImage(window) else {
            print("screenshots: \(name) yakalanamadı")
            return
        }
        let url = dir.appendingPathComponent("\(name).png")
        do {
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
            print("screenshots: \(name).png")
        } catch {
            print("screenshots: \(name) yazılamadı: \(error)")
        }
    }

    private typealias WindowListCreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    private static func windowServerImage(_ window: NSWindow) -> CGImage? {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: WindowListCreateImage.self)
        let optionIncludingWindow: UInt32 = 1 << 3
        let boundsIgnoreFraming: UInt32 = 1 << 0, bestResolution: UInt32 = 1 << 3
        return create(.null, optionIncludingWindow, UInt32(window.windowNumber), boundsIgnoreFraming | bestResolution)?
            .takeRetainedValue()
    }

    private static func viewImage(_ window: NSWindow) -> CGImage? {
        guard let view = window.contentView?.superview,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }

    private static func sleep(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
