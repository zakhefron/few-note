import SwiftUI
import AppKit

/// The writing surface: a glyph matrix wrapped for SwiftUI.
///
/// A note is written into a fixed grid of cells — one glyph per cell — rather than onto a
/// word-processing page. The grid, the cell size, the styles and the caret all come from
/// `GlyphMatrix`, which the replay uses too, so watching a note being typed looks exactly like
/// typing it.
///
/// AppKit is used underneath (rather than SwiftUI's `TextEditor`) because it gives native
/// undo/redo, selection, find bar, spell checking and copy/paste for free, while letting us push
/// text changes straight into `AppModel` without round-tripping the whole SwiftUI view tree.
struct SourceEditor: NSViewRepresentable {

    @ObservedObject var model: AppModel
    /// Cleared while a replay is covering the editor, so keystrokes cannot land in a note the
    /// user is not actually looking at.
    var isEditable: Bool = true
    /// The colour the note is written in, chosen from the status bar.
    var tint: GlyphTint = .chalk
    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // The width here is only a starting point; the first layout pass replaces it with the
        // real one.
        let textView = GlyphMatrixTextView(width: 720, isEditable: isEditable)
        textView.tint = tint
        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        let scrollView = GlyphMatrixScrollView.wrapping(textView)
        context.coordinator.load(note: model.selectedNote, into: textView, model: model)
        focus(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? GlyphMatrixTextView else { return }

        textView.fit(width: scrollView.contentSize.width, height: scrollView.contentSize.height)
        textView.tint = tint

        // Reload only when the selected note actually changed — or when the open note has been
        // changed from the outside, such as by a rename in the list — so typing is never
        // interrupted for nothing.
        if let note = model.selectedNote,
           context.coordinator.loadedNoteID != note.id || context.coordinator.loadedToken != model.reloadToken {
            context.coordinator.load(note: note, into: textView, model: model)
            focus(textView)
        }

        // Going from read-only back to editable (e.g. when a replay ends) needs focus handed
        // back so the user can carry on typing without clicking.
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
            if isEditable { focus(textView) }
        }
    }

    private func focus(_ textView: NSTextView) {
        // Deferred so the view is in a window before we make it first responder.
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let model: AppModel
        private(set) var loadedNoteID: UUID?
        /// The reload token the note was loaded under, so an outside change to the same note is
        /// noticed as readily as a switch to another one.
        private(set) var loadedToken = UUID()
        weak var textView: GlyphMatrixTextView?

        init(model: AppModel) {
            self.model = model
        }

        func load(note: Note?, into textView: NSTextView, model: AppModel) {
            loadedToken = model.reloadToken
            guard let note, let matrix = textView as? GlyphMatrixTextView else {
                textView.string = ""
                loadedNoteID = nil
                model.applyCounts(from: "")
                return
            }
            let attributed = model.loadAttributed(for: note)
            matrix.setNote(attributed)
            matrix.setSelectedRange(NSRange(location: 0, length: 0))
            loadedNoteID = note.id
            model.applyCounts(from: attributed.string)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // Hand over the live storage, not a copy of it: the model takes its one copy when it
            // writes the note, so a keystroke in a long note costs no more than one in a short one.
            if let storage = textView.textStorage {
                model.textEdited(storage)
            } else {
                model.textEdited(textView.string)
            }
            // Keep the matrix tall enough to hold the row being typed on.
            if let matrix = self.textView, let scrollView = matrix.enclosingScrollView {
                matrix.fit(width: scrollView.contentSize.width, height: scrollView.contentSize.height)
            }
        }
    }
}
