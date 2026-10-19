import SwiftUI
import AppKit

/// The sidebar: a quiet rail of pages.
///
/// The rules that give it its feel. Nothing shouts — a row is an icon, a name, and the colour a
/// label was given, actions belong to the hover, not the row — a "+" and a "⋯" appear while the
/// pointer is there and vanish when it moves on. And the tree is not a hierarchy of views: it is
/// one flat list of rows, computed from the model and the set of folded folders, drawn by a
/// single `ForEach` — the way an outliner works, and the reason it cannot misrender.
struct SidebarView: View {

    @ObservedObject var model: AppModel

    /// The folders folded away. A folder with nothing under it never enters this set.
    @State private var folded: Set<String> = []
    /// The folder whose name is being typed over, and the text in the field.
    @State private var renamingFolder: String?
    @State private var renameText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchRow
            Divider()

            tree
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.wantsSearchFocus) { wanted in
            guard wanted else { return }
            model.wantsSearchFocus = false
            isSearchFocused = true
        }
        .onChange(of: model.browsingFolder) { path in
            // Reaching a folder from anywhere else (a menu, a drag) reveals it: its ancestors
            // unfold so the place that is open is visibly where it is.
            guard var ancestor = path else { return }
            while !ancestor.isEmpty {
                folded.remove(ancestor)
                ancestor = parent(of: ancestor)
            }
        }
        .onChange(of: model.selectedNoteID) { id in
            // A draft has no file yet, so it is in the tree by favour alone: unfold its folder's
            // chain so the grey row is visibly where the new page went.
            guard let id, let note = model.notes.first(where: { $0.id == id }), note.isDraft else { return }
            var ancestor = model.folderPath(of: note)
            while !ancestor.isEmpty {
                folded.remove(ancestor)
                ancestor = parent(of: ancestor)
            }
        }
    }

    // MARK: - Search

    private var searchRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search", text: $model.searchQuery)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($isSearchFocused)
                .onSubmit { isSearchFocused = false }
            if model.isSearching {
                Button { model.clearSearch() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    // MARK: - The tree: one flat list of rows

    private var tree: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if model.isSearching {
                    // Searching, the rail is a results list, flat: the tree waits until the
                    // field is cleared.
                    searchResults
                } else {
                    // The rail opens with the workspace: every note that is in nothing else,
                    // and every folder, nested under it.
                    rootRow

                    ForEach(rows) { entry in
                    switch entry {
                    case .folder(let display):
                        FolderRow(
                            model: model,
                            display: display,
                            editing: renamingFolder == display.path,
                            editText: renameText,
                            isSelected: model.browsingFolder == display.path,
                            toggle: {
                                if folded.contains(display.path) { folded.remove(display.path) }
                                else { folded.insert(display.path) }
                            },
                            open: { model.browse(display.path) },
                            beginRename: {
                                renamingFolder = display.path
                                renameText = display.name
                            },
                            commitRename: { name in
                                model.renameFolder(display.path, to: name)
                                renamingFolder = nil
                            },
                            cancelRename: { renamingFolder = nil },
                            addFile: { model.createNote(in: display.path) },
                            addFolder: { addFolder(inside: display.path) }
                        )
                    case .note(let note, let depth):
                        RailNoteRow(
                            model: model,
                            note: note,
                            depth: depth
                        )
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
        }
        .onTapGesture { commitRenameOutside() }
        .dropDestination(for: NoteTransfer.self) { items, _ in
            model.moveNotes(items.map(\.id), toFolder: "")
        }
        .dropDestination(for: FolderTransfer.self) { items, _ in
            items.contains { model.moveFolder($0.id, into: "") }
        }
        // ⌫ or ⌦ on the rail: the selected note, or the folder being looked at, is deleted —
        // the way a Finder selection is. The rename field owns the key while it is typing.
        .background {
            Group {
                Button { deleteSelection() } label: { EmptyView() }
                    .keyboardShortcut(.delete, modifiers: [])
                Button { deleteSelection() } label: { EmptyView() }
                    .keyboardShortcut(KeyEquivalent("\u{7F}"), modifiers: [])
            }
            .opacity(0)
        }
    }

    /// The search's answer on the rail: every note that matches, flat, with the line it matched
    /// shown under the name - or an honest nothing, if nothing does.
    private var searchResults: some View {
        Group {
            if model.searchHits.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                    Text("No matches")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
            } else {
                ForEach(model.searchHits) { hit in
                    RailNoteRow(model: model, note: hit.note, depth: 0, snippet: hit.snippet)
                }
            }
        }
    }

    /// A click where nothing is named: a rename going on ends there, the field committing as
    /// its focus goes - which is how typing a folder into being ends by clicking away.
    private func commitRenameOutside() {
        guard renamingFolder != nil else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    /// What the delete key means right now: the folder being looked at, or the note selected.
    /// A rename in progress takes the key back, and the rail deletes nothing.
    private func deleteSelection() {
        guard renamingFolder == nil, !isSearchFocused else { return }
        if let folder = model.browsingFolder, !folder.isEmpty {
            model.deleteFolder(folder)
        } else if let id = model.selectedNoteID {
            model.deleteNote(id)
        }
    }

    /// The workspace row: the rail's root, the way Notion's teamspaces sit at the top.
    private var rootRow: some View {
        PageRow(
            title: "Notes",
            depth: 0,
            isWorkspace: true,
            chevron: treeHasContent,
            expanded: !folded.contains(""),
            editing: renamingFolder == "",
            editText: renameText,
            isSelected: model.browsingFolder == "",
            labelColour: nil,
            showsPlus: true,
            toggle: {
                if folded.contains("") { folded.remove("") } else { folded.insert("") }
            },
            open: { model.browse("") },
            beginRename: {},
            commitRename: { _ in renamingFolder = nil },
            cancelRename: { renamingFolder = nil },
            addFile: { model.createNote(in: "") },
            addFolder: { addFolder(inside: "") },
            menu: {
                Button { model.createNote(in: "") } label: {
                    Label("New File", systemImage: "doc.badge.plus")
                }
                Button { addFolder(inside: "") } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
        )
    }

    // MARK: - The tree, as data

    /// Every row the tree shows, in order: depth-first subfolders, then their notes.
    private var rows: [TreeEntry] {
        var rows: [TreeEntry] = []
        appendChildren(of: "", depth: 0, into: &rows)
        return rows
    }

    /// The children of a folder that is expanded, appended after their parent's mention. A folded
    /// folder shows nothing under it: the fold is not a hidden province, it is the tree.
    private func appendChildren(of path: String, depth: Int, into rows: inout [TreeEntry]) {
        guard !folded.contains(path) else { return }
        let (folders, notes) = children(of: path)
        for folder in folders {
            rows.append(.folder(display(path: folder.id, name: folder.name, depth: depth)))
            appendChildren(of: folder.id, depth: depth + 1, into: &rows)
        }
        for note in notes {
            rows.append(.note(note, depth: depth))
        }
    }

    /// A row's description: what it shows, and how deep it sits.
    private func display(path: String, name: String, depth: Int) -> FolderDisplay {
        FolderDisplay(
            path: path,
            name: name,
            depth: depth,
            expanded: !folded.contains(path),
            hasChildren: hasChildren(path)
        )
    }

    /// A folder's children: its subfolders and its own notes, each alphabetically, which is how a
    /// page list reads. The draft being written is here too, at the foot of its folder's rows —
    /// a new page is on the rail the moment it is made, greyed until it is written.
    private func children(of path: String) -> (folders: [NoteFolder], notes: [Note]) {
        let folders = model.folders
            .filter { parent(of: $0.id) == path }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var notes = model.notes(inFolder: path)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let drafts = model.notes
            .filter { $0.isDraft && model.folderPath(of: $0) == path }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        notes.append(contentsOf: drafts)
        return (folders, notes)
    }

    private func hasChildren(_ path: String) -> Bool {
        let (folders, notes) = children(of: path)
        return !folders.isEmpty || !notes.isEmpty
    }

    private var treeHasContent: Bool {
        let (folders, notes) = children(of: "")
        return !folders.isEmpty || !notes.isEmpty
    }

    /// The folder a path sits in: "A/B" is filed under "A".
    private func parent(of path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }

    // MARK: - Helpers

    /// Makes a folder in place: expanded so it is visible, then straight into renaming it.
    private func addFolder(inside parent: String) {
        guard let path = model.createFolder(named: String(localized: "New Folder"), in: parent) else { return }
        var ancestor = path
        while !ancestor.isEmpty {
            folded.remove(ancestor)
            ancestor = self.parent(of: ancestor)
        }
        folded.remove(parent)
        renamingFolder = path
        renameText = String(localized: "New Folder")
    }
}

// MARK: - Row data

/// One row of the tree: a folder, or a note. Identifiable by kind and place, so a note keeps its
/// identity across re-sorts and a folder across renames.
private enum TreeEntry: Identifiable {
    case folder(FolderDisplay)
    case note(Note, depth: Int)

    var id: String {
        switch self {
        case .folder(let folder): return "F:" + folder.path
        case .note(let note, _): return "N:" + note.id.uuidString
        }
    }
}

/// What a folder row needs to know to draw itself.
private struct FolderDisplay {
    let path: String
    let name: String
    let depth: Int
    let expanded: Bool
    let hasChildren: Bool
}

// MARK: - Row parts

/// A page on the rail: its chevron, its kind's icon, its name, and the actions that live in the
/// hover.
///
/// Both the folder row and the note row are this view — a folder row carries the folder's icon, a
/// "+" and a page-plus; a note row carries the file's icon and no actions. Everything else (the
/// name, the hover fill, the "⋯", the drag, the menu) is shared, which is what keeps the rail
/// reading as one object.
private struct PageRow<PageMenu: View>: View {

    let title: String
    let depth: Int
    /// The workspace row is the rail's root: slightly heavier, and never renamed.
    var isWorkspace = false
    /// The row's kind, drawn where the eye starts: a folder, or a file.
    var icon: String? = nil
    /// Whether a chevron is drawn, and which way it points.
    var chevron: Bool = false
    var expanded: Bool = false
    let editing: Bool
    let editText: String
    var isSelected: Bool = false
    var labelColour: LabelColour?
    /// A draft page: greyed where a written page would take its colour, until it is typed into.
    var isPlaceholder = false
    var showsPlus: Bool = false
    /// Folders take their new name over their name with a double click, the way the folder view's
    /// heading does.
    var allowsDoubleClickRename = false
    /// What a search result matched: a second line under the name, so a hit reads before it opens.
    var snippet: String? = nil
    /// A drop hovering on the row, being filed into. Stronger than a hover, because it says
    /// something is about to happen.
    var isDropTargeted = false
    let toggle: () -> Void
    let open: () -> Void
    let beginRename: () -> Void
    let commitRename: (String) -> Void
    let cancelRename: () -> Void
    var addFile: (() -> Void)? = nil
    var addFolder: (() -> Void)? = nil
    @ViewBuilder var menu: () -> PageMenu

    @State private var isHovering = false
    /// The three dots are a Menu, not a Button, and a Menu swallows the hover its label would
    /// carry - so the row watches for the pointer and styles the label from here.
    @State private var isDotsHovering = false
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
            if chevron {
                Button(action: toggle) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 14, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(editing)
            } else {
                Color.clear.frame(width: 14, height: 20)
            }

            if editing {
                HStack(spacing: 0) {
                    RenameField(text: editText, commit: commitRename, cancel: cancelRename)
                        .foregroundStyle(labelColour?.colour ?? Color.primary)
                    Spacer(minLength: 4)
                }
            } else {
                Button(action: open) {
                    HStack(spacing: 5) {
                        if let icon {
                            Image(systemName: icon)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(labelColour?.colour
                                                 ?? (isPlaceholder ? Color.secondary : Color.primary.opacity(0.55)))
                        }
                        Text(title)
                            .font(isWorkspace ? .callout.weight(.semibold) : .callout)
                            .italic(isPlaceholder)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(labelColour?.colour
                                             ?? (isPlaceholder ? Color.secondary : Color.primary))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    if allowsDoubleClickRename { beginRename() }
                })

                HStack(spacing: 2) {
                    if showsPlus, let addFile {
                        RailButton(systemImage: "plus", action: addFile)
                    }

                    if showsPlus, let addFolder {
                        RailButton(systemImage: "folder.badge.plus", action: addFolder)
                    }

                    // The dots are split in two: an invisible Menu underneath takes the clicks
                    // and opens the menu, and the visible symbol above it is plain SwiftUI, so
                    // the hover highlight can never be swallowed by the menu's own AppKit
                    // button. The hover itself is an AppKit tracking area behind the pair - it
                    // fires wherever the cursor is over its rect, whatever sits above it.
                    ZStack {
                        Menu {
                            menu()
                        } label: {
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(width: 18, height: 18)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()

                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isDotsHovering ? Color.primary : Color.primary.opacity(0.45))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.primary.opacity(isDotsHovering ? 0.12 : 0)))
                            .allowsHitTesting(false)
                    }
                    .background(HoverWatcher { isDotsHovering = $0 })
                }
                .foregroundStyle(Color.primary.opacity(0.45))
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering && !isTargeted)
            }
            }

            // A search result shows the line it matched, so the hit reads before it opens.
            if let snippet, !editing {
                Text(snippet)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, 26)
            }
        }
        .padding(.leading, CGFloat(depth) * 14 + 4)
        .padding(.trailing, 4)
        .frame(height: snippet == nil ? 26 : 40, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.14)
                      : isTargeted ? Color.primary.opacity(0.12)
                      : isSelected ? Color.primary.opacity(0.09)
                      : isHovering ? Color.primary.opacity(0.05)
                      : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(isDropTargeted ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu { menu() }
        .accessibilityLabel(title)
    }
}

