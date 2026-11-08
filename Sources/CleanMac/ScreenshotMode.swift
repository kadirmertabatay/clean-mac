import AppKit
import SwiftUI

/// Automated mode that produces the screenshots used in the documentation.
///
/// Enabled only with the `CLEANMAC_SCREENSHOTS=<folder>` environment variable; has no effect in normal use.
/// Resizes the window to a fixed size, runs the full analysis, visits each screen in turn and
/// captures it from the window itself (no screen recording permission needed). Nothing is deleted.
/// Restores the settings it changed when done. See `scripts/screenshots.sh` for usage.
@MainActor
enum ScreenshotMode {
    static let outputDirectory = ProcessInfo.processInfo.environment["CLEANMAC_SCREENSHOTS"].map { URL(fileURLWithPath: $0) }
    static var isActive: Bool { outputDirectory != nil }
    /// Performs a single scan and quits (creates a previous scan for the "What Grew?" screen).
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
        guard let window = mainWindow() else { print("screenshots: window not found"); return }
        window.setContentSize(windowSize)
        // Move the window to the center of the highest-resolution screen so the images are 2x.
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

    /// Adds the suggested rules (preview only, never auto-applied) for the Auto Cleanup screen and
    /// computes their pending sizes in the demo folder. No rule is run; the rules are restored afterwards.
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

    /// Re-activates the window if another app came to the front (an inactive window looks dimmed).
    private static func focus(_ window: NSWindow) {
        for _ in 0..<10 where !(NSApp.isActive && window.isKeyWindow) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        }
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows
            .filter { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true }
            .max { $0.frame.width < $1.frame.width }
            ?? NSApp.windows.filter(\.isVisible).max { $0.frame.width < $1.frame.width }
    }

    /// Saves the window, including the title bar, as a PNG with its real appearance (translucent sidebar, rounded corners).
    /// An app can capture its own window without screen recording permission. The API is hidden in newer SDKs, so
    /// it's looked up at runtime; if unavailable, it falls back to the window's own drawing.
    private static func capture(_ window: NSWindow, _ name: String, in dir: URL) {
        guard let image = windowServerImage(window) ?? viewImage(window) else {
            print("screenshots: couldn’t capture \(name)")
            return
        }
        let url = dir.appendingPathComponent("\(name).png")
        do {
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
            print("screenshots: \(name).png")
        } catch {
            print("screenshots: couldn’t write \(name): \(error)")
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
