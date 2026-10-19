import Foundation
import AppKit

/// A single note on disk.
///
/// Notes are written as RTF, so the styling the user applies survives a quit and opens properly
/// in anything else that reads rich text. A `.txt`/`.md` note left over from an earlier,
/// plain-text FewNote is still listed and opens as plain text; it is written back as RTF the
/// first time it is edited, which is the one moment the app can be sure of what it holds.
public struct Note: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public var title: String
    /// When the note was first written, and when it was last written to. Both come from the file
    /// itself, so they survive the app being closed and are right for notes written elsewhere.
    public var created: Date
    public var modified: Date
    /// A note that has never been typed into is a draft: it lives in the app's memory only, and
    /// becomes a file the moment something is entered. An abandoned draft leaves nothing behind —
    /// which is why the library never fills with empty notes.
    public var isDraft: Bool

    public init(id: UUID, url: URL, title: String,
                created: Date = .distantPast, modified: Date = .distantPast,
                isDraft: Bool = false) {
        self.id = id
        self.url = url
        self.title = title
        self.created = created
        self.modified = modified
        self.isDraft = isDraft
    }

    /// Whether the file on disk is rich text.
    public var isRichText: Bool { url.pathExtension.lowercased() == "rtf" }
}

/// A note that was just deleted, kept so the deletion can be undone for a moment.
public struct DeletedNote {
    public let note: Note
    /// Where it was in the list, so putting it back feels like nothing happened.
    public let index: Int
    let trashURL: URL
}

/// The app's one piece of shared state: the note library, the current note, live counts and
/// the couple of UI flags the View menu needs.
@MainActor
public final class AppModel: ObservableObject {

    public static let shared = AppModel()

    // MARK: - Published state

    @Published public private(set) var notes: [Note] = []

    @Published public var selectedNoteID: UUID? {
        didSet {
            guard oldValue != selectedNoteID else { return }
            // A draft that is being left without ever being typed into is not a note: it is
            // dropped from the library, and nothing is written anywhere.
            if let old = oldValue, let index = notes.firstIndex(where: { $0.id == old }),
               notes[index].isDraft {
                notes.remove(at: index)
            }
            // Opening a note closes whatever folder was open: the two are one view of the same
            // library, and a note is what you came to read.
            if selectedNoteID != nil { browsingFolder = nil }
            // Leaving a note: make sure nothing pending is lost before the editor reloads.
            flushPendingSave()
            persistState()
        }
    }

    /// The folder whose contents are on screen, when the reader is looking at a folder rather than
    /// writing in a note. "" is the notes directory — the top level — and nil means a note is open,
    /// which is where the app always starts.
    @Published public var browsingFolder: String?

    /// Shows what a folder holds. The open note is left open behind the list, so going back to it
    /// costs nothing — and choosing a folder is where the next file or folder goes.
    public func browse(_ path: String) {
        folderChoice = path.isEmpty ? .all : .folder(path)
        browsingFolder = path
        // Browsing a folder is not opening a note: the note stays open behind the list, and the
        // sidebar's selection clears so the folder reads as the thing that is open.
        selectedNoteID = nil
    }

    @Published public private(set) var characterCount = 0
    @Published public private(set) var wordCount = 0

    @Published public var showsSidebar = false {
        didSet {
            // Asking for the note list while in full view is asking to leave it.
            if showsSidebar, isFullView { isFullView = false }
        }
    }

    /// Full view: the note and nothing else. The list and the bar get out of the way, and the
    /// list's own setting is kept so leaving full view puts it back exactly as it was.
    @Published public var isFullView = false

    private var sidebarBeforeFullView = false

    public func toggleFullView() {
        if isFullView {
            isFullView = false
            showsSidebar = sidebarBeforeFullView
        } else {
            sidebarBeforeFullView = showsSidebar
            isFullView = true
            showsSidebar = false
        }
    }

    /// The folders notes can be filed in, and which of them the list is showing.
    @Published public private(set) var folders: [NoteFolder] = []
    @Published public var folderChoice: FolderChoice = .all {
        didSet {
            guard oldValue != folderChoice else { return }
            persistState()
        }
    }

    /// The colour a folder's or a note's name is written in, by folder path and by note identity.
    ///
    /// A name has no entry until it is given one. The colours live here rather than in the files,
    /// so a note stays a plain note and a folder stays a plain folder — drop one into the Finder
    /// and it is exactly what FewNote wrote, with nothing of the interface inside it.
    @Published public private(set) var folderColours: [String: String] = [:]
    @Published public private(set) var noteColours: [String: String] = [:]