/// One of the small actions that live in a row's hover: a symbol that lights a circle when the
/// pointer is on it, so the hand can see which one it is on.
/// Watches the pointer over one control, the way AppKit does it: a tracking area.
///
/// SwiftUI's own hover never reaches into a `Menu`'s label - the menu's AppKit button takes the
/// events and hands nothing down. A tracking area is geometric rather than hit-tested, so it
/// fires wherever the cursor is over its rect, whether or not a control above it takes the
/// clicks. It sits behind the control it watches.
struct HoverWatcher: NSViewRepresentable {

    var onHover: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onHover = onHover
    }

    @MainActor
    final class TrackingView: NSView {
        var onHover: ((Bool) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas where area.owner === self {
                removeTrackingArea(area)
            }
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil))
        }

        override func mouseEntered(with event: NSEvent) {
            onHover?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHover?(false)
        }
    }
}

struct RailButton: View {
    let systemImage: String
    var edge: CGFloat = 18
    var help: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovering ? Color.primary : Color.primary.opacity(0.45))
                .frame(width: edge, height: edge)
                .background(Circle().fill(Color.primary.opacity(isHovering ? 0.12 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(help ?? systemImage)
    }
}

/// The rail's root row: the workspace itself, with both a "+" and its menu.

/// A folder on the rail: a page that other pages sit inside, so it drags, and takes drops.
private struct FolderRow: View {

    @ObservedObject var model: AppModel
    let display: FolderDisplay
    let editing: Bool
    let editText: String
    let isSelected: Bool
    let toggle: () -> Void
    let open: () -> Void
    let beginRename: () -> Void
    let commitRename: (String) -> Void
    let cancelRename: () -> Void
    let addFile: () -> Void
    let addFolder: () -> Void

    /// A drop hovering on the folder, from either payload - a note or another folder.
    @State private var isDropTargeted = false

    var body: some View {
        PageRow(
            title: display.name,
            depth: display.depth + 1,
            icon: "folder",
            chevron: display.hasChildren,
            expanded: display.expanded,
            editing: editing,
            editText: editText,
            isSelected: isSelected,
            labelColour: model.labelColour(forFolder: display.path),
            showsPlus: true,
            allowsDoubleClickRename: true,
            isDropTargeted: isDropTargeted,
            toggle: toggle,
            open: open,
            beginRename: beginRename,
            commitRename: commitRename,
            cancelRename: cancelRename,
            addFile: addFile,
            addFolder: addFolder,
            menu: { menuContent }
        )
        .modifier(FolderDrag(folder: model.folders.first { $0.id == display.path }))
        .dropDestination(for: NoteTransfer.self) { items, _ in
            model.moveNotes(items.map(\.id), toFolder: display.path)
        } isTargeted: { isDropTargeted = $0 }
        .dropDestination(for: FolderTransfer.self) { items, _ in
            items.contains { model.moveFolder($0.id, into: display.path) }
        } isTargeted: { isDropTargeted = $0 }
    }

    @ViewBuilder
    private var menuContent: some View {
        Button { addFile() } label: {
            Label("New File", systemImage: "doc.badge.plus")
        }
        Button { addFolder() } label: {
            Label("New Folder", systemImage: "folder.badge.plus")
        }
        Button {
            beginRename()
        } label: {
            Label("Rename…", systemImage: "pencil")
        }
        Divider()
        LabelColourMenu(current: model.labelColour(forFolder: display.path)) { colour in
            model.setLabelColour(colour, forFolder: display.path)
        }
        Divider()
        Button(role: .destructive) { model.deleteFolder(display.path) } label: {
            Label("Delete Folder", systemImage: "trash")
        }
    }
}

/// A note on the rail: a leaf page. It drags; it does not take drops. A note is its writing —
/// its name is the first line of it — so there is no renaming it from outside.
private struct RailNoteRow: View {

    @ObservedObject var model: AppModel
    let note: Note
    let depth: Int
    /// What a search hit matched, shown under the name.
    var snippet: String? = nil

    var body: some View {
        PageRow(
            title: note.title,
            depth: depth + 1,
            icon: "doc",
            editing: false,
            editText: "",
            isSelected: model.selectedNoteID == note.id && model.browsingFolder == nil,
            labelColour: note.isDraft ? nil : model.labelColour(forNote: note.id),
            isPlaceholder: note.isDraft,
            snippet: snippet,
            toggle: {},
            open: { model.selectedNoteID = note.id },
            beginRename: {},
            commitRename: { _ in },
            cancelRename: {},
            menu: { menuContent }
        )
        .modifier(NoteDrag(note: note))
    }

    @ViewBuilder
    private var menuContent: some View {
        LabelColourMenu(current: model.labelColour(forNote: note.id)) { colour in
            model.setLabelColour(colour, forNote: note.id)
        }
        Divider()
        Button(role: .destructive) { model.deleteNote(note.id) } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Rename field

/// A name being typed over, in place of the name it replaces.
struct RenameField: View {
    let commit: (String) -> Void
    let cancel: () -> Void
    /// The rail renames at the row's own size; a heading renames at the heading's.
    var font: Font = .callout
    @State private var draft: String
    @State private var hasFinished = false
    @FocusState private var isFocused: Bool

    init(text: String, commit: @escaping (String) -> Void, cancel: @escaping () -> Void,
         font: Font = .callout) {
        _draft = State(initialValue: text)
        self.commit = commit
        self.cancel = cancel
        self.font = font
    }

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .font(font)
            .focused($isFocused)
            .onSubmit { finish(commit: true) }
            .onExitCommand { finish(commit: false) }
            .onChange(of: isFocused) { focused in
                if !focused { finish(commit: true) }
            }
            .onAppear { isFocused = true }
    }

    private func finish(commit shouldCommit: Bool) {
        guard !hasFinished else { return }
        hasFinished = true
        if shouldCommit { commit(draft) } else { cancel() }
    }
}

// MARK: - Folder drag

// MARK: - Page drags

/// A note's drag. A draft cannot be dragged: there is no file for the drop to move yet.
private struct NoteDrag: ViewModifier {
    let note: Note
    func body(content: Content) -> some View {
        if note.isDraft {
            content
        } else {
            content.draggable(NoteTransfer(id: note.id)) {
                Label(note.title, systemImage: "note.text")
                    .font(.caption)
                    .padding(4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

private struct FolderDrag: ViewModifier {
    let folder: NoteFolder?
    @ViewBuilder
    func body(content: Content) -> some View {
        if let folder {
            content.draggable(FolderTransfer(id: folder.id)) {
                Label(folder.name, systemImage: "folder")
                    .font(.caption)
                    .padding(4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
        } else {
            content
        }
    }
}
