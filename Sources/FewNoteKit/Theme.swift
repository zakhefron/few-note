import AppKit

/// The three appearance choices shown in the status bar and View menu.
public enum Theme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }

    public var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

public enum ThemePreference {
    /// Shared `UserDefaults`/`@AppStorage` key. Kept in one place so the app and views agree.
    public static let key = "FewNoteTheme"
}

/// Applies a stored theme to the whole app without restarting.
/// Switching `NSApp.appearance` is instant and leaves SwiftUI's colour scheme to re-resolve.
public enum ThemeApplier {
    @MainActor
    public static func apply(rawValue: String) {
        let theme = Theme(rawValue: rawValue) ?? .system
        switch theme {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
