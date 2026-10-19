import Foundation

/// What the app calls the person writing.
///
/// It is a name and nothing else: no account, no sign-in, no store — the one reason FewNote has to
/// know it is so the greeting on the way in can be a greeting rather than a label. A pet name is
/// as good a name as any, which is why the field is not called anything grander.
public enum UserNamePreference {
    /// Shared `UserDefaults`/`@AppStorage` key.
    public static let key = "FewNoteUserName"

    /// The name, trimmed. Empty when the user has not given one.
    public static func stored(in defaults: UserDefaults = .standard) -> String {
        (defaults.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The greeting for the way in: a name if there is one, and the plain welcome if not.
    ///
    /// The words and the name are kept as two strings rather than one with a hole in it, so a
    /// translator gets a word to translate instead of a format string to be careful with.
    public static func greeting(for name: String) -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return String(localized: "Welcome to FewNote") }
        return String(localized: "Hello,") + " " + clean
    }
}