    public func labelColour(forFolder path: String) -> LabelColour? {
        folderColours[path].flatMap(LabelColour.init(rawValue:))
    }

    public func labelColour(forNote id: UUID) -> LabelColour? {
        noteColours[id.uuidString].flatMap(LabelColour.init(rawValue:))
    }

    /// Sets a name's colour — or clears it, with nil, which puts it back to the ordinary label.
    public func setLabelColour(_ colour: LabelColour?, forFolder path: String) {
        folderColours[path] = colour?.rawValue
        persistState()
    }

    public func setLabelColour(_ colour: LabelColour?, forNote id: UUID) {
        noteColours[id.uuidString] = colour?.rawValue
        persistState()
    }

    /// Carries a folder's colour — and its children's — across a rename or a move, both of which
    /// change the paths the colours are filed under.
    private func remapFolderColours(from old: String, to new: String) {
        var remapped: [String: String] = [:]
        for (path, colour) in folderColours {
            guard path == old || path.hasPrefix(old + "/") else {
                remapped[path] = colour
                continue
            }
            remapped[new + path.dropFirst(old.count)] = colour
        }
        folderColours = remapped
    }

    /// What is being searched for, and what has been found.
    ///
    /// Setting the query — by typing in the field, or by the Search Notes command — is what starts
    /// the search, so there is no way to change it without the list following; the hits appear a
    /// moment later, when the notes have been read.
    @Published public var searchQuery = "" {
        didSet {
            guard oldValue != searchQuery else { return }
            runSearch()
        }
    }
    @Published public private(set) var searchHits: [SearchHit] = []
    /// Set by the Search Notes command so the field can take the keyboard.
    @Published public var wantsSearchFocus = false
    /// Set by the Your Name… command so its alert can come up over the editor.
    @Published public var wantsNameEditor = false
    /// Set when the language has been changed, so the alert can offer the restart that applies it.
    @Published public var wantsRelaunch = false

    /// Bumped when the open note has been changed from the outside — by a rename in the list, say
    /// — so the editor knows to read the note off disk again rather than keep what it has.
    @Published public var reloadToken = UUID()

    /// The last deletion, and the words to describe it in the undo banner.
    @Published public private(set) var lastDeleted: DeletedNote?

    /// The undo manager a deletion is registered with — the window's own, handed over by the
    /// interface, so ⌘Z takes a deleted note back in its turn with the typing.
    public var undoManager: UndoManager?

    // MARK: - Storage

    public let directory: URL

    private var pendingNoteID: UUID?
    /// What is waiting to be written.
    ///
    /// The editor hands over its own text storage — the note as it is being typed — rather than a
    /// copy of it, so a keystroke costs nothing but a schedule: the copy is taken once, when the
    /// debounce fires. Callers that have only a finished string (the checks, and anything that is
    /// not the editor) are held as they are.
    private var liveStorage: NSTextStorage?
    private var pendingNote: NSAttributedString?
    private var saveWorkItem: DispatchWorkItem?
    private var searchTask: Task<Void, Never>?

    /// Delay between the last keystroke and writing to disk. Small enough to feel instant,
    /// long enough to avoid touching the disk on every character.
    private let saveDebounce: TimeInterval = 0.4

    public var selectedNote: Note? {
        guard let id = selectedNoteID else { return nil }
        return notes.first { $0.id == id }
    }

    // MARK: - Folders and search

    /// The notes the list is showing: the chosen folder's, or every note's. Drafts wait until
    /// they are written before they are listed, so a list never shows an empty note.
    public var listedNotes: [Note] {
        notes.filter { !$0.isDraft } .filter { note in
            guard case .folder(let path) = folderChoice else { return true }
            return folderPath(of: note) == path
        }
    }

    /// Whether the sidebar is showing what a search found rather than the library.
    public var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Where a note is filed, relative to the notes directory. "" is the notes directory itself.
    public func folderPath(of note: Note) -> String {
        let parent = note.url.deletingLastPathComponent().standardizedFileURL.pathComponents
        let root = directory.standardizedFileURL.pathComponents
        guard parent.count >= root.count, Array(parent.prefix(root.count)) == root else { return "" }
        return parent.dropFirst(root.count).joined(separator: "/")
    }

