import AppKit
import Foundation

/// The interface language chosen in Settings.
///
/// English is the default and the source language of the string catalog. The choice is applied by setting the
/// app's own `AppleLanguages` preference before any UI is created, so every string (SwiftUI, menus, alerts,
/// formatters) follows it. Changing it takes effect after a relaunch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case turkish = "tr"
    case system

    static let preferenceKey = "appLanguage"
    static let fallback: AppLanguage = .english

    var id: String { rawValue }

    /// Language names are shown in their own language so they can be found in any interface language.
    var title: String {
        switch self {
        case .english: "English"
        case .turkish: "Türkçe"
        case .system: L("System Default")
        }
    }

    /// The saved choice. `CLEANMAC_LANGUAGE` (en, tr, system) overrides it, e.g. for screenshots.
    static var current: AppLanguage {
        if let forced = ProcessInfo.processInfo.environment["CLEANMAC_LANGUAGE"], let language = AppLanguage(rawValue: forced) {
            return language
        }
        return UserDefaults.standard.string(forKey: preferenceKey).flatMap(AppLanguage.init(rawValue:)) ?? fallback
    }

    /// The language the running app was started with.
    static let active: AppLanguage = current

    /// Must run before the first localized string is looked up.
    static func applyAtLaunch() {
        switch current {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case let language:
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    static func save(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: preferenceKey)
    }

    /// Starts a new instance of the app and quits this one.
    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
