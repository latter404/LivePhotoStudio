import AppKit
import Observation

enum AppAppearance: String, CaseIterable {
    case system, light, dark
    var title: String {
        switch self { case .system: return L("跟随系统"); case .light: return L("浅色"); case .dark: return L("深色") }
    }

    /// One application-wide override lets SwiftUI windows and native panels
    /// inherit together. A second presentation-level override can stay pinned
    /// when switching back to the system appearance.
    @MainActor func apply(to application: NSApplication) {
        switch self {
        case .system: application.appearance = nil
        case .light: application.appearance = NSAppearance(named: .aqua)
        case .dark: application.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum AppLanguage: String, CaseIterable {
    case system, chinese = "zh-Hans", english = "en"
    var title: String {
        switch self { case .system: return L("跟随系统"); case .chinese: return "简体中文"; case .english: return "English" }
    }
}

@MainActor @Observable final class AppPreferences {
    static let shared = AppPreferences()
    var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "ui.appearance")
            applyAppearance()
            AppMenuController.shared.refresh()
        }
    }
    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "ui.language")
            for window in NSApp.windows where window.identifier?.rawValue == "main" { window.title = L("实况工坊") }
            AppMenuController.shared.refresh()
        }
    }
    private init() {
        appearance = AppAppearance(rawValue: UserDefaults.standard.string(forKey: "ui.appearance") ?? "system") ?? .system
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "ui.language") ?? "system") ?? .system
    }
    var locale: Locale {
        // Reading language makes SwiftUI observe changes while the media model survives.
        _ = language
        return Locale(identifier: UIStrings.isEnglish ? "en" : "zh-Hans")
    }
    func applyAppearance() {
        appearance.apply(to: NSApp)
    }
}