    /// The notes filed directly in a folder, newest first, which is what the folder's own list
    /// shows. The count the sidebar shows is this, counted. Drafts are not on disk yet, so they
    /// are not here.
    public func notes(inFolder path: String) -> [Note] {
        notes.filter { !$0.isDraft && folderPath(of: $0) == path }
    }

    /// How many notes are filed directly in a folder — the count the sidebar shows.
    public func noteCount(in path: String) -> Int {
        notes.reduce(0) { $0 + (!$1.isDraft && folderPath(of: $1) == path ? 1 : 0) }
    }

    /// The note being edited, with any styling it carries, including keystrokes the debounce has
    /// not flushed to disk yet. Read from the editor's live storage, so the answer is always what
    /// is on the screen.
    public var currentAttributed: NSAttributedString {
        if let liveStorage, pendingNoteID == selectedNoteID {
            return NSAttributedString(attributedString: liveStorage)
        }
        if let pendingNote, pendingNoteID == selectedNoteID { return pendingNote }
        guard let note = selectedNote else { return NSAttributedString(string: "") }
        return loadAttributed(for: note)
    }

    /// The note's text without its styling. What counts, titles and a replay care about.
    public var currentText: String {
        if let liveStorage, pendingNoteID == selectedNoteID { return liveStorage.string }
        if let pendingNote, pendingNoteID == selectedNoteID { return pendingNote.string }
        return selectedNote.map { loadAttributed(for: $0).string } ?? ""
    }

    /// Whether a new note can be started: the current one has to have something in it first, so
    /// an empty note is never quietly abandoned to become a second empty note.
    public var canCreateNote: Bool { !currentText.isEmpty }

    /// Whether the one-time tidy of a pre-draft library has run. It is only ever written true.
    private var tidiedEmptyNotes = true

