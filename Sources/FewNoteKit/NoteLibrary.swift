import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// A folder of notes.
///
/// A folder is nothing but a directory inside the notes directory, and a note is nothing but a
/// file inside it — so a folder can be made in the Finder, a note can be dragged into it, and
/// everything FewNote shows is something you could have filed yourself.
public struct NoteFolder: Identifiable, Hashable, Sendable {

    /// The folder's path relative to the notes directory. The notes directory itself is "", and
    /// that is the one folder that cannot be renamed or deleted.
    public let id: String
    /// The folder's own name, which is what the sidebar shows.
    public let name: String
    public let url: URL
    /// How many notes are filed here (not counting subfolders, which have rows of their own).
    public let count: Int
    /// How far inside the notes directory it sits, so a folder in a folder reads as nested.
    public let depth: Int

    public init(id: String, name: String, url: URL, count: Int, depth: Int) {
        self.id = id
        self.name = name
        self.url = url
        self.count = count
        self.depth = depth
    }

    /// What to call the folder in a menu, where a bare name would not say where it is: a folder
    /// inside another is shown with the way in — "Notes / Work".
    public var displayName: String {
        let parts = id.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return name }
        return parts.joined(separator: " / ")
    }
}

/// Which notes the list is showing.
public enum FolderChoice: Hashable, Sendable {
    /// Every note, wherever it is filed. What the app opens on, and what a search leaves behind.
    case all
    /// One folder, by its path relative to the notes directory; "" is the notes directory itself.
    case folder(String)

    /// The folder's path, or nil when every note is being shown.
    public var path: String? {
        switch self {
        case .all: return nil
        case .folder(let path): return path
        }
    }
}

/// A note a search found, with the words around the match so the row can show why it matched.
public struct SearchHit: Identifiable, Hashable, Sendable {
    public let note: Note
    /// The matching line, trimmed and shortened. Nil when the title is what matched — the row is
    /// already showing that.
    public let snippet: String?

    public var id: UUID { note.id }

    public init(note: Note, snippet: String?) {
        self.note = note
        self.snippet = snippet
    }
}

/// Searching the notes.
///
/// Matching is case- and accent-insensitive, so "cafe" finds "café" — which is what makes the
/// search usable in a language other than the one the app happens to be running in.
public enum Search {

    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// The line a query is found on, shortened for a row. Nil when the query is not there.
    public static func snippet(in text: String, for query: String, limit: Int = 96) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let found = text.range(of: trimmed, options: options) else { return nil }
        return snippet(in: text, around: found, limit: limit)
    }

    /// The line around a match: the whole line, trimmed, and — if the line is long — a window
    /// centred on the match, so what matched is always in the snippet.
    static func snippet(in text: String, around match: Range<String.Index>, limit: Int) -> String {
        var start = text.startIndex
        var end = text.endIndex
        if let newline = text[..<match.lowerBound].lastIndex(where: { $0.isNewline }) {
            start = text.index(after: newline)
        }
        if let newline = text[match.upperBound...].firstIndex(where: { $0.isNewline }) {
            end = newline
        }

        let line = String(text[start..<end]).trimmingCharacters(in: .whitespaces)
        guard line.count > limit else { return line }

        let offset = text.distance(from: start, to: match.lowerBound)
        let head = max(0, offset - limit / 3)
        let clipped = String(line.dropFirst(head).prefix(limit)).trimmingCharacters(in: .whitespaces)
        return (head > 0 ? "…" : "") + clipped + (head + limit < line.count ? "…" : "")
    }

    /// Every note whose title or text contains the query, newest first.
    ///
    /// Run off the main thread: it reads the note files, and nothing about searching should be
    /// able to stutter the typing it is running alongside.
    public static func hits(in notes: [Note], query: String) -> [SearchHit] {
        notes.compactMap { note in
            if note.title.range(of: query, options: options) != nil {
                let text = NoteDocument.text(at: note.url)
                return SearchHit(note: note, snippet: snippet(in: text, for: query))
            }
            let text = NoteDocument.text(at: note.url)
            guard let snippet = snippet(in: text, for: query) else { return nil }
            return SearchHit(note: note, snippet: snippet)
        }
    }
}

/// A note being dragged, as the drag carries it.
///
/// Only the identity travels: the note itself stays on disk, where it has to be anyway, and a
/// drop is a file move rather than a copy of a note into another note.
public struct NoteTransfer: Codable, Transferable, Sendable {
    public let id: UUID

    public init(id: UUID) {
        self.id = id
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .fewNote)
    }
}

extension UTType {
    /// The drag's own type. Declared in the app's Info.plist, so the system knows what a note
    /// being dragged is rather than treating it as text.
    public static let fewNote = UTType(exportedAs: "com.fewnote.note")
    /// The same, for a folder being dragged onto another folder to nest it.
    public static let fewNoteFolder = UTType(exportedAs: "com.fewnote.folder")
}

/// A folder being dragged, as the drag carries it. Like a note's, only the identity travels: the
/// drop is a directory move, not a copy.
public struct FolderTransfer: Codable, Transferable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .fewNoteFolder)
    }
}
