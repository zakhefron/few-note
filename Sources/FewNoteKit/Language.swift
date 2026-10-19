import AppKit

/// The language the interface is written in.
///
/// This never touches the notes: what is written on the matrix stays exactly as it was typed. It
/// changes only what the app calls things — the menus, the sidebar, the controls. System follows
/// the Mac, which is what the app does by default and what most people want.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case spanish
    case french
    case german
    case portuguese
    case italian
    case dutch

    public var id: String { rawValue }

    /// The language code to hand to the system, or nil to follow the system's own choice.
    public var code: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .spanish: return "es"
        case .french: return "fr"
        case .german: return "de"
        case .portuguese: return "pt"
        case .italian: return "it"
        case .dutch: return "nl"
        }
    }

    /// A language is listed in its own language, which is the only name for it the person reading
    /// it is sure to recognise.
    public var label: String {
        switch self {
        case .system: return String(localized: "System")
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .portuguese: return "Português"
        case .italian: return "Italiano"
        case .dutch: return "Nederlands"
        }
    }

    }

public enum LanguagePreference {
    /// Shared `UserDefaults`/`@AppStorage` key.
    public static let key = "FewNoteLanguage"

    public static func stored(in defaults: UserDefaults = .standard) -> AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: key) ?? "") ?? .system
    }

    /// Hands the choice to the system before the interface is read.
    ///
    /// AppKit reads `AppleLanguages` once, when the app's bundle is loaded, so a change lands on
    /// the next launch rather than the current one — which is why the menu offers a restart.
    public static func applyStored(in defaults: UserDefaults = .standard) {
        let language = stored(in: defaults)
        guard let code = language.code else {
            // Back to the Mac's own languages: drop the app's override and the system's show through.
            defaults.removeObject(forKey: "AppleLanguages")
            return
        }
        guard defaults.stringArray(forKey: "AppleLanguages") != [code] else { return }
        defaults.set([code], forKey: "AppleLanguages")
    }

    /// Starts the app again, so the interface is read in the chosen language.
    @MainActor
    public static func relaunch() {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app" else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