    // MARK: - Lifecycle

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultNotesDirectory()
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)

        purgeOldTrash()
        let stored = loadPersistedState()
        let lastNoteID = stored?.lastNoteID
        folderColours = stored?.folderColours ?? [:]
        noteColours = stored?.noteColours ?? [:]
        // A restored folder path is only used when there is a real folder to restore: an empty path
        // means the notes directory itself, which is no longer one of the rows, so the list opens on
        // the whole notebook instead of on a folder that cannot be seen.
        if let path = stored?.folderPath, !path.isEmpty {
            folderChoice = .folder(path)
        }
        notes = Self.scanNotes(in: self.directory)

        // One-time tidy: a library from before notes were drafts can hold empty ones, gathered a
        // note at a launch at a time. They are trash, not destroyed, and it runs exactly once.
        if stored?.tidiedEmptyNotes != true {
            let empties = notes.filter {
                Self.readTitle(from: $0.url) == NoteText.untitled
                    && loadAttributed(for: $0).string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            for note in empties { _ = try? trash(note.url) }
            if !empties.isEmpty { notes = Self.scanNotes(in: self.directory) }
            tidiedEmptyNotes = true
            persistState()
        }

        // Restore the previous note, fall back to the newest one.
        if let lastNoteID, notes.contains(where: { $0.id == lastNoteID }) {
            selectedNoteID = lastNoteID
        } else {
            selectedNoteID = notes.first?.id
        }
        if notes.isEmpty { createNote() }
        refreshFolders()
        refreshCounts()
    }

    // MARK: - Note management

    /// Where a note goes: the folder named, else the folder that is open, else the notes
    /// directory itself — which is the root of the tree, and where a note with no folder lives.
    private func folderURL(for path: String?) -> URL {
        let wanted = path ?? folderChoice.path ?? ""
        guard !wanted.isEmpty else { return directory }
        let url = directory.appending(path: wanted, directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: url.path) ? url : directory
    }

    /// Makes a note, in the folder named, or in the one that is open. A named note is what a
    /// folder's own "New File" is, so a note can be started anywhere the tree can show one.
    public func createNote(in folder: String? = nil) {
        flushPendingSave()

        // A new note is a draft, not a file: nothing is written until something is entered, so an
        // "New File" pressed twice, or an app opened and quit, never leaves an empty note behind.
        // The url it would take is decided now, so the draft already knows where it belongs.
        let id = UUID()
        let url = folderURL(for: folder).appending(path: "Note-\(id.uuidString).rtf")

        // A note made here and now knows when it was made. It is the same answer the next scan
        // would read from the file, without waiting for one.
        let now = Date()
        notes.insert(Note(id: id, url: url, title: NoteText.untitled, created: now, modified: now,
                          isDraft: true), at: 0)
        selectedNoteID = id
        applyCounts(from: "")
        persistState()
    }

    /// Deletes a note by moving it into the notes directory's `.trash`, so it is recoverable both
    /// by Undo and, failing that, by hand.
    public func deleteNote(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if pendingNoteID == id { discardPendingSave() }

        let note = notes[index]
        // A draft has no file to trash: it was never written.
        var trashURL = note.url
        if !note.isDraft, let trashed = try? trash(note.url) { trashURL = trashed }

        notes.remove(at: index)
        // The note's colour goes with it: a file that is gone has no name to colour.
        noteColours[id.uuidString] = nil
        lastDeleted = DeletedNote(note: note, index: min(index, notes.count), trashURL: trashURL)

        if selectedNoteID == id {
            selectedNoteID = notes.first?.id
        }
        if notes.isEmpty { createNote() }
        if let manager = targetUndoManager {
            // The window's own stack, which is where the typing's undo goes too, so ⌘Z takes back
            // whichever came last and the Edit menu names it.
            manager.beginUndoGrouping()
            manager.registerUndo(withTarget: self) { model in model.undoDelete() }
            manager.setActionName("Delete Note")
            manager.endUndoGrouping()
        }
        refreshFolders()
        persistState()
        refreshCounts()
    }

    /// The stack a deletion registers on.
    ///
    /// ⌘Z asks the key window's undo manager, so that is the one a delete has to join for Undo to
    /// take it back — and joining it is also what makes the Edit menu say "Undo Delete Note". The
    /// manager SwiftUI hands the views is the fallback, which is what is available when there is
    /// no window at all (in the checks, say).
    var targetUndoManager: UndoManager? {
        guard NSApp != nil else { return undoManager }
        return NSApp.keyWindow?.undoManager ?? NSApp.mainWindow?.undoManager ?? undoManager
    }

    /// Puts back the note that was deleted last, so what that was deleted survives.
    public func undoDelete() {
        guard let deleted = lastDeleted else { return }
        lastDeleted = nil

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A draft comes back without a file: there never was one, and it will be written the
        // same moment it is typed into again.
        if FileManager.default.fileExists(atPath: deleted.trashURL.path) {
            try? FileManager.default.moveItem(at: deleted.trashURL, to: deleted.note.url)
        }

        let index = min(max(deleted.index, 0), notes.count)
        notes.insert(deleted.note, at: index)
        selectedNoteID = deleted.note.id
        refreshFolders()
        persistState()
        refreshCounts()
    }

    /// Renames a note by rewriting the line its title comes from.
    ///
    /// A note's name in the list is its first line, so renaming means editing the note — the rest
    /// of it, styling and all, is left exactly as it was. The open note is reloaded so the change
    /// shows in the editor too.
    @discardableResult
    public func renameNote(_ id: UUID, to title: String) -> Bool {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = notes.firstIndex(where: { $0.id == id }) else { return false }
        guard notes[index].title != clean else { return true }

        // Whatever has been typed but not written belongs in the file before the title is replaced.
        flushPendingSave()

        let attributed = NSMutableAttributedString(attributedString: loadAttributed(for: notes[index]))
        let text = attributed.string as NSString
        let lineBreak = text.range(of: "\n")
        let lineRange = lineBreak.location == NSNotFound
            ? NSRange(location: 0, length: attributed.length)
            : NSRange(location: 0, length: lineBreak.location)
        // The new title keeps the first line's own styling, so a renamed note still looks a note.
        let attributes = attributed.length > 0
            ? attributed.attributes(at: 0, effectiveRange: nil)
            : NoteDocument.canvasAttributes()
        attributed.replaceCharacters(in: lineRange,
                                     with: NSAttributedString(string: clean, attributes: attributes))

        // Written through the same path as an edit, so a plain-text note is upgraded on the way.
        pendingNoteID = id
        liveStorage = nil
        pendingNote = attributed
        writePendingNote()

        if let written = notes.firstIndex(where: { $0.id == id }) { notes[written].title = clean }
        refreshCounts()
        persistState()
        if selectedNoteID == id { reloadToken = UUID() }
        return true
    }

    // MARK: - Folders

    /// Makes a folder and opens it. Returns its path, or nil if the name came to nothing.
    ///
    /// A name that is already taken gets a number, rather than a folder quietly not appearing.
    @discardableResult
    public func createFolder(named name: String, in parent: String = "") -> String? {
        let clean = Self.folderName(name)
        guard !clean.isEmpty else { return nil }

        let parentURL = parent.isEmpty
            ? directory
            : directory.appending(path: parent, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: parentURL.path) else { return nil }

        var unique = clean
        var counter = 2
        while FileManager.default.fileExists(atPath: parentURL.appending(path: unique).path) {
            unique = "\(clean) \(counter)"
            counter += 1
        }

        let url = parentURL.appending(path: unique, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            return nil
        }
        refreshFolders()
        let path = parent.isEmpty ? unique : "\(parent)/\(unique)"
        persistState()
        return path
    }

    /// Renames a folder. The notes inside keep their names, so they keep their identities too.
    @discardableResult
    public func renameFolder(_ id: String, to name: String) -> Bool {
        guard !id.isEmpty, let folder = folders.first(where: { $0.id == id }) else { return false }
        let clean = Self.folderName(name)
        guard !clean.isEmpty, clean != folder.name else { return false }

        flushPendingSave()
        let destination = folder.url.deletingLastPathComponent().appending(path: clean, directoryHint: .isDirectory)
        guard !FileManager.default.fileExists(atPath: destination.path),
              (try? FileManager.default.moveItem(at: folder.url, to: destination)) != nil else { return false }

        // The folder's notes have moved with it, so everything is read again; identities come from
        // file names, so the open note stays open.
        let parent = id.split(separator: "/").dropLast().joined(separator: "/")
        if case .folder(let path) = folderChoice, path == id {
            folderChoice = .folder(clean)
        }
        // Whatever is on screen is where the folder was: if the folder being renamed is the one
        // being looked at, the look at it follows the new name, or the grid goes to a path that
        // does not exist.
        if let host = browsingFolder, host == id || host.hasPrefix(id + "/") {
            let tail = host.dropFirst(id.count)
            browsingFolder = parent.isEmpty ? clean + tail : parent + "/" + clean + tail
        }
        // The folder keeps its name's colour: only the path it is filed under has changed.
        remapFolderColours(from: id, to: parent.isEmpty ? clean : parent + "/" + clean)
        rescan()
        return true
    }

    /// Deletes a folder by putting the whole thing in the trash, notes and all — recoverable by
    /// hand for a week, which is the same bargain a deleted note gets.
    public func deleteFolder(_ id: String) {
        guard !id.isEmpty, let folder = folders.first(where: { $0.id == id }) else { return }
        flushPendingSave()
        _ = try? trash(folder.url)
        if let path = folderChoice.path, path == id || path.hasPrefix(id + "/") {
            folderChoice = .all
        }
        if let path = browsingFolder, path == id || path.hasPrefix(id + "/") {
            browsingFolder = ""
        }
        // A name that is gone has no colour to remember: the folder and everything inside it takes
        // its colour with it, and a new folder made with the same name starts ordinary.
        for path in Array(folderColours.keys) where path == id || path.hasPrefix(id + "/") {
            folderColours[path] = nil
        }
        rescan()
    }

    /// Nests a folder inside another — or moves it back to the top level, with an empty parent.
    ///
    /// A folder cannot be moved into itself or into one of its own children, which would take it
    /// out of the tree altogether; that is the only rule, and it is the one the filesystem insists
    /// on anyway.
    @discardableResult
    public func moveFolder(_ id: String, into parent: String) -> Bool {
        guard !id.isEmpty, let folder = folders.first(where: { $0.id == id }) else { return false }
        guard parent != id, !parent.hasPrefix(id + "/") else { return false }
        guard id != "" else { return false }
        flushPendingSave()

        let parentURL = parent.isEmpty
            ? directory
            : directory.appending(path: parent, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: parentURL.path) else { return false }

        let destination = parentURL.appending(path: folder.name, directoryHint: .isDirectory)
        guard destination.standardizedFileURL != folder.url.standardizedFileURL else { return false }
        guard !FileManager.default.fileExists(atPath: destination.path) else { return false }
        guard (try? FileManager.default.moveItem(at: folder.url, to: destination)) != nil else { return false }

        // Whatever the list was showing has moved with it.
        if case .folder(let path) = folderChoice,
           path == id || path.hasPrefix(id + "/") {
            let tail = path.dropFirst(id.count)
            let newID = parent.isEmpty ? String(folder.name) + tail : parent + "/" + folder.name + tail
            folderChoice = .folder(newID)
        }
        remapFolderColours(from: id, to: parent.isEmpty ? String(folder.name) : parent + "/" + folder.name)
        rescan()
        return true
    }

    /// Files a note into a folder — or back into the notes directory, with an empty path.
    @discardableResult
    public func moveNote(_ id: UUID, toFolder path: String) -> Bool {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return false }
        // Whatever has been typed but not written belongs in the file before it moves.
        flushPendingSave()

        let note = notes[index]
        guard folderPath(of: note) != path else { return false }

        let folderURL = path.isEmpty ? directory : directory.appending(path: path, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: folderURL.path) else { return false }
        let destination = folderURL.appending(path: note.url.lastPathComponent)
        guard (try? FileManager.default.moveItem(at: note.url, to: destination)) != nil else { return false }

        let moved = Note(id: note.id, url: destination, title: note.title,
                         created: note.created, modified: note.modified)
        notes[index] = moved
        registerMoveUndo(of: note)
        refreshFolders()
        persistState()
        return true
    }

    /// Files any of these notes into a folder. What a drop onto a folder row does.
    @discardableResult
    public func moveNotes(_ ids: [UUID], toFolder path: String) -> Bool {
        var moved = false
        for id in ids where moveNote(id, toFolder: path) { moved = true }
        return moved
    }

    /// Puts a moved note back where it was, so dragging one to the wrong folder is a ⌘Z away.
    private func registerMoveUndo(of note: Note) {
        guard let manager = targetUndoManager else { return }
        let origin = folderPath(of: note)
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: self) { model in
            model.moveNote(note.id, toFolder: origin)
        }
        manager.setActionName("Move Note")
        manager.endUndoGrouping()
    }

    /// Re-reads the notes and folders from disk.
    public func rescan() {
        notes = Self.scanNotes(in: directory)
        refreshFolders()
        if let id = selectedNoteID, !notes.contains(where: { $0.id == id }) {
            selectedNoteID = notes.first?.id
        }
        if notes.isEmpty { createNote() }
        refreshCounts()
        persistState()
    }

    /// Counts what is in each folder, so the sidebar can show it.
    func refreshFolders() {
        folders = Self.scanFolders(in: directory).map { url in
            let path = folderPath(for: url)
            return NoteFolder(
                id: path,
                name: url.lastPathComponent,
                url: url,
                count: notes.filter { !$0.isDraft && folderPath(of: $0) == path }.count,
                depth: max(0, path.split(separator: "/").count - 1)
            )
        }
        // A colour belongs to a name that still exists. Whether the deletion was app-made or
        // made by hand in the Finder, what is gone takes its colour with it — so a folder made
        // later with the same name starts ordinary.
        let livePaths = Set(folders.map(\.id))
        let liveNoteIDs = Set(notes.map { $0.id.uuidString })
        let keptFolders = folderColours.filter { livePaths.contains($0.key) }
        let keptNotes = noteColours.filter { liveNoteIDs.contains($0.key) }
        if keptFolders.count != folderColours.count {
            folderColours = keptFolders
            persistState()
        }
        if keptNotes.count != noteColours.count {
            noteColours = keptNotes
            persistState()
        }
    }

    /// A directory's path relative to the notes directory.
    private func folderPath(for url: URL) -> String {
        let parts = url.standardizedFileURL.pathComponents
        let root = directory.standardizedFileURL.pathComponents
        guard parts.count > root.count, Array(parts.prefix(root.count)) == root else { return "" }
        return parts.dropFirst(root.count).joined(separator: "/")
    }

    /// A folder name that is safe to make a directory from.
    static func folderName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Search

    /// Searches every note, by title and by what is written in it.
    public func search(_ query: String) {
        searchQuery = query
    }

    /// Clears the search, putting the library back the way it was.
    public func clearSearch() {
        searchQuery = ""
    }

    /// Does the searching: titles at once, because they are already in memory, then the note files
    /// a moment later, off the main thread — so a search never stutters the typing it runs beside.
    private func runSearch() {
        searchTask?.cancel()

        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchHits = []
            return
        }

        let library = notes
        searchHits = library
            .filter { $0.title.range(of: trimmed, options: Search.options) != nil }
            .map { SearchHit(note: $0, snippet: nil) }

        searchTask = Task { [weak self] in
            // A moment's pause so typing the query does not read every note once per letter.
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) {
                Search.hits(in: library, query: trimmed)
            }.value
            guard !Task.isCancelled, self?.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
            self?.searchHits = found
        }
    }

    /// Moves a file into the notes directory's trash. The trash is a directory, so scanning for
    /// notes (which looks at files) never sees what is in it.
    private func trash(_ url: URL) throws -> URL {
        let folder = directory.appendingPathComponent(Self.trashFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var target = folder.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
        }
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    /// Clears out anything that has been in the trash for a week, so it cannot grow without end.
    private func purgeOldTrash() {
        let folder = directory.appendingPathComponent(Self.trashFolderName, isDirectory: true)
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [URLResourceKey.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in contents {
            let modified = (try? url.resourceValues(forKeys: [URLResourceKey.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if modified < cutoff { try? FileManager.default.removeItem(at: url) }
        }
    }

    static let trashFolderName = ".trash"

    // MARK: - Loading and saving

    /// Reads a note, translating whatever is on disk into the matrix's own attributes.
    public func loadAttributed(for note: Note) -> NSAttributedString {
        guard let data = try? Data(contentsOf: note.url) else { return NoteDocument.empty() }
        return NoteDocument.attributed(fromFileExtension: note.url.pathExtension, data: data)
    }

    // MARK: - Editing callbacks

    /// Called on every keystroke and on every style change. Cheap: updates counts and titles and
    /// schedules a debounced write.
    public func textEdited(_ storage: NSTextStorage) {
        guard let noteID = selectedNoteID else { return }
        pendingNoteID = noteID
        liveStorage = storage
        pendingNote = nil
        edited(storage.string, noteID: noteID)
    }

    public func textEdited(_ attributed: NSAttributedString) {
        guard let noteID = selectedNoteID else { return }
        // A finished string is kept as it is: there is nothing live to read it from later.
        pendingNoteID = noteID
        liveStorage = nil
        pendingNote = NSAttributedString(attributedString: attributed)
        edited(attributed.string, noteID: noteID)
    }

    /// The shared tail of both entry points: the title, the counts, and the write that follows.
    private func edited(_ text: String, noteID: UUID) {
        let newTitle = NoteText.displayTitle(text)
        if let index = notes.firstIndex(where: { $0.id == noteID }), notes[index].title != newTitle {
            notes[index].title = newTitle
        }
        applyCounts(from: text)
        scheduleSave()
    }

    /// Convenience for callers that only have the text (the checks, and a replay).
    public func textEdited(_ text: String) {
        textEdited(NSAttributedString(string: text))
    }

    public func applyCounts(from text: String) {
        characterCount = NoteText.characterCount(text)
        wordCount = NoteText.wordCount(text)
    }

    private func refreshCounts() {
        applyCounts(from: currentText)
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.writePendingNote()
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounce, execute: work)
    }

    /// Writes any pending note immediately and persists the last-note pointer. Called on note
    /// switch, when closing a window, and on terminate.
    public func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        writePendingNote()
        persistState()
    }

    /// Identical to `saveNow` but tolerant of being called during teardown.
    func flushPendingSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        writePendingNote()
    }

    private func discardPendingSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        clearPending()
    }

    private func clearPending() {
        pendingNote = nil
        liveStorage = nil
        pendingNoteID = nil
    }

    /// What is waiting to be written, as a note. The one copy a save costs.
    private func pendingAttributed() -> NSAttributedString? {
        if let liveStorage { return NSAttributedString(attributedString: liveStorage) }
        return pendingNote
    }

    private func writePendingNote() {
        guard let noteID = pendingNoteID,
              let attributed = pendingAttributed(),
              let index = notes.firstIndex(where: { $0.id == noteID }) else {
            clearPending()
            return
        }
        clearPending()

        // A draft that is still empty is not a note yet: nothing is entered, nothing is written.
        // The one that has words in it becomes a file here, which is the moment it stops being a
        // draft.
        if notes[index].isDraft {
            guard !attributed.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            notes[index].isDraft = false
            refreshFolders()
        }

        guard let data = NoteDocument.rtfData(for: attributed) else { return }

        // A note inherited from the plain-text era becomes rich text the first time it is saved.
        var note = notes[index]
        if !note.isRichText, let upgraded = upgradedURL(for: note) {
            try? data.write(to: upgraded, options: .atomic)
            try? FileManager.default.removeItem(at: note.url)
            // The new file's creation date is now; the note's own is the one it came with.
            note = Note(id: note.id, url: upgraded, title: note.title,
                        created: note.created, modified: Date())
            notes[index] = note
        } else {
            try? data.write(to: note.url, options: .atomic)
            note.modified = Date()
            notes[index] = note
        }
    }

    /// The `.rtf` file a plain-text note becomes, under the same name so its identity — which is
    /// read back out of the file name — does not change.
    private func upgradedURL(for note: Note) -> URL? {
        let stem = note.url.deletingPathExtension().lastPathComponent
        // Beside the note it replaces, which for a filed note means inside its folder.
        return note.url.deletingLastPathComponent().appending(path: "\(stem).rtf")
    }

    // MARK: - Persisted state (last note)

    struct StateFile: Codable {
        var lastNoteID: UUID?
        /// The folder that was open, so the app comes back to it.
        var folderPath: String?
        /// The colours names have been given, kept with the rest of the state. Both are optional,
        /// so a state file written before colours existed still reads.
        var folderColours: [String: String]?
        var noteColours: [String: String]?
        /// Marks the one-time tidy-up that trashed the empty notes a library gathered before
        /// notes became drafts. A state file without it is one that has not been tidied yet.
        var tidiedEmptyNotes: Bool?
    }

    private var stateURL: URL { directory.appending(path: "state.json") }

    private func loadPersistedState() -> StateFile? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(StateFile.self, from: data)
    }

    private func persistState() {
        let state = StateFile(lastNoteID: selectedNoteID,
                              folderPath: folderChoice.path,
                              folderColours: folderColours.isEmpty ? nil : folderColours,
                              noteColours: noteColours.isEmpty ? nil : noteColours,
                              tidiedEmptyNotes: tidiedEmptyNotes)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    // MARK: - Directory scanning

    /// File types FewNote treats as notes: what it writes now, and what it used to write.
    static let noteExtensions: Set<String> = ["rtf", "txt", "md"]

    static func defaultNotesDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("FewNote/notes", isDirectory: true)
    }

    /// Lists note files newest-first. `.rtf` is what FewNote writes; `.txt` and `.md` are accepted
    /// so notes written by earlier versions keep working and stay editable.
    ///
    /// The search runs through the folder tree, so a note put inside a folder — by the app, or by
    /// hand in the Finder — is always found. Hidden directories, the trash among them, are skipped.
    static func scanNotes(in directory: URL) -> [Note] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey, .isRegularFileKey]

        let dated: [(url: URL, created: Date, modified: Date)] = files(in: directory).compactMap { url in
            guard Self.noteExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile != false else { return nil }
            let modified = values?.contentModificationDate ?? .distantPast
            return (url, values?.creationDate ?? modified, modified)
        }

        return dated
            .sorted { $0.modified > $1.modified }
            .map { entry in
                Note(
                    id: Self.identifier(from: entry.url),
                    url: entry.url,
                    title: Self.readTitle(from: entry.url),
                    created: entry.created,
                    modified: entry.modified
                )
            }
    }

    /// Every directory below the notes directory, which is what a folder is.
    static func scanFolders(in directory: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let walk = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var folders: [URL] = []
        for case let url as URL in walk {
            if (try? url.resourceValues(forKeys: Set(keys)))?.isDirectory == true {
                folders.append(url)
            }
        }
        return folders.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Every file below the notes directory, at any depth.
    static func files(in directory: URL) -> [URL] {
        guard let walk = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in walk where !url.hasDirectoryPath {
            files.append(url)
        }
        return files
    }

    /// Recovers the stable note identity from the file name. Files we create are named
    /// "Note-<uuid>.rtf"; anything else is treated as an external file with a fresh identity.
    private static func identifier(from url: URL) -> UUID {
        let stem = url.deletingPathExtension().lastPathComponent
        if stem.hasPrefix("Note-"), let uuid = UUID(uuidString: String(stem.dropFirst("Note-".count))) {
            return uuid
        }
        return UUID(uuidString: stem) ?? UUID()
    }

    private static func readTitle(from url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return NoteText.untitled }
        let text = NoteDocument.attributed(fromFileExtension: url.pathExtension, data: data).string
        return NoteText.displayTitle(text)
    }
}
