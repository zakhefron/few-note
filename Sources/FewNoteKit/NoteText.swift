import Foundation

/// Pure, dependency-free text helpers used for live counts and note titles.
/// Kept separate from the UI so it can be reasoned about (and checked) in isolation.
public enum NoteText {

    /// Grapheme-cluster count, so multi-scalar characters (emoji, flags, combining marks) count as one.
    public static func characterCount(_ string: String) -> Int {
        string.count
    }

    /// Whitespace separated token count. Emoji and punctuation-only tokens still count as words,
    /// which matches the behaviour people expect from a simple writing counter.
    public static func wordCount(_ string: String) -> Int {
        string.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Best-effort plain title for a note, derived from its first non-empty line. The line is
    /// shown exactly as written — FewNote is a plain-text notepad and does not interpret syntax.
    ///
    /// A note with nothing written in it has no title of its own, so it is shown under the
    /// interface's word for one — the single place in here that is localised, because it is the
    /// single place that shows something the user did not write.
    public static func displayTitle(_ raw: String) -> String {
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let title = cleanTitleLine(String(line))
            if !title.isEmpty { return title }
        }
        return untitled
    }

    /// What an empty note is called in the list.
    public static var untitled: String { String(localized: "Untitled") }

    /// Trims the line and keeps it to a sensible length, so one long line cannot dominate the
    /// sidebar or an export file name.
    private static func cleanTitleLine(_ line: String) -> String {
        let text = line.trimmingCharacters(in: .whitespaces)
        return text.count > 120 ? String(text.prefix(120)) : text
    }
}
