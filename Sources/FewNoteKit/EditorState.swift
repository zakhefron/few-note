import Foundation
import AppKit

/// What the editor is currently doing, for the status bar's styling controls.
///
/// The controls live in a different view from the surface they style, and SwiftUI cannot reach
/// into an `NSTextView`'s selection. So the surface publishes the little the controls need to
/// know — how the selection is struck, whether it is a list, and whether there is one at all —
/// and the controls act back on it through the responder chain.
@MainActor
final class EditorState: ObservableObject {

    static let shared = EditorState()

    /// How the selection (or, with nothing selected, the next typed characters) is struck.
    @Published var style: GlyphFont.Style = .regular

    /// What lines the selection carries past its strike: underline, strikethrough.
    @Published var decor: NoteStyle.Decoration = []

    /// Whether the lines the selection touches are bulleted.
    @Published var isBulleted = false

    /// Whether anything is selected. The colour swatches use this to decide whether a click
    /// colours the note or just the run of text that is selected.
    @Published var hasSelection = false

    /// Takes what the surface is doing.
    ///
    /// Each value is only assigned when it has really changed: `@Published` announces every
    /// assignment, and a keystroke would otherwise re-render the whole status bar three times
    /// over — for a style, a list and a selection that are usually exactly what they were.
    func update(style: GlyphFont.Style, decor: NoteStyle.Decoration, isBulleted: Bool,
                hasSelection: Bool) {
        if self.style != style { self.style = style }
        if self.decor != decor { self.decor = decor }
        if self.isBulleted != isBulleted { self.isBulleted = isBulleted }
        if self.hasSelection != hasSelection { self.hasSelection = hasSelection }
    }
}

/// The styling commands, as the menus reach them.
///
/// Menu items belong to the app, but the text they act on lives in the kit's matrix view, so the
/// app names the command and the kit does the sending. Everything goes through the responder
/// chain, which is what makes a menu item grey out when there is nothing to style.
public enum EditorCommands {

    @MainActor public static func toggleBold() {
        send(#selector(GlyphMatrixTextView.toggleBold(_:)))
    }

    @MainActor public static func toggleItalic() {
        send(#selector(GlyphMatrixTextView.toggleItalic(_:)))
    }

    @MainActor public static func toggleList() {
        send(#selector(GlyphMatrixTextView.toggleList(_:)))
    }

    @MainActor public static func toggleUnderline() {
        send(#selector(GlyphMatrixTextView.toggleUnderline(_:)))
    }

    @MainActor public static func toggleStrikethrough() {
        send(#selector(GlyphMatrixTextView.toggleStrikethrough(_:)))
    }

    /// Gives the selected text a colour of its own.
    @MainActor public static func colourSelection(_ tint: GlyphTint) {
        send(#selector(GlyphMatrixTextView.applyTint(_:)), from: GlyphMatrixTextView.TintAction(tint))
    }

    /// Puts the selected text back into the note's own colour.
    @MainActor public static func clearSelectionColour() {
        send(#selector(GlyphMatrixTextView.clearTint(_:)))
    }

    /// Saves the open note as a picture of itself.
    ///
    /// The note is written to disk first, so the picture is of a note that is actually saved, and
    /// then drawn from what the editor is showing — so anything typed in the last moment is in it.
    @MainActor public static func saveImage() {
        let model = AppModel.shared
        model.saveNow()
        guard let note = model.selectedNote else { return }
        NoteImage.export(note: model.currentAttributed,
                         title: note.title,
                         tint: GlyphTintPreference.stored())
    }

    @MainActor private static func send(_ selector: Selector, from sender: Any? = nil) {
        NSApp.sendAction(selector, to: nil, from: sender)
    }
}
