import SwiftUI
import AppKit

/// The contents of a folder, shown in the writing area when one is opened.
///
/// What a folder holds is laid out the way Apple Notes shows it: its subfolders first, then its
/// notes, each as a card — kind, name, a preview of the writing, and when it was last touched.
/// The folder's own name is a heading, and it is a piece of text like any other: double-click it
/// and type the new name over it. A note card opens the note; the hovers carry the small edits,
/// the right-click menus carry the rest.
struct FolderContentsView: View {

    @EnvironmentObject private var model: AppModel

    let path: String

    /// The folder's name being typed over, and what is in the field.
    @State private var renamingFolder = false
    @State private var folderRenameText = ""
    /// What this folder is being narrowed down to. Empty is everything.
    @State private var query = ""

    private var isRoot: Bool { path.isEmpty }

    private var title: String {
        isRoot ? String(localized: "Notes") : path.split(separator: "/").last.map(String.init) ?? path
    }

    private var notes: [Note] { model.notes(inFolder: path) }

    /// The folders this one holds, by name, the same order the rail reads.
    private var subfolders: [NoteFolder] {
        model.folders
            .filter { folder in
                let components = folder.id.split(separator: "/")
                guard components.count >= 1 else { return false }
                return components.dropLast().joined(separator: "/") == path
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var shownSubfolders: [NoteFolder] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return subfolders }
        return subfolders.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    /// Notes that match: by name first, and past that by what is written in them - the same
    /// reading the rail's search gives, narrowed to this folder's own files.
    private var shownNotes: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return notes }
        let titleHits = notes.filter { $0.title.localizedCaseInsensitiveContains(q) }
        let rest = notes.filter { !titleHits.contains($0) }
        return titleHits + Search.hits(in: rest, query: q).map(\.note)
    }

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if notes.isEmpty && subfolders.isEmpty {
                emptyState
            } else if shownNotes.isEmpty && shownSubfolders.isEmpty {
                noMatches
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(shownSubfolders) { folder in
                            FolderCard(
                                folder: folder,
                                open: { model.browse(folder.id) },
                                commitRename: { name in model.renameFolder(folder.id, to: name) },
                                deleteFolder: { model.deleteFolder(folder.id) }
                            )
                        }
                        ForEach(shownNotes) { note in
                            NoteCard(
                                note: note,
                                open: { model.selectedNoteID = note.id }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        // A click where nothing is named: a rename going on ends there, the field committing
        // as its focus goes - the same way the rail's renames end.
        .onTapGesture { commitRenameOutside() }
        .onChange(of: path) { _ in renamingFolder = false; query = "" }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No Notes")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Drop a note here, or start a new one.")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    /// Nothing here matches what the field holds - the folder is fine, the search is the thing
    /// that found nothing.
    private var noMatches: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No matches")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func commitRenameOutside() {
        guard renamingFolder else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    // MARK: - The heading

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            if renamingFolder {
                RenameField(
                    text: folderRenameText,
                    commit: { name in
                        if !isRoot { model.renameFolder(path, to: name) }
                        renamingFolder = false
                    },
                    cancel: { renamingFolder = false },
                    font: .title2.weight(.semibold)
                )
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
            } else {
                titleBlock
            }

            Spacer(minLength: 12)

            searchField

            if !subfolders.isEmpty {
                Text(Counts.folders(subfolders.count))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text(Counts.notes(notes.count))
                .font(.callout)
                .foregroundStyle(.secondary)

            // The two ways this folder can grow, where the eye already is. A new note lands
            // beside the open one; a new folder joins the rail under the same roof.
            headerButton("doc.badge.plus", help: "New File") {
                model.createNote(in: path)
            }
            headerButton("folder.badge.plus", help: "New Folder") {
                addFolderHere()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .contextMenu {
            Button { beginRename() } label: {
                Label("Rename…", systemImage: "pencil")
            }
            .disabled(isRoot)
            Divider()
            Button { model.createNote(in: path) } label: {
                Label("New File", systemImage: "doc.badge.plus")
            }
            Button { addFolderHere() } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            Divider()
            if !isRoot {
                LabelColourMenu(current: model.labelColour(forFolder: path)) { colour in
                    model.setLabelColour(colour, forFolder: path)
                }
                Divider()
                Button(role: .destructive) { model.deleteFolder(path) } label: {
                    Label("Delete Folder", systemImage: "trash")
                }
            }
        }
    }

    /// The folder's own search, as small as the rail's: a leaf beside the counts.
    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
                .frame(width: 120)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .help("Search this folder")
    }

    /// Where you are: the folder's name, a piece of text like any other — double-click it and
    /// type the new name over it.
    @ViewBuilder
    private var titleBlock: some View {
        Text(title)
            .font(.title2.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .onTapGesture(count: 2) { beginRename() }
    }

    private func beginRename() {
        guard !isRoot else { return }
        folderRenameText = title
        renamingFolder = true
    }

    /// A folder made where you are: it joins the rail under the same roof.
    private func addFolderHere() {
        _ = model.createFolder(named: String(localized: "New Folder"), in: path)
    }

    /// A small, quiet icon button that lights a circle under the pointer - the same species the
    /// rail's row buttons are in, at the header's size.
    private func headerButton(_ systemImage: String, help: String, action: @escaping () -> Void)
        -> some View {
        RailButton(systemImage: systemImage, edge: 24, help: help, action: action)
    }
}

/// A folder as a card, at the front of the grid: the folder's mark, its name in the colour it was
/// given, and how much it holds. Opening it is a click; the hover and the right-click menu carry
/// name, contents, and colour. A note or a folder dropped on it files itself there.
private struct FolderCard: View {
    let folder: NoteFolder
    let open: () -> Void
    let commitRename: (String) -> Void
    let deleteFolder: () -> Void

    @EnvironmentObject private var model: AppModel
    @State private var isHovering = false
    @State private var editingName = false
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if editingName {
                RenameField(
                    text: folder.name,
                    commit: { name in
                        commitRename(name)
                        editingName = false
                    },
                    cancel: { editingName = false },
                    font: .headline
                )
                .padding(10)
                .frame(minHeight: 96, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                )
            } else {
                card
            }
        }
        .onHover { isHovering = editingName ? false : $0 }
        .modifier(CardFolderDrag(active: !editingName, id: folder.id, name: folder.name))
        .dropDestination(for: NoteTransfer.self) { items, _ in
            model.moveNotes(items.map(\.id), toFolder: folder.id)
        } isTargeted: { isDropTargeted = $0 }
        .dropDestination(for: FolderTransfer.self) { items, _ in
            items.contains { model.moveFolder($0.id, into: folder.id) }
        } isTargeted: { isDropTargeted = $0 }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isDropTargeted ? Color.accentColor.opacity(0.7) : .clear,
                              lineWidth: 2)
                .padding(-2)
        )
        .contextMenu {
            Button { editingName = true } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Button { model.createNote(in: folder.id) } label: {
                Label("New File", systemImage: "doc.badge.plus")
            }
            Button {
                _ = model.createFolder(named: String(localized: "New Folder"), in: folder.id)
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            Divider()
            LabelColourMenu(current: model.labelColour(forFolder: folder.id)) { colour in
                model.setLabelColour(colour, forFolder: folder.id)
            }
            Divider()
            Button(role: .destructive) { deleteFolder() } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
        .accessibilityLabel(folder.name)
    }

    /// Typing the folder's new name over the card: the field takes the card's place whole.
    private var card: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(model.labelColour(forFolder: folder.id)?.colour
                                     ?? Color(nsColor: .systemBlue).opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(folder.name)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundStyle(model.labelColour(forFolder: folder.id)?.colour ?? .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(Counts.items(model.noteCount(in: folder.id)
                                  + model.folders.filter {
                                      $0.id.split(separator: "/").dropLast()
                                          .joined(separator: "/") == folder.id
                                  }.count))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(minHeight: 96, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.07)
                          : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovering ? 0.16 : 0.08), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    HStack(spacing: 4) {
                        Button { editingName = true } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                                .background(Color(nsColor: .controlBackgroundColor), in: Circle())
                                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Rename…")

                        Button { deleteFolder() } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                                .background(Color(nsColor: .controlBackgroundColor), in: Circle())
                                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(6)
                    .transition(.opacity)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// A note as a card: title, a preview of the writing, and when it was last touched. Hovering
/// brings the trash; the right-click menu gives colour and delete. A note is its writing — its
/// name is the first line of it — so a card is not renamed from outside.
private struct NoteCard: View {
    let note: Note
    let open: () -> Void

    @EnvironmentObject private var model: AppModel
    @State private var isHovering = false

    private var preview: String {
        let text = modelText(for: note)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        // Skip the title line (first line) for the preview body.
        let body = lines.dropFirst().joined(separator: " ")
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return String(trimmed.prefix(120))
    }

    private var modifiedText: String {
        note.modified.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(model.labelColour(forNote: note.id)?.colour ?? .secondary)

                    Text(note.title)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundStyle(model.labelColour(forNote: note.id)?.colour ?? .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !preview.isEmpty {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)

                Text(modifiedText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(minHeight: 100, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.06)
                          : model.labelColour(forNote: note.id)?.colour.opacity(0.07)
                          ?? Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        model.labelColour(forNote: note.id)?.colour.opacity(0.35)
                            ?? Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    Button { model.deleteNote(note.id) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color(nsColor: .controlBackgroundColor), in: Circle())
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .transition(.opacity)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .draggable(NoteTransfer(id: note.id)) {
            Label(note.title, systemImage: "note.text")
                .font(.caption)
                .padding(4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .contextMenu {
            LabelColourMenu(current: model.labelColour(forNote: note.id)) { colour in
                model.setLabelColour(colour, forNote: note.id)
            }
            Divider()
            Button(role: .destructive) { model.deleteNote(note.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel(note.title)
    }

    /// Reads the note's text for the preview. Falls back to the title when the file cannot be read.
    private func modelText(for note: Note) -> String {
        guard let data = try? Data(contentsOf: note.url) else { return note.title }
        let attributed = NoteDocument.attributed(fromFileExtension: note.url.pathExtension, data: data)
        return attributed.string
    }
}

/// The card's drag. A card that is being renamed cannot be drug: the field is in the way of the
/// pointer that a drag begins with.
private struct CardFolderDrag: ViewModifier {
    let active: Bool
    let id: String
    let name: String
    func body(content: Content) -> some View {
        if active {
            content.draggable(FolderTransfer(id: id)) {
                Label(name, systemImage: "folder")
                    .font(.caption)
                    .padding(4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
        } else {
            content
        }
    }
}
