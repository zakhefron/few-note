import Foundation
import AppKit
import SwiftUI
@testable import FewNoteKit

/// Dependency-free checks for FewNote's logic. Deliberately avoids XCTest so the suite runs with
/// Command Line Tools alone:
///
///     swift run FewNoteChecks
///
/// Exits non-zero if anything fails, so it can be used in CI.
@main
struct FewNoteChecks {

    @MainActor
    static func main() {
        let suite = CheckSuite()
        countingChecks(suite)
        titleChecks(suite)
        persistenceChecks(suite)
        libraryChecks(suite)
        liveTextChecks(suite)
        replayChecks(suite)
        speedChecks(suite)
        tintChecks(suite)
        stylingChecks(suite)
        listChecks(suite)
        sizeChecks(suite)
        sizePreferenceChecks(suite)
        dateChecks(suite)
        labelColourChecks(suite)
        profileChecks(suite)
        folderChecks(suite)
        draftChecks(suite)
        searchChecks(suite)
        glyphMatrixChecks(suite)
        performanceChecks(suite)

        exit(suite.report())
    }

    // MARK: - Glyph matrix

    @MainActor
    static func glyphMatrixChecks(_ suite: CheckSuite) {
        // The face: every printable character has a shape, and every shape fits the 5x8 box.
        let printable = (32...126).compactMap { UnicodeScalar($0).map(Character.init) }
        suite.equal(printable.count, 95, "printable ASCII")
        suite.equal(printable.filter { GlyphFont.glyphs[$0] == nil }, [], "every printable character has a shape")

        var strayDots = 0
        for dots in GlyphFont.dots.values {
            for dot in dots where dot.column < 0 || dot.column >= GlyphFont.columns
                || dot.row < 0 || dot.row >= GlyphFont.rows {
                strayDots += 1
            }
        }
        suite.equal(strayDots, 0, "every dot sits inside the glyph box")

        // The shapes are really the characters, not filler.
        suite.equal(GlyphFont.litDots(for: "I").count, 11, "'I' is a stem with serifs")
        suite.equal(GlyphFont.litDots(for: " ").count, 0, "a space lights nothing")
        suite.equal(GlyphFont.litDots(for: "\u{1F600}").count, GlyphFont.boxDots.count, "an unknown character falls back to the box")
        suite.equal(GlyphFont.litDots(for: "\u{1F600}"), GlyphFont.boxDots, "the fallback is the missing-glyph box")

        // The accented letters are composed from the plain face, so a European note draws rather
        // than falling back to the box — and a mark only lands where the letter has room for it.
        let accentRows = { (character: Character) -> [String] in
            (GlyphFont.glyphs[character] ?? "").split(separator: "/").map(String.init)
        }
        suite.notEqual(GlyphFont.litDots(for: "é"), GlyphFont.boxDots, "'é' is not the fallback box")
        suite.notEqual(GlyphFont.litDots(for: "ü"), GlyphFont.boxDots, "'ü' is not the fallback box")
        suite.notEqual(GlyphFont.litDots(for: "ñ"), GlyphFont.boxDots, "'ñ' is not the fallback box")
        suite.notEqual(GlyphFont.litDots(for: "ß"), GlyphFont.boxDots, "'ß' is drawn by hand")
        suite.equal(accentRows("ç").first ?? "", ".....", "a cedilla sits below, with nothing above")
        suite.equal(accentRows("ą").first ?? "", ".....", "an ogonek sits below, with nothing above")
        suite.equal(accentRows("ș").first ?? "", ".....", "a comma-below sits below, with nothing above")
        suite.equal(accentRows("é").first ?? "", "...#.", "an acute lights the row above an 'e'")
        suite.equal(accentRows("í").first ?? "", "...#.", "an accent takes the dot's place on an 'i'")
        suite.equal(accentRows("É").first ?? "", "...#.", "an accented capital carries its mark")
        suite.equal(accentRows("É").count, GlyphFont.rows, "an accented capital still fits the box")
        // Every accented letter the face claims to draw is exactly the box, mark and all.
        let accentedOffenders = GlyphFont.glyphs.filter { !$0.key.isASCII }
            .filter { $0.value.split(separator: "/").contains { $0.count != GlyphFont.columns } }
            .map(\.key)
        suite.equal(accentedOffenders, [], "every accented letter is five dots wide")

        // The composed letters are a real set rather than a handful of examples: a note in any of
        // the languages FewNote ships with can be written and read in the face.
        let accented = GlyphFont.glyphs.keys.filter { !$0.isASCII }
        suite.isTrue(accented.count >= 140, "the face draws the European letters (\(accented.count))")
        let boxed = accented.filter { GlyphFont.litDots(for: $0) == GlyphFont.boxDots }
        suite.isTrue(boxed.isEmpty,
                     "and not one of them falls back to the missing-glyph box (\(String(boxed.sorted())))")

        // The cells: exactly 14 x 21 points, so the field is whole points at 1x and whole pixels at 2x.
        suite.equal(GlyphMatrix.Metrics.cellWidth, 14, "a cell is 14 points wide")
        suite.equal(GlyphMatrix.Metrics.cellHeight, 21, "a cell is 21 points tall")

        let metrics = GlyphMatrix.Metrics(width: 800)
        // The layout font is only a ruler, but the text system leans on it for wrapping, selection
        // and the caret, so its advance has to be exactly one cell.
        let advance = ("0" as NSString).size(withAttributes: [.font: metrics.layoutFont]).width
        suite.isTrue(abs(advance - GlyphMatrix.Metrics.cellWidth) < 0.05,
                     "the layout font advances exactly one cell (got \(advance))")
        suite.equal(metrics.contentWidth, CGFloat(metrics.columnCount) * GlyphMatrix.Metrics.cellWidth,
                    "the matrix is a whole number of cells wide")

        // Columns follow the width, and never collapse to nothing.
        suite.isTrue(GlyphMatrix.Metrics(width: 1200).columnCount > GlyphMatrix.Metrics(width: 400).columnCount,
                     "a wider matrix has more columns")
        suite.equal(GlyphMatrix.Metrics(width: 0).columnCount, GlyphMatrix.Metrics.minimumColumns,
                    "a collapsed matrix keeps its minimum columns")
        suite.equal(GlyphMatrix.Metrics(width: 100_000).columnCount, GlyphMatrix.Metrics.maximumColumns,
                    "an enormous matrix is capped")

        // The editor and a replay of the same width agree, cell for cell.
        let editor = GlyphMatrixTextView(width: 900, isEditable: true)
        let replay = GlyphMatrixTextView(width: 900, isEditable: false)
        editor.fit(width: 900, height: 500)
        replay.fit(width: 900, height: 500)
        suite.equal(editor.columnCount, replay.columnCount, "editor and replay share a column count")
        suite.equal(editor.columnCount, GlyphMatrix.Metrics(width: 900).columnCount, "the matrix fills the width with cells")

        // A character sits in a cell, and a long line wraps into the next row of cells.
        let cellWidth = GlyphMatrix.Metrics.cellWidth
        let cellHeight = GlyphMatrix.Metrics.cellHeight
        let inset = GlyphMatrix.Metrics.insetSize
        editor.string = String(repeating: "a", count: editor.columnCount + 3)
        suite.equal(editor.caretCell(forInsertionAt: 0)?.origin, NSPoint(x: inset.width, y: inset.height),
                    "the first cell is the matrix's top-left cell")
        suite.equal(editor.caretCell(forInsertionAt: editor.columnCount + 2)?.origin,
                    NSPoint(x: inset.width + 2 * cellWidth, y: inset.height + cellHeight),
                    "a line wraps into the next row of cells")
        editor.string = "first\nsecond"
        suite.equal(editor.caretCell(forInsertionAt: 6)?.origin, NSPoint(x: inset.width, y: inset.height + cellHeight),
                    "a newline starts the next row of cells")

        // A replay reveals a growing prefix without rewriting the whole matrix.
        replay.reveal("hello")
        replay.reveal("hello world")
        suite.equal(replay.string, "hello world", "a replay reveals text")
        replay.reveal("")
        suite.equal(replay.string, "", "a new replay starts from an empty matrix")

        // The matrix follows the theme.
        let dark = GlyphMatrix.Appearance.resolve(NSAppearance(named: .darkAqua))
        let light = GlyphMatrix.Appearance.resolve(NSAppearance(named: .aqua))
        suite.notEqual(dark.panel, light.panel, "the matrix follows the theme")
        suite.notEqual(dark.glyph, light.glyph, "the lit dots follow the theme")

        // And it is really drawn: the field has dots, and writing lights more of them.
        let blank = GlyphMatrixTextView(width: 900, isEditable: true)
        guard let blankBitmap = renderMatrix(blank, width: 900, height: 400) else {
            suite.fail("the matrix renders")
            return
        }
        let blankInk = inkPixels(blankBitmap, over: blank.matrixAppearance.panel, threshold: 0.03)
        suite.isTrue(blankInk > 2000, "the empty matrix draws its dot field (\(blankInk) dots)")

        let written = GlyphMatrixTextView(width: 900, isEditable: true)
        written.string = "glyph matrix"
        guard let writtenBitmap = renderMatrix(written, width: 900, height: 400) else {
            suite.fail("a written matrix renders")
            return
        }
        // Lit dots are far brighter than the field, so they can be counted on their own.
        let lit = inkPixels(writtenBitmap, over: written.matrixAppearance.panel,
                            threshold: CGFloat(luminance(written.matrixAppearance.glyph)
                                               - luminance(written.matrixAppearance.panel)) / 2)
        suite.isTrue(lit > 300, "12 characters light up their dots (\(lit) lit pixels)")

        writeSampleSheet()
        writeStyleSheet()
        writeAccentSheet()
        writeExportSample()
    }

    /// A sheet of every accented letter, so the composed marks can be judged by eye.
    @MainActor
    static func writeAccentSheet() {
        let previous = GlyphMatrix.Metrics.pitch
        GlyphMatrix.Metrics.pitch = CGFloat(MatrixSize.defaultPitch * 2.2)
        defer { GlyphMatrix.Metrics.pitch = previous }

        let extras = GlyphFont.glyphs.keys.filter { !$0.isASCII }
            .sorted { ($0.isUppercase ? 1 : 0, $0) < ($0.isUppercase ? 1 : 0, $1) }
        var lines: [String] = []
        var current = ""
        for character in extras {
            current.append(character)
            if current.count >= 14 { lines.append(current); current = "" }
        }
        if !current.isEmpty { lines.append(current) }

        let view = GlyphMatrixTextView(width: 1400, isEditable: false)
        view.string = lines.joined(separator: "\n")
        guard let rep = renderMatrix(view, width: 1400, height: 900) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FewNoteAccentSample.png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("accent sample (\(extras.count) letters): \(url.path)")
    }

    /// A sheet of the four strikes at a size big enough to look at, so bold and italic can be
    /// judged by eye and not only by counting dots.
    @MainActor
    static func writeStyleSheet() {
        let previous = GlyphMatrix.Metrics.pitch
        GlyphMatrix.Metrics.pitch = MatrixSize.maximumPitch
        defer { GlyphMatrix.Metrics.pitch = previous }

        let view = GlyphMatrixTextView(width: 760, isEditable: false)
        let note = NSMutableAttributedString()
        for style in GlyphFont.Style.allCases {
            note.append(NSAttributedString(
                string: "\(style.rawValue): Sphinx egg 0123 Wm. aeiou\n",
                attributes: NoteDocument.canvasAttributes(style: style)
            ))
        }
        view.setNote(note)
        guard let rep = renderMatrix(view, width: 760, height: 240) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FewNoteStyleSample.png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("style sample: \(url.path)")
    }

    /// The exported picture of a note, so the card, the margin and the hugging width can be seen
    /// rather than only measured.
    @MainActor
    static func writeExportSample() {
        let note = NSMutableAttributedString(string: "FewNote\n\n")
        note.append(NSAttributedString(string: "A note that leaves the app as a picture of itself.\n",
                                       attributes: NoteDocument.canvasAttributes()))
        note.append(NSAttributedString(string: "And a line in another colour.\n",
                                       attributes: NoteDocument.canvasAttributes(tint: .ember)))
        note.append(NSAttributedString(string: "• one\n• two\n", attributes: NoteDocument.canvasAttributes()))
        for appearance in [NSAppearance(named: .darkAqua), NSAppearance(named: .aqua)] {
            let name = appearance?.name == .darkAqua ? "dark" : "light"
            guard let rep = NoteImage.bitmap(of: note, tint: .chalk, appearance: appearance) else { continue }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("FewNoteExportSample-\(name).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("export sample (\(name)): \(url.path) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
        }
    }

    /// Renders a sheet of every character the face can draw, so the shapes can be looked at.
    @MainActor
    static func writeSampleSheet() {
        let sheet = GlyphMatrixTextView(width: 1400, isEditable: false)
        sheet.string = """
        THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG
        the quick brown fox jumps over the lazy dog
        0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ
        abcdefghijklmnopqrstuvwxyz
        !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~
        gjpqy descend, brackets ( ) [ ] { } go below too
        Mixed Case 101: FewNote writes on a dot matrix.
        """
        guard let rep = renderMatrix(sheet, width: 1400, height: 400) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FewNoteMatrixSample.png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("matrix sample: \(url.path)")

        let caret = GlyphMatrixTextView(width: 300, isEditable: false)
        caret.showsCaretCell = true
        caret.string = "FewNote"
        guard let caretRep = renderMatrix(caret, width: 300, height: 84) else { return }
        let caretURL = FileManager.default.temporaryDirectory.appendingPathComponent("FewNoteMatrixCaret.png")
        try? caretRep.representation(using: .png, properties: [:])?.write(to: caretURL)
        print("caret sample: \(caretURL.path)")

        // Every colour on its own, so the palette and the glow can be looked at rather than only
        // counted. One file per colour keeps the sample honest — no compositing in between.
        for tint in GlyphTint.allCases {
            let view = GlyphMatrixTextView(width: 760, isEditable: false)
            view.tint = tint
            view.string = "\(tint.label) 0123 the quick brown fox jumps"
            guard let rep = renderMatrix(view, width: 760, height: 21) else { continue }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("FewNoteTint-\(tint.rawValue).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("tint sample (\(tint.label)): \(url.path)")
        }
    }

    /// Renders a matrix to a bitmap so its drawing can be measured rather than eyeballed.
    @MainActor
    static func renderMatrix(_ textView: GlyphMatrixTextView, width: CGFloat, height: CGFloat) -> NSBitmapImageRep? {
        textView.fit(width: width, height: height)
        guard let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) else { return nil }
        textView.cacheDisplay(in: textView.bounds, to: rep)
        return rep
    }

    /// Counts pixels that differ from the panel by more than `threshold`.
    @MainActor
    static func inkPixels(_ rep: NSBitmapImageRep, over panel: NSColor, threshold: CGFloat) -> Int {
        let reference = panel.usingColorSpace(.deviceRGB) ?? panel
        var count = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if abs(colour.redComponent - reference.redComponent) > threshold
                    || abs(colour.greenComponent - reference.greenComponent) > threshold
                    || abs(colour.blueComponent - reference.blueComponent) > threshold {
                    count += 1
                }
            }
        }
        return count
    }

    // MARK: - Counting

    static func countingChecks(_ suite: CheckSuite) {
        suite.equal(NoteText.characterCount(""), 0, "empty character count")
        suite.equal(NoteText.characterCount("hello"), 5, "simple character count")
        // A family emoji is one grapheme cluster despite many scalars ("h", "i", " ", emoji).
        suite.equal(NoteText.characterCount("hi 👨‍👩‍👧‍👦"), 4, "emoji counts as one character")
        suite.equal(NoteText.characterCount("👨‍👩‍👧‍👦"), 1, "standalone emoji counts as one character")
        suite.equal(NoteText.characterCount("🇮🇳"), 1, "flag emoji counts as one character")
        suite.equal(NoteText.characterCount("café"), 4, "accented character count")

        suite.equal(NoteText.wordCount(""), 0, "empty word count")
        suite.equal(NoteText.wordCount("   "), 0, "whitespace-only word count")
        suite.equal(NoteText.wordCount("one"), 1, "single word count")
        suite.equal(NoteText.wordCount("one two\nthree"), 3, "multiline word count")
        suite.equal(NoteText.wordCount("  spaced   out  "), 2, "extra whitespace is ignored")
    }

    // MARK: - Titles

    static func titleChecks(_ suite: CheckSuite) {
        suite.equal(NoteText.displayTitle("Shopping list"), "Shopping list", "plain title")
        suite.equal(NoteText.displayTitle("  spaced out  "), "spaced out", "title is trimmed")
        // FewNote no longer interprets Markdown, so the line is kept exactly as written.
        suite.equal(NoteText.displayTitle("# TODO: ship it"), "# TODO: ship it", "markers are kept")
        suite.equal(NoteText.displayTitle("**bold** opening"), "**bold** opening", "no inline stripping")
        suite.equal(NoteText.displayTitle("\n\nSecond line wins"), "Second line wins", "skips blank leading lines")
        suite.equal(NoteText.displayTitle(""), "Untitled", "empty title fallback")
        suite.equal(NoteText.displayTitle("   \n  \n"), "Untitled", "blank-only title fallback")
        suite.equal(NoteText.displayTitle(String(repeating: "x", count: 400)).count, 120, "long titles are capped")
    }

    // MARK: - Autosave and restore

    @MainActor
    static func persistenceChecks(_ suite: CheckSuite) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FewNoteChecks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // First session: a fresh library starts ready to type, then we write and flush.
        let first = AppModel(directory: directory)
        suite.equal(first.notes.count, 1, "fresh library starts with one note")
        suite.equal(first.characterCount, 0, "fresh note starts empty")

        first.textEdited("Buy milk\n\n- [ ] two litres")
        first.saveNow()
        let noteID = first.selectedNoteID

        // Second session: relaunch restores the same note, its title and its exact text.
        let second = AppModel(directory: directory)
        suite.equal(second.selectedNoteID, noteID, "relaunch restores the last note")
        suite.equal(second.selectedNote?.title, "Buy milk", "restored note title")
        suite.isTrue(second.selectedNote?.url.pathExtension == "rtf", "new notes are rich-text files")

        if let note = second.selectedNote {
            let restored = second.loadAttributed(for: note).string
            suite.equal(restored, "Buy milk\n\n- [ ] two litres", "note text round-trips exactly")
            suite.equal(second.characterCount, NoteText.characterCount(restored), "counts restored")
            suite.equal(second.wordCount, NoteText.wordCount(restored), "word count restored")
        } else {
            suite.fail("relaunch should have a selected note")
        }

        // Empty notes must be safe to save.
        second.textEdited("")
        second.saveNow()
        suite.equal(second.characterCount, 0, "saving an empty note is safe")

        // Creating and deleting keeps at least one note ready to type.
        let firstID = second.selectedNoteID
        second.createNote()
        suite.equal(second.notes.count, 2, "creating a note adds it to the library")
        suite.notEqual(second.selectedNoteID, firstID, "new note becomes selected")

        if let newID = second.selectedNoteID {
            second.deleteNote(newID)
            suite.equal(second.notes.count, 1, "deleting a note removes it")
            suite.equal(second.selectedNoteID, firstID, "selection falls back to the remaining note")
        }
        if let lastID = firstID {
            second.deleteNote(lastID)
            suite.equal(second.notes.count, 1, "deleting the final note leaves a fresh one")
            suite.isTrue(second.selectedNoteID != nil, "a note is always selected")
        }
    }

    // MARK: - Live text

    @MainActor
    static func liveTextChecks(_ suite: CheckSuite) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FewNoteChecks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // A replay reads `currentText`, which must include keystrokes the debounce has not
        // written yet — otherwise it would retype a stale note.
        let model = AppModel(directory: directory)
        model.textEdited("Live text")
        suite.equal(model.currentText, "Live text", "currentText includes unsaved keystrokes")
    }

    // MARK: - Replay

    @MainActor
    static func replayChecks(_ suite: CheckSuite) {
        let engine = ReplayEngine()
        suite.isTrue(!engine.isReplaying, "replay starts idle")

        engine.replay(text: "hi")
        suite.isTrue(engine.isReplaying, "replay starts")
        suite.isTrue(
            pump(until: { engine.visibleText == "hi" }),
            "typewriter reveals every letter (got \"\(engine.visibleText)\")"
        )
        suite.isTrue(pump(until: { !engine.isReplaying }), "replay finishes on its own")
        suite.isTrue(engine.visibleText.isEmpty, "finished replay cleans up")

        // Stopping halfway must leave nothing behind and never touch the note text.
        let long = String(repeating: "typewriter ", count: 200)
        engine.replay(text: long)
        _ = pump(until: { !engine.visibleText.isEmpty })
        engine.stop()
        suite.isTrue(!engine.isReplaying && engine.visibleText.isEmpty, "stop clears the replay")

        // Empty notes are a no-op rather than an empty overlay.
        engine.replay(text: "")
        suite.isTrue(!engine.isReplaying, "empty note does not start a replay")

    }

    // MARK: - Text colour and glow

    /// The chosen colour has to reach the dots, and the glow has to be a glow — so these checks
    /// resolve the palette and then measure the pixels the matrix actually drew.
    @MainActor
    static func tintChecks(_ suite: CheckSuite) {
        _ = NSApplication.shared

        suite.equal(GlyphTint.allCases.count, 6, "six text colours are offered")
        suite.equal(GlyphTintPreference.resolve("nonsense"), .chalk, "an unknown colour falls back to chalk")
        suite.equal(GlyphTintPreference.resolve("lime"), .lime, "a stored colour survives")

        // Every colour is a light on the dark surface and ink on the light one: brighter there,
        // darker here. That is what "proper colours for the theme" means in practice.
        for tint in GlyphTint.allCases {
            let dark = luminance(tint.colour(darkMode: true))
            let light = luminance(tint.colour(darkMode: false))
            suite.isTrue(dark > light, "\(tint.label) is bright on the dark surface and deep on the light one (dark \(dark), light \(light))")
        }

        // The colours have to be distinguishable from each other, or the picker is decoration.
        for (first, second) in GlyphTint.allCases.flatMap({ a in GlyphTint.allCases.map { (a, $0) } }) where first != second {
            suite.isTrue(first.colour(darkMode: true) != second.colour(darkMode: true),
                         "\(first.label) and \(second.label) are different colours")
        }

        // The surface's own palette follows the tint, and the glow is the same colour as the dots.
        for tint in GlyphTint.allCases {
            for isDark in [true, false] {
                let appearance = GlyphMatrix.Appearance.resolve(
                    NSAppearance(named: isDark ? .darkAqua : .aqua), tint: tint)
                suite.equal(appearance.glyph, tint.colour(darkMode: isDark),
                            "\(tint.label) reaches the lit dots")
                suite.equal(appearance.glow?.colour, appearance.glyph,
                            "\(tint.label) glows in its own colour")
                suite.isTrue((appearance.glow?.innerBlur ?? 0) > 0 && (appearance.glow?.innerAlpha ?? 0) > 0,
                             "the glow is switched on")
            }
        }

        // The dark surface glows harder than the light one, where a bloom would only smudge ink.
        let darkGlow = GlyphMatrix.Appearance.resolve(NSAppearance(named: .darkAqua), tint: .chalk).glow
        let lightGlow = GlyphMatrix.Appearance.resolve(NSAppearance(named: .aqua), tint: .chalk).glow
        suite.isTrue((darkGlow?.innerAlpha ?? 0) > (lightGlow?.innerAlpha ?? 1), "the dark surface glows harder")

        // And it is really drawn: a lit dot takes the tint's colour...
        let view = GlyphMatrixTextView(width: 900, isEditable: false)
        view.tint = .ember
        view.string = "H"
        guard let rep = renderMatrix(view, width: 900, height: 200) else {
            suite.fail("a tinted matrix renders")
            return
        }
        let scale = CGFloat(rep.pixelsWide) / 900
        let ember = GlyphTint.ember.colour(darkMode: true).usingColorSpace(.deviceRGB)

        // The left stem of "H" is lit at the centre of cell (0, 0)'s first dot column, row 0.
        let pitch = GlyphMatrix.Metrics.pitch
        let inset = GlyphMatrix.Metrics.insetSize
        let dotCentre = CGPoint(x: inset.width + pitch / 2, y: inset.height + pitch / 2)
        let stem = pixel(rep, at: dotCentre, scale: scale)
        suite.isTrue(stem != nil && closeEnough(stem, ember, tolerance: 0.12),
                     "a lit dot is drawn in the chosen colour (got \(describe(stem)), wanted \(describe(ember)))")

        // ...and the gap between two lit dots is not the panel, because the glow fills it.
        let panel = view.matrixAppearance.panel.usingColorSpace(.deviceRGB)
        let betweenDots = CGPoint(x: inset.width + pitch / 2, y: inset.height + pitch * 2)
        let halo = pixel(rep, at: betweenDots, scale: scale)
        suite.isTrue(luminance(halo) > luminance(panel) + 0.02,
                     "the glow lights the gap between dots (halo \(describe(halo)), panel \(describe(panel)))")

        // The same point far from the text sits on the same part of the field but has no glyph
        // nearby, so it must be plainly darker: the glow is local, not a wash over everything.
        let far = CGPoint(x: inset.width + pitch / 2 + GlyphMatrix.Metrics.cellWidth * 20,
                          y: inset.height + pitch * 2 + GlyphMatrix.Metrics.cellHeight * 4)
        let away = pixel(rep, at: far, scale: scale)
        suite.isTrue(luminance(halo) > luminance(away) + 0.02,
                     "the glow is local: the same gap far from the text has none (halo \(describe(halo)), far \(describe(away)))")
    }

    // MARK: - Typing speed

    @MainActor
    static func speedChecks(_ suite: CheckSuite) {
        suite.equal(TypingSpeed.normal, 1.0, "a replay starts at normal speed")
        suite.equal(TypingSpeed.fastest, 1.0, "the fastest the slider goes is the ordinary pace")
        suite.equal(TypingSpeed.slowest, 0.1, "and the slowest is a tenth of it")
        suite.equal(TypingSpeed.clamped(99), TypingSpeed.fastest, "an absurd speed is capped")
        suite.equal(TypingSpeed.clamped(0), TypingSpeed.slowest, "a speed of zero is floored")
        suite.equal(TypingSpeed.clamped(.nan), TypingSpeed.normal, "a nonsense speed falls back to normal")

        // Slower means a longer wait, at every note length.
        for count in [12, 200, 4_000, 60_000] {
            let slow = TypingSpeed.tickDelay(forCharacterCount: count, speed: TypingSpeed.slowest)
            let half = TypingSpeed.tickDelay(forCharacterCount: count, speed: 0.5)
            let normal = TypingSpeed.tickDelay(forCharacterCount: count, speed: TypingSpeed.fastest)
            suite.isTrue(slow > half && half > normal,
                         "speed scales the delay for a \(count)-character note (\(slow) > \(half) > \(normal))")
        }

        // Long notes reveal several characters per tick, so a delay that was per-character would
        // make them take hours. The delay must fall as the note grows.
        suite.isTrue(TypingSpeed.tickDelay(forCharacterCount: 20, speed: 1)
                     >= TypingSpeed.tickDelay(forCharacterCount: 20_000, speed: 1),
                     "a longer note types at least as fast a tick")

        // A whole note stays inside a sane duration at normal speed — and the slider can stretch
        // it out when the user asks for that.
        let ticks = 1_200.0
        let normalRun = Double(TypingSpeed.tickDelay(forCharacterCount: 60_000, speed: 1)) / 1e9 * ticks
        suite.isTrue(normalRun < 30, "a huge note still replays in under 30s at normal speed (got \(normalRun)s)")
        let slowRun = Double(TypingSpeed.tickDelay(forCharacterCount: 60_000, speed: TypingSpeed.slowest)) / 1e9 * ticks
        suite.isTrue(slowRun > normalRun, "the slow end is genuinely slower (got \(slowRun)s)")
        suite.isTrue(slowRun < 60, "but the slow end is capped, so it is not glacial (got \(slowRun)s)")

        // The stored value is what the engine reads back, which is how the slider reaches a
        // replay that is already running.
        let defaults = UserDefaults(suiteName: "FewNoteChecksSpeed")!
        defer { defaults.removePersistentDomain(forName: "FewNoteChecksSpeed") }
        suite.equal(TypingSpeed.stored(in: defaults), TypingSpeed.normal, "an unset speed reads as normal")
        defaults.set(0.5, forKey: ReplayPreference.speedKey)
        suite.equal(TypingSpeed.stored(in: defaults), 0.5, "a stored speed is read back")
        defaults.set(99.0, forKey: ReplayPreference.speedKey)
        suite.equal(TypingSpeed.stored(in: defaults), TypingSpeed.fastest, "a stored speed is clamped on the way out")
        defaults.set(0.01, forKey: ReplayPreference.speedKey)
        suite.equal(TypingSpeed.stored(in: defaults), TypingSpeed.slowest, "and so is one below the slow end")

        suite.equal(TypingSpeed.description(1), "1×", "the speed is shown as a multiplier")
        suite.equal(TypingSpeed.description(0.5), "0.5×", "half speed reads as half")
        suite.equal(TypingSpeed.description(0.1), "0.1×", "the slow end reads exactly")
        suite.equal(TypingSpeed.description(99), "1×", "the caption clamps with the slider")

        // A person's timing, not a metronome's: a beat at a full stop, a smaller one at a comma,
        // and none at all in the middle of a word.
        suite.equal(TypingSpeed.pauseFactor(after: "a"), 1, "no pause in the middle of a word")
        suite.isTrue(TypingSpeed.pauseFactor(after: ".") > TypingSpeed.pauseFactor(after: ","),
                     "a sentence takes a longer beat than a comma")
        suite.isTrue(TypingSpeed.pauseFactor(after: ",") > 1, "a comma takes a beat")
        suite.isTrue(TypingSpeed.pauseFactor(after: "\n") > 1, "so does the end of a line")
        suite.equal(TypingSpeed.pauseFactor(after: nil), 1, "nothing to follow reads as no pause")

        // The wander keeps the tick in hand: it never doubles it, and it never goes backwards.
        let tick: UInt64 = 20_000_000
        for _ in 0..<200 {
            let natural = TypingSpeed.naturalTick(tick, after: "a")
            suite.isTrue(natural >= TypingSpeed.fastestScaledTick,
                         "a wandered tick stays inside the fastest bound")
            suite.isTrue(natural <= UInt64(Double(tick) * 1.3),
                         "and never wanders far past the tick (\(natural))")
        }
        // Over enough ticks the wander averages out, which is what keeps the pace meaning
        // something rather than the timing being noise.
        let average = (0..<600)
            .map { _ in Double(TypingSpeed.naturalTick(tick, after: "a")) }
            .reduce(0, +) / 600
        suite.isTrue(abs(average - Double(tick)) < Double(tick) * 0.05,
                     "the wander has no bias in it (\(Int(average)) vs \(tick))")
    }

    // MARK: - Styling

    /// The face's styles, and the round trip through the file.
    @MainActor
    static func stylingChecks(_ suite: CheckSuite) {
        // Bold strikes more dots; italic leans, and always within the cell.
        let plain = GlyphFont.litDots(for: "H")
        let bold = GlyphFont.placedDots(for: "H", style: .bold)
        suite.isTrue(bold.count > plain.count, "bold strikes more dots than regular (\(bold.count) > \(plain.count))")

        // Bold is a heavier strike in the ink as well as in the pattern: the dots themselves are
        // fatter, which is what makes a doubled stroke read as one solid line.
        let metrics = GlyphMatrix.Metrics(width: 900)
        suite.equal(GlyphMatrix.ink(for: .regular, metrics: metrics), metrics.dotDiameter,
                    "an ordinary dot is the ordinary size")
        suite.isTrue(GlyphMatrix.ink(for: .bold, metrics: metrics) > metrics.dotDiameter,
                     "a bold dot lays down more ink")
        suite.isTrue(GlyphMatrix.ink(for: .bold, metrics: metrics) < metrics.dotPitch,
                     "and still fits the dot grid")
        suite.isTrue(bold.count >= plain.count * 3 / 2,
                     "bold doubles most of a glyph's dots (\\(bold.count) vs \\(plain.count))")

        let upright = GlyphFont.placedDots(for: "H", style: .regular)
        let leaned = GlyphFont.placedDots(for: "H", style: .italic)
        suite.equal(leaned.count, upright.count, "italic lights the same dots as regular")
        let topLean = leaned[0].column - upright[0].column
        let footLean = leaned[leaned.count - 1].column - upright[upright.count - 1].column
        suite.isTrue(topLean > footLean, "italic leans at the top more than at the foot")
        suite.isTrue(leaned.allSatisfy { $0.column >= 0 && $0.column < Double(GlyphFont.columns) + 1 },
                     "an italic glyph leans into the gap, never into the next cell")
        suite.isTrue(GlyphFont.placedDots(for: "H", style: .boldItalic).count > plain.count,
                     "bold italic is both")

        // The marks a list and pasted prose need.
        suite.isTrue(GlyphFont.litDots(for: "•").count == 4, "the bullet is a solid dot")
        suite.notEqual(GlyphFont.litDots(for: "•"), GlyphFont.boxDots, "the bullet is not the fallback box")
        suite.notEqual(GlyphFont.litDots(for: "’"), GlyphFont.boxDots, "a curly quote has a shape")
        suite.notEqual(GlyphFont.litDots(for: "…"), GlyphFont.boxDots, "an ellipsis has a shape")

        // A note's styling survives being written and read back.
        let document = NSMutableAttributedString(string: "quiet loud blue")
        document.setAttributes(NoteDocument.canvasAttributes(), range: NSRange(location: 0, length: 5))
        document.setAttributes(NoteDocument.canvasAttributes(style: .bold), range: NSRange(location: 6, length: 4))
        document.setAttributes(NoteDocument.canvasAttributes(style: .boldItalic, tint: .ember),
                               range: NSRange(location: 11, length: 4))

        guard let data = NoteDocument.rtfData(for: document) else {
            suite.fail("a note writes as RTF")
            return
        }
        let restored = NoteDocument.attributed(fromFileExtension: "rtf", data: data)

        suite.equal(restored.string, "quiet loud blue", "the text survives the file")
        suite.equal(NoteStyle.style(in: restored.attributes(at: 0, effectiveRange: nil)), .regular,
                    "plain text stays plain")
        suite.equal(NoteStyle.style(in: restored.attributes(at: 6, effectiveRange: nil)), .bold,
                    "bold survives the file")
        suite.equal(NoteStyle.style(in: restored.attributes(at: 11, effectiveRange: nil)), .boldItalic,
                    "bold italic survives the file")
        suite.equal(NoteStyle.tint(in: restored.attributes(at: 11, effectiveRange: nil)), .ember,
                    "a coloured run keeps its colour")
        suite.equal(NoteStyle.tint(in: restored.attributes(at: 6, effectiveRange: nil)), nil,
                    "an uncoloured run stays uncoloured")

        // Underline and strike survive the file, in both directions: written as FewNote's own
        // mask, read back from whatever standard attributes foreign writers of RTF use.
        let dressedDecor = NSMutableAttributedString(string: "plain under struck both")
        dressedDecor.setAttributes(NoteDocument.canvasAttributes(), range: NSRange(location: 0, length: 5))
        dressedDecor.setAttributes(NoteDocument.canvasAttributes(decor: .underline),
                              range: NSRange(location: 6, length: 4))
        dressedDecor.setAttributes(NoteDocument.canvasAttributes(decor: .strike),
                              range: NSRange(location: 11, length: 6))
        dressedDecor.setAttributes(NoteDocument.canvasAttributes(decor: [.underline, .strike]),
                              range: NSRange(location: 18, length: 4))
        guard let dressData = NoteDocument.rtfData(for: dressedDecor) else {
            suite.fail("a decorated note writes as RTF")
            return
        }
        let redressed = NoteDocument.attributed(fromFileExtension: "rtf", data: dressData)
        suite.equal(NoteStyle.decoration(in: redressed.attributes(at: 0, effectiveRange: nil)), [],
                    "plain text carries no decoration")
        suite.equal(NoteStyle.decoration(in: redressed.attributes(at: 6, effectiveRange: nil)), [.underline],
                    "an underline survives the file")
        suite.equal(NoteStyle.decoration(in: redressed.attributes(at: 11, effectiveRange: nil)), [.strike],
                    "a strike survives the file")
        suite.equal(NoteStyle.decoration(in: redressed.attributes(at: 18, effectiveRange: nil)),
                    [.underline, .strike],
                    "underline and strike travel together")

        // And a foreign file's own markers are read back as the same decoration.
        let foreign = NSMutableAttributedString(string: "alien note")
        foreign.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue],
                              range: NSRange(location: 0, length: 5))
        foreign.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue],
                              range: NSRange(location: 6, length: 4))
        let alienRestored = NoteDocument.canvas(from: foreign)
        suite.equal(NoteStyle.decoration(in: alienRestored.attributes(at: 0, effectiveRange: nil)), [.underline],
                    "a foreign underline becomes the matrix's")
        suite.equal(NoteStyle.decoration(in: alienRestored.attributes(at: 6, effectiveRange: nil)), [.strike],
                    "a foreign strike becomes the matrix's")

        // On the surface, the decoration is drawn: a decorated cell lays more ink down than a
        // plain one, and a whole word joined under one line reads across the letter gaps.
        let decorMetrics = GlyphMatrix.Metrics(width: 900)
        let plainCell = CGMutablePath()
        GlyphMatrix.addDots(for: "a", inCell: .zero, metrics: decorMetrics, into: plainCell)
        let underlinedCell = CGMutablePath()
        GlyphMatrix.addDots(for: "a", inCell: .zero, metrics: decorMetrics,
                            decor: .underline, into: underlinedCell)
        suite.isTrue(underlinedCell.boundingBox.width > plainCell.boundingBox.width,
                     "an underline crosses the letter gap, joining the cells")
        suite.isTrue(underlinedCell.boundingBox.height > plainCell.boundingBox.height,
                     "an underline draws below the glyph")
        let struckCell = CGMutablePath()
        GlyphMatrix.addDots(for: "a", inCell: .zero, metrics: decorMetrics, decor: .strike, into: struckCell)
        suite.isTrue(struckCell.boundingBox.minY > plainCell.boundingBox.minY ||
                     struckCell.boundingBox.height == plainCell.boundingBox.height,
                     "a strike draws inside the glyph's own rows")

        // On the matrix the text itself is invisible: the dots are what is drawn.
        let dressed = restored.attributes(at: 0, effectiveRange: nil)
        suite.equal((dressed[.font] as? NSFont)?.fontName, GlyphMatrix.Metrics.layoutFont.fontName,
                    "a note is dressed in the matrix's ruler")
        suite.equal((dressed[.foregroundColor] as? NSColor)?.alphaComponent, 0,
                    "the note's text is invisible — the dots are the writing")

        // Colours are matched back to the palette, so they follow the theme.
        suite.equal(GlyphTint.matching(GlyphTint.rose.colour(darkMode: false)), .rose,
                    "a light-surface colour matches its palette colour")
        suite.equal(GlyphTint.matching(GlyphTint.rose.colour(darkMode: true)), .rose,
                    "a dark-surface colour matches its palette colour")
        suite.equal(GlyphTint.matching(.black), nil, "black is nobody's palette colour")
        suite.equal(GlyphTint.matching(.clear), nil, "an invisible colour matches nothing")

        // Bulleted lines, as text.
        let list = "one\ntwo\nthree" as NSString
        suite.equal(NoteList.lineRanges(in: list, for: NSRange(location: 0, length: 0)).count, 1,
                    "a caret sits on one line")
        suite.equal(NoteList.lineRanges(in: list, for: NSRange(location: 0, length: 13)).count, 3,
                    "a selection covering the note touches three lines")
        suite.isTrue(!NoteList.isBulleted(list, in: NSRange(location: 0, length: 13)),
                     "plain lines are not a list")
        let bulleted = "• one\n— not a bullet" as NSString
        suite.isTrue(NoteList.isBulleted(bulleted, in: NSRange(location: 0, length: 1)),
                     "a bulleted line reads as a list")
        suite.isTrue(!NoteList.isBulleted(bulleted, in: NSRange(location: 7, length: 1)),
                     "an unbulleted line does not")
    }

    // MARK: - Lists

    /// A list is a bulleted line that hangs: the bullet at the margin, and everything that wraps
    /// under it lined up two cells in — and Return and Backspace keep it that way while writing.
    @MainActor
    static func listChecks(_ suite: CheckSuite) {
        let cellWidth = GlyphMatrix.Metrics.cellWidth
        let indent = CGFloat(NoteList.indentCells) * cellWidth

        let hanging = GlyphMatrix.paragraphStyle(list: true)
        suite.equal(hanging.headIndent, indent, "a list item indents its wrapped lines by two cells")
        suite.equal(hanging.firstLineHeadIndent, 0, "the bullet itself starts at the margin")
        suite.equal(GlyphMatrix.paragraphStyle(list: false).headIndent, 0, "an ordinary line does not hang")
        suite.equal(hanging.minimumLineHeight, GlyphMatrix.paragraphStyle().minimumLineHeight,
                    "hanging does not change the line height")

        // The prefix, as text.
        suite.equal(NoteList.bulletPrefix(of: "• one"), NoteList.bullet.count, "a bulleted line has its prefix")
        suite.equal(NoteList.bulletPrefix(of: "•"), 1, "a bare bullet is still a bullet")
        suite.equal(NoteList.bulletPrefix(of: "one"), 0, "an ordinary line has none")

        // The editor's own behaviour around a list.
        let view = GlyphMatrixTextView(width: 900, isEditable: true)
        view.fit(width: 900, height: 400)

        view.string = "first"
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.toggleList(nil)
        suite.equal(view.string, "• first", "the list control bullets the line")
        suite.equal(headIndent(of: view, at: 0), indent, "and the line starts to hang")

        // Return starts the next item, struck and indented like the line above.
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        view.insertNewline(nil)
        suite.equal(view.string, "• first\n• ", "return starts the next item")
        suite.equal(headIndent(of: view, at: (view.string as NSString).length - 1), indent,
                    "the new item hangs too")
        suite.equal(NoteStyle.style(in: view.textStorage?.attributes(at: 0, effectiveRange: nil) ?? [:]),
                    NoteStyle.style(in: view.textStorage?.attributes(at: 9, effectiveRange: nil) ?? [:]),
                    "and carries the same strike as the line above")

        // Return on an empty item ends the list, without moving the caret down: Notes' behaviour.
        view.insertNewline(nil)
        suite.equal(view.string, "• first\n", "return on an empty item ends the list")
        suite.equal(view.selectedRange().location, 8, "and the caret stays on that line")

        // Backspace at the start of an item's own text takes the bullet away.
        view.setSelectedRange(NSRange(location: 2, length: 0))
        view.deleteBackward(nil)
        suite.equal(view.string, "first\n", "backspace on the bullet removes it")
        suite.equal(headIndent(of: view, at: 0), 0, "and the line stops hanging")

        // Toggling a whole selection back off clears the bullets and the hanging.
        view.string = "one\ntwo\nthree"
        view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
        view.toggleList(nil)
        suite.equal(view.string, "• one\n• two\n• three", "a selection becomes a list")
        view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
        view.toggleList(nil)
        suite.equal(view.string, "one\ntwo\nthree", "and back again")
        suite.equal(headIndent(of: view, at: 4), 0, "with nothing left hanging")

        // A wrapped item lines up under its own text.
        let wrapping = GlyphMatrixTextView(width: 900, isEditable: true)
        wrapping.fit(width: 900, height: 400)
        let columns = wrapping.columnCount
        wrapping.setNote(NSAttributedString(string: "• " + String(repeating: "x", count: columns)))
        let cell = wrapping.caretCell(forInsertionAt: columns)
        suite.equal(cell?.origin.x, GlyphMatrix.Metrics.insetSize.width + indent,
                    "a wrapped list line lines up under the text")
    }

    /// The paragraph style a character carries, which is how hanging is measured.
    @MainActor
    static func headIndent(of view: GlyphMatrixTextView, at location: Int) -> CGFloat {
        guard let storage = view.textStorage, storage.length > 0 else { return 0 }
        let index = min(max(location, 0), storage.length - 1)
        let style = storage.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle
        return style?.headIndent ?? 0
    }

    // MARK: - Drawing cost

    /// How long the surface takes to draw, on a screenful of writing — printed so a regression
    /// shows up in the numbers as well as in a failure. It is the whole point of the surface that
    /// it feels light: the bloom behind the dots is painted from an image of its own, and the
    /// pixels are squares rather than circles, so a pass over a full screen and the pass a
    /// keystroke causes both stay well inside a frame.
    @MainActor
    static func performanceChecks(_ suite: CheckSuite) {
        let line = "the quick brown fox jumps over the lazy dog 0123456789\n"
        let view = GlyphMatrixTextView(width: 760, isEditable: true)
        view.setNote(NSAttributedString(string: String(repeating: line, count: 26)))
        view.fit(width: 760, height: 540)

        let full = measure(view, rect: view.bounds)
        let keystroke = measure(view, rect: NSRect(x: 0, y: 0, width: 20, height: 30))
        print(String(format: "a screenful draws in %.2f ms; a keystroke's pass in %.2f ms",
                     full * 1000, keystroke * 1000))

        suite.isTrue(full < 0.05,
                     String(format: "a screenful draws in well under 50 ms (got %.1f ms)", full * 1000))
        suite.isTrue(keystroke < 0.005,
                     String(format: "a keystroke's pass stays inside a frame (got %.2f ms)",
                            keystroke * 1000))
    }

    /// The average time a redraw of one rect takes.
    @MainActor
    static func measure(_ view: GlyphMatrixTextView, rect: NSRect, frames: Int = 8) -> TimeInterval {
        _ = renderMatrix(view, width: view.bounds.width, height: view.bounds.height)
        let start = Date()
        for _ in 0..<frames {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { break }
            view.cacheDisplay(in: rect, to: rep)
        }
        return Date().timeIntervalSince(start) / Double(frames)
    }

    // MARK: - Text size

    @MainActor
    static func sizeChecks(_ suite: CheckSuite) {
        suite.equal(MatrixSize.clamped(0.1), MatrixSize.minimumPitch, "a tiny pitch is clamped")
        suite.equal(MatrixSize.clamped(99), MatrixSize.maximumPitch, "a huge pitch is clamped")
        suite.equal(MatrixSize.clamped(.nan), MatrixSize.defaultPitch, "a nonsense pitch falls back")
        suite.equal(MatrixSize.percent(of: MatrixSize.minimumPitch), 30, "the smallest size is 30%")
        suite.equal(MatrixSize.percent(of: MatrixSize.maximumPitch), 150, "the largest size is 150%")
        suite.equal(MatrixSize.percent(of: MatrixSize.defaultPitch), 100, "the default reads as 100%")
        suite.equal(MatrixSize.pitch(forPercent: 100), MatrixSize.defaultPitch, "100% is the default pitch")
        suite.equal(MatrixSize.pitch(forPercent: 30), MatrixSize.minimumPitch, "30% is the smallest pitch")
        suite.equal(MatrixSize.snapped(MatrixSize.pitch(forPercent: 42)), MatrixSize.pitch(forPercent: 42),
                    "a whole percent survives being snapped")
        suite.equal(MatrixSize.percent(of: MatrixSize.snapped(MatrixSize.pitch(forPercent: 73))), 73,
                    "a size read back reads the same")
        suite.equal(MatrixSize.percent(of: MatrixSize.pitch(forPercent: 900)), 150,
                    "a size beyond the slider is pulled back to 150%")

        // The size is one number, and the whole grid follows it.
        let defaultWidth = GlyphMatrix.Metrics.cellWidth
        let defaultColumns = GlyphMatrix.Metrics(width: 900).columnCount
        defer { GlyphMatrix.Metrics.pitch = MatrixSize.defaultPitch }

        GlyphMatrix.Metrics.pitch = MatrixSize.maximumPitch
        suite.isTrue(GlyphMatrix.Metrics.cellWidth > defaultWidth, "a bigger pitch makes bigger cells")
        suite.isTrue(GlyphMatrix.Metrics(width: 900).columnCount < defaultColumns,
                     "a bigger pitch fits fewer columns")
        suite.isTrue(GlyphMatrix.Metrics.diameter > 1.6, "the dots grow with the pitch")

        GlyphMatrix.Metrics.pitch = MatrixSize.minimumPitch
        suite.isTrue(GlyphMatrix.Metrics(width: 900).columnCount > defaultColumns,
                     "a smaller pitch fits more columns")
    }

    /// The text size is one shared preference, and a surface that is already on screen has to take
    /// a new size up on the frame it changes — the note is re-dressed where it stands, so nothing
    /// about the writing moves.
    @MainActor
    static func sizePreferenceChecks(_ suite: CheckSuite) {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: MatrixSizePreference.key)
        defer {
            if let previous { defaults.set(previous, forKey: MatrixSizePreference.key) }
            else { defaults.removeObject(forKey: MatrixSizePreference.key) }
            GlyphMatrix.Metrics.pitch = MatrixSize.defaultPitch
        }

        let view = GlyphMatrixTextView(width: 900, isEditable: true)
        view.setNote(NSAttributedString(string: "a note worth reading at another size"))
        view.fit(width: 900, height: 400)
        let beforeWidth = GlyphMatrix.Metrics.cellWidth
        let beforeHeight = GlyphMatrix.Metrics.cellHeight

        defaults.set(MatrixSize.maximumPitch, forKey: MatrixSizePreference.key)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)

        suite.isTrue(GlyphMatrix.Metrics.pitch > MatrixSize.defaultPitch,
                     "a surface already on screen takes up a new text size")
        suite.isTrue(GlyphMatrix.Metrics.cellWidth > beforeWidth, "and its cells grow with it")
        suite.isTrue(GlyphMatrix.Metrics.cellHeight > beforeHeight, "and so do its lines")

        // The note itself is re-dressed in place: its ruler carries the new size, which is what
        // makes the lines and the caret land on the new grid.
        let ruler = view.textStorage?.attribute(.paragraphStyle, at: 0,
                                                effectiveRange: nil) as? NSParagraphStyle
        suite.equal(ruler?.minimumLineHeight, GlyphMatrix.Metrics.cellHeight,
                    "the note's ruler is re-dressed to the new size")
        let font = view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let advance = font.map { ("0" as NSString).size(withAttributes: [.font: $0]).width } ?? 0
        suite.isTrue(abs(advance - GlyphMatrix.Metrics.cellWidth) < 0.05,
                     "and the layout font's advance is the new cell width")
    }

    /// The note's dates in the middle of the bottom bar.
    @MainActor
    static func dateChecks(_ suite: CheckSuite) {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let earlier = now.addingTimeInterval(-3 * 24 * 3600)
        let older = now.addingTimeInterval(-400 * 24 * 3600)

        suite.equal(NoteDateView.dateText(for: nil, now: now), "—", "a note with no date shows a dash")
        suite.equal(NoteDateView.dateText(for: .distantPast, now: now), "—",
                    "a note with no date on disk shows a dash")

        let thisYear = NoteDateView.dateText(for: earlier, now: now)
        let year = Calendar.current.component(.year, from: earlier)
        suite.isTrue(!thisYear.isEmpty, "a note written this year has a date")
        suite.isTrue(!thisYear.contains(String(year)), "this year's date leaves the year out")

        let lastYear = NoteDateView.dateText(for: older, now: now)
        let oldYear = Calendar.current.component(.year, from: older)
        suite.isTrue(lastYear.contains(String(oldYear)), "an older date keeps its year")
        suite.isTrue(lastYear.count > thisYear.count, "an older date has more to say")

        let full = NoteDateView.fullText(for: earlier)
        suite.isTrue(full.contains(":"), "the full date gives a time of day")
        suite.isTrue(full.contains(String(year)), "the full date gives the year")
        suite.equal(NoteDateView.fullText(for: nil), "—", "a note with no date has no full form")
    }

    // MARK: - Effects

    // MARK: - Names, colours and full view

    /// The five colours a folder's or a note's name can be given, and where they are kept.
    ///
    /// A colour is the app's own note to itself: it never reaches the file, so a folder stays a
    /// folder and a note stays a note — which is the promise everything else here is built on.
    @MainActor
    static func labelColourChecks(_ suite: CheckSuite) {
        suite.equal(LabelColour.allCases.count, 5, "five colours to give a name")
        suite.equal(Set(LabelColour.allCases.map(\.label)).count, 5, "each colour is named once")
        suite.isTrue(LabelColour.allCases.allSatisfy { !$0.label.isEmpty },
                     "and every name is something to read")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FewNoteColours-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(directory: directory)
        let noteID = model.notes[0].id

        // The note the launch made is a draft until something is entered, and only a written
        // note carries its colour past a relaunch.
        model.textEdited("A note worth naming")
        model.saveNow()

        suite.equal(model.labelColour(forFolder: "Work"), nil, "a folder begins with no colour")
        suite.equal(model.labelColour(forNote: noteID), nil, "and so does a note")

        model.createFolder(named: "Work")
        model.setLabelColour(.pink, forFolder: "Work")
        model.setLabelColour(.blue, forNote: noteID)
        suite.equal(model.labelColour(forFolder: "Work"), .pink, "a folder keeps the colour it is given")
        suite.equal(model.labelColour(forNote: noteID), .blue, "and so does a note")

        // A rename changes the path a colour is filed under, so the colour has to move with it —
        // and so do the colours of everything inside it.
        model.createFolder(named: "Inner", in: "Work")
        model.setLabelColour(.green, forFolder: "Work/Inner")
        model.renameFolder("Work", to: "Studio")
        suite.equal(model.labelColour(forFolder: "Studio"), .pink, "a colour survives a rename")
        suite.equal(model.labelColour(forFolder: "Studio/Inner"), .green,
                    "and a folder inside it keeps its own")

        // Colours are read back with the rest of the state, so they are still there tomorrow.
        let reread = AppModel(directory: directory)
        suite.equal(reread.labelColour(forFolder: "Studio"), .pink, "colours come back at launch")
        suite.equal(reread.labelColour(forNote: noteID), .blue, "for folders and notes alike")

        // A colour belongs to a name that still exists: a folder that is gone takes its colour
        // with it, and a folder made later with the same name starts ordinary.
        model.setLabelColour(.green, forFolder: "Studio")
        model.setLabelColour(.blue, forNote: noteID)
        model.deleteFolder("Studio")
        suite.equal(model.labelColour(forFolder: "Studio"), nil, "a deleted folder's colour goes with it")
        suite.equal(model.createFolder(named: "Studio"), "Studio", "the name can be used again")
        suite.equal(model.labelColour(forFolder: "Studio"), nil, "and the recycled name begins ordinary")
        model.setLabelColour(.purple, forFolder: "Studio")

        model.setLabelColour(nil, forNote: noteID)
        suite.equal(model.labelColour(forNote: noteID), nil, "default puts a name back to ordinary")

        colourSweepChecks(suite)
        fullViewChecks(suite)
    }

    /// The sweep that keeps colours honest: a colour whose folder or note is gone does not
    /// survive the next reading of the library, however it got left behind.
    @MainActor
    static func colourSweepChecks(_ suite: CheckSuite) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FewNoteSweep-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = AppModel(directory: directory)
        model.createFolder(named: "Vestige")
        model.textEdited("A note of its own")
        model.saveNow()
        guard let note = model.notes.first(where: { !$0.isDraft }) else { return }

        // A state file that leaks: colours for names that are not in the library, as a library
        // can carry after its folders were deleted by hand outside the app.
        let state = """
        {"folderPath": "", "lastNoteID": null,
         "folderColours": {"Vestige": "green", "Ghost Folder": "orange"},
         "noteColours": {"\(note.id.uuidString)": "blue", "\(UUID().uuidString)": "pink"},
         "tidiedEmptyNotes": true}
        """
        try? state.write(to: directory.appending(path: "state.json"), atomically: true, encoding: .utf8)

        let reread = AppModel(directory: directory)
        suite.equal(reread.labelColour(forFolder: "Vestige"), .green, "a colour whose folder lives is kept")
        suite.equal(reread.labelColour(forFolder: "Ghost Folder"), nil,
                    "a colour whose folder is gone is swept")
        suite.equal(reread.labelColour(forNote: note.id), .blue,
                    "a note's colour is kept for the note that exists")
        suite.equal(reread.noteColours.count, 1, "and a colour for a note that is gone does not stay")
    }

    /// Full view: the list and the bar stand aside for the note, and come back as they were.
    @MainActor
    static func fullViewChecks(_ suite: CheckSuite) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FewNoteFullView-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(directory: directory)

        suite.isTrue(!model.isFullView, "the app opens in the ordinary view")
        model.showsSidebar = true
        model.toggleFullView()
        suite.isTrue(model.isFullView, "full view takes over")
        suite.isTrue(!model.showsSidebar, "and the note list stands aside")

        model.toggleFullView()
        suite.isTrue(!model.isFullView, "leaving full view")
        suite.isTrue(model.showsSidebar, "puts the list back exactly as it was")

        model.toggleFullView()
        model.showsSidebar = true
        suite.isTrue(!model.isFullView, "asking for the list is asking to leave full view")
    }


    // MARK: - Profile, picture and language

    /// The name the app calls the user, the note drawn as a picture, and the languages the
    /// interface ships in.
    @MainActor
    static func profileChecks(_ suite: CheckSuite) {
        // A name, or a pet name, for the greeting on the way in.
        suite.equal(UserNamePreference.greeting(for: ""), "Welcome to FewNote",
                    "with no name, the greeting is the plain welcome")
        suite.equal(UserNamePreference.greeting(for: "   "), "Welcome to FewNote",
                    "and it stays plain when the name is only spaces")
        suite.equal(UserNamePreference.greeting(for: "Momo"), "Hello, Momo",
                    "a name — or a pet name — is used by name")
        suite.equal(UserNamePreference.greeting(for: "  Momo  "), "Hello, Momo",
                    "a name is trimmed on the way in")

        let profileName = "FewNoteChecksProfile"
        let profileDefaults = UserDefaults(suiteName: profileName)!
        profileDefaults.removePersistentDomain(forName: profileName)
        suite.equal(UserNamePreference.stored(in: profileDefaults), "",
                    "there is no name to begin with")
        profileDefaults.set("Momo", forKey: UserNamePreference.key)
        suite.equal(UserNamePreference.stored(in: profileDefaults), "Momo", "a name is remembered")
        profileDefaults.set("  Momo  ", forKey: UserNamePreference.key)
        suite.equal(UserNamePreference.stored(in: profileDefaults), "Momo",
                    "and read back trimmed, however it was stored")
        profileDefaults.removePersistentDomain(forName: profileName)

        languageChecks(suite)
        pictureChecks(suite)
    }

    /// The languages the interface ships in, and the preference that picks one.
    @MainActor
    static func languageChecks(_ suite: CheckSuite) {
        suite.equal(AppLanguage.allCases.count, 8, "the Mac's own language and seven of FewNote's")
        suite.equal(AppLanguage.system.code, nil, "System follows the Mac")
        let codes = AppLanguage.allCases.compactMap(\.code)
        suite.equal(Set(codes).count, 7, "every language has a code of its own")
        suite.isTrue(codes.allSatisfy { $0.count == 2 }, "and they are all two-letter codes")
        suite.equal(Set(AppLanguage.allCases.map(\.label)).count, 8, "each is named once")
        // A language is listed in its own language, which is the name its reader is sure of.
        suite.equal(AppLanguage.spanish.label, "Español", "Spanish is listed in Spanish")
        suite.equal(AppLanguage.german.label, "Deutsch", "and German in German")

        let name = "FewNoteChecksLanguage"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        suite.equal(LanguagePreference.stored(in: defaults), .system,
                    "the interface follows the Mac to begin with")
        defaults.set(AppLanguage.french.rawValue, forKey: LanguagePreference.key)
        suite.equal(LanguagePreference.stored(in: defaults), .french, "a chosen language is read back")
        defaults.set("klingon", forKey: LanguagePreference.key)
        suite.equal(LanguagePreference.stored(in: defaults), .system,
                    "a language FewNote does not ship falls back to the Mac")

        // Applying the choice is what the system reads on the way in, and going back to System has
        // to drop the override rather than pin the app to whatever was chosen last.
        defaults.removeObject(forKey: "AppleLanguages")
        defaults.set(AppLanguage.german.rawValue, forKey: LanguagePreference.key)
        LanguagePreference.applyStored(in: defaults)
        suite.equal(defaults.persistentDomain(forName: name)?["AppleLanguages"] as? [String], ["de"],
                    "the choice is handed to the system")
        defaults.set(AppLanguage.system.rawValue, forKey: LanguagePreference.key)
        LanguagePreference.applyStored(in: defaults)
        // This suite's own domain, because with the override gone the Mac's languages show through.
        suite.isTrue(defaults.persistentDomain(forName: name)?["AppleLanguages"] == nil,
                     "and System drops the override")
        defaults.removePersistentDomain(forName: name)

        // The translation files themselves: seven of them, each covering every key the interface
        // uses, so no screen falls back to English by accident.
        let resources = URL(fileURLWithPath: #filePath)      // …/Sources/FewNoteChecks/ChecksMain.swift
            .deletingLastPathComponent()                     // …/Sources/FewNoteChecks
            .deletingLastPathComponent()                     // …/Sources
            .deletingLastPathComponent()                     // … (the package root)
            .appending(path: "Resources")

        guard let english = strings(at: resources, language: "en") else {
            suite.fail("the English base strings are there")
            return
        }
        let reference = Set(english.keys)
        suite.isTrue(reference.count >= 80, "the interface has a catalogue to translate (\(reference.count))")

        // Keys that sit in positions the extractor cannot see — a `LocalizedStringKey` parameter, a
        // word built beside its value rather than around it. They are listed here so that none of
        // them can quietly escape the catalogue and be the one English word left on a translated
        // screen.
        for key in ["Created", "Hello,", "New Note", "Note list", "Search",
                    "Typewriter", "Untitled", "Updated", "Welcome to FewNote"] {
            suite.isTrue(reference.contains(key), "the catalogue has \"\(key)\"")
        }

        for language in AppLanguage.allCases.compactMap(\.code) {
            guard let entries = strings(at: resources, language: language) else {
                suite.fail("\(language) ships a Localizable.strings")
                continue
            }
            let keys = Set(entries.keys)
            let missing = reference.subtracting(keys)
            suite.equal(missing.count, 0,
                        "\(language) covers every key (missing \(missing.count): \(missing.sorted().prefix(2).joined(separator: ", ")))")
            suite.equal(keys.count, reference.count, "\(language) adds nothing of its own")
            suite.isTrue(entries.allSatisfy { !$0.value.isEmpty }, "\(language) has no blank strings")

            // A file of English copied under another name is the failure worth catching: it would
            // look translated and read as English.
            guard language != "en" else { continue }
            let unchanged = entries.filter { key, value in english[key] == value && key.count > 3 }
            suite.isTrue(unchanged.count <= 20,
                         "\(language) is actually translated (\(unchanged.count) left in English)")
        }
    }

    /// Reads a `.strings` file into its keys and values.
    static func strings(at resources: URL, language: String) -> [String: String]? {
        let url = resources.appending(path: "\(language).lproj/Localizable.strings")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var entries: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\"") else { continue }   // a comment, or a blank line
            // The files are exactly `"key" = "value";`, so the quotes can be used as the split.
            let parts = trimmed.split(separator: "\"", omittingEmptySubsequences: false)
            guard parts.count >= 5 else { continue }
            entries[String(parts[1])] = String(parts[3])
        }
        return entries
    }

    /// A note drawn as a picture: the export that keeps the note's look.
    @MainActor
    static func pictureChecks(_ suite: CheckSuite) {
        let note = NSAttributedString(string: "A short note\nwith two lines")
        let dark = NSAppearance(named: .darkAqua)

        suite.equal(NoteImage.columns(for: note), 16,
                    "the picture is as wide as the note's longest line, plus room")
        suite.equal(NoteImage.columns(for: NSAttributedString(string: "")),
                    GlyphMatrix.Metrics.minimumColumns, "an empty note still gets a surface")
        suite.equal(NoteImage.columns(for: NSAttributedString(string: String(repeating: "w", count: 400))),
                    NoteImage.maximumColumns, "a very long line is wrapped rather than run off the edge")

        suite.equal(NoteImage.fileName(for: "Shopping list"), "Shopping list.png",
                    "the picture is named after the note")
        suite.equal(NoteImage.fileName(for: "   "), "Note.png", "a nameless note still gets a name")
        suite.equal(NoteImage.fileName(for: "a/b:c\nd"), "a-b-c.png",
                    "a title is made safe to be a file name")

        guard let data = NoteImage.pngData(of: note, tint: .chalk, appearance: dark) else {
            suite.fail("a note can be drawn as a picture")
            return
        }
        suite.isTrue(data.count > 2_000, "the picture has something in it (\(data.count) bytes)")
        // A PNG: the eight-byte signature, so the file is what it says it is.
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        suite.equal(Array(data.prefix(8)), signature, "and it really is a PNG")

        guard let narrow = NoteImage.bitmap(of: note, tint: .chalk, appearance: dark) else { return }
        suite.isTrue(narrow.pixelsWide > narrow.pixelsHigh, "a wide note makes a wide picture")
        // The card is a Retina picture: twice the points, so the dots are as sharp as on screen.
        let points = NoteImage.margin * 2 + CGFloat(16) * GlyphMatrix.Metrics.cellWidth
            + GlyphMatrix.Metrics.insetSize.width * 2
        suite.equal(narrow.pixelsWide, Int(points * 2), "the picture is drawn at twice the points")

        guard let wide = NoteImage.bitmap(of: NSAttributedString(string: String(repeating: "wide ", count: 12)),
                                          tint: .chalk, appearance: dark) else { return }
        suite.isTrue(wide.pixelsWide > narrow.pixelsWide, "a longer line makes a wider picture")

        guard let ember = NoteImage.bitmap(of: note, tint: .ember, appearance: dark) else { return }
        let chalkPNG = narrow.representation(using: .png, properties: [:])
        let emberPNG = ember.representation(using: .png, properties: [:])
        suite.isTrue(chalkPNG != emberPNG, "the picture is drawn in the note's own colour")

        // The theme is the note's own too: a picture of a light note comes out light. Without the
        // appearance being handed to the surface there is no window to take one from, and every
        // picture comes out in whichever theme the Mac happens to be in.
        guard let light = NoteImage.bitmap(of: note, tint: .chalk, appearance: NSAppearance(named: .aqua)) else {
            return
        }
        guard let darkCorner = narrow.colorAt(x: 20, y: narrow.pixelsHigh / 2)?.usingColorSpace(.deviceRGB),
              let lightCorner = light.colorAt(x: 20, y: light.pixelsHigh / 2)?.usingColorSpace(.deviceRGB) else { return }
        suite.isTrue(darkCorner.brightnessComponent < 0.4,
                     "a picture of a dark note has a dark card (\(darkCorner.brightnessComponent))")
        suite.isTrue(lightCorner.brightnessComponent > 0.6,
                     "and a picture of a light note has a light one (\(lightCorner.brightnessComponent))")
    }

    // MARK: - Folders

    /// Folders are directories and notes are files, so these checks are as much about the file
    /// system as about the model: a note that has been filed is a note that has moved.
    @MainActor
    static func folderChecks(_ suite: CheckSuite) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FewNoteFolders-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = AppModel(directory: directory)
        model.textEdited("Something to file")
        suite.equal(model.folders.count, 0, "a new library has no folders")
        suite.equal(model.folderChoice, .all, "and shows every note")

        // Making a folder does not take over the list: a folder made at the root is a sibling of
        // the last one, not a child of it, and the next file still goes where you were.
        suite.equal(model.createFolder(named: "Work"), "Work", "a folder is made")
        suite.equal(model.createFolder(named: "Work"), "Work 2", "a repeated name gets a number")
        suite.equal(model.folders.map(\.name), ["Work", "Work 2"], "both folders are listed")
        suite.equal(model.folderChoice, .all, "making a folder does not choose it")
        suite.equal(model.createFolder(named: "   "), nil, "a folder needs a name")
        suite.equal(AppModel.folderName("a/b:c"), "a-b-c", "a name is made safe to be a directory")

        // A note made with nothing chosen lands at the root, where a note with no folder lives.
        let before = model.selectedNoteID
        model.createNote()
        suite.isTrue(model.selectedNoteID != before, "a note is made")
        guard let rootNote = model.selectedNote else { return }
        suite.equal(model.folderPath(of: rootNote), "", "and lands at the top level")
        suite.isTrue(rootNote.created != .distantPast && rootNote.modified != .distantPast,
                     "with the dates it was made with")

        // Choosing a folder is what puts the next one inside it.
        model.folderChoice = .folder("Work 2")
        model.createNote()
        guard let id = model.selectedNoteID, let filed = model.selectedNote else { return }
        suite.equal(model.folderPath(of: filed), "Work 2", "a new note lands in the folder that is open")

        // A draft becomes a note when something is entered in it, which has to happen before it
        // can be filed: there is no file to move until there are words in it.
        model.textEdited("A note to be filed")

        // Filing a note moves the file itself.
        let origin = filed.url
        suite.isTrue(model.moveNote(id, toFolder: "Work"), "a note can be moved to another folder")
        guard let moved = model.selectedNote else { return }
        suite.equal(model.folderPath(of: moved), "Work", "and is filed there")
        suite.isTrue(!FileManager.default.fileExists(atPath: origin.path), "the file left the folder it was in")
        suite.isTrue(FileManager.default.fileExists(atPath: moved.url.path), "and is in the new one")
        suite.equal(model.noteCount(in: "Work"), 1, "the folder counts it")
        suite.equal(model.noteCount(in: "Work 2"), 0, "and the folder it left does not")
        suite.isTrue(!model.moveNote(id, toFolder: "Work"), "filing a note where it already is does nothing")
        suite.isTrue(!model.moveNote(id, toFolder: "Nowhere"), "a folder that is not there cannot take a note")

        // What the list shows follows the folder that is open.
        model.folderChoice = .folder("Work")
        suite.equal(model.listedNotes.count, 1, "the open folder lists its own notes")
        model.folderChoice = .folder("Work 2")
        suite.equal(model.listedNotes.count, 0, "an empty folder lists nothing")
        model.folderChoice = .all
        suite.equal(model.listedNotes.count, model.notes.count, "All Notes lists every note")

        // Renaming keeps the notes, and keeps their identities.
        suite.isTrue(model.renameFolder("Work", to: "Archive"), "a folder can be renamed")
        suite.equal(model.folders.map(\.name).sorted(), ["Archive", "Work 2"], "the new name is listed")
        guard let renamed = model.notes.first(where: { $0.id == id }) else { return }
        suite.equal(model.folderPath(of: renamed), "Archive", "the notes inside moved with it")
        suite.equal(model.noteCount(in: "Archive"), 1, "and are still counted")
        suite.isTrue(!model.renameFolder("Work", to: "Gone"), "renaming a folder that is not there does nothing")

        // A folder made by hand in the Finder is a folder like any other, however deep it sits.
        let nested = directory.appending(path: "Archive/2026", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        model.rescan()
        guard let nestedFolder = model.folders.first(where: { $0.id == "Archive/2026" }) else {
            suite.isTrue(false, "a nested folder is found")
            return
        }
        suite.equal(nestedFolder.name, "2026", "a nested folder is listed by its own name")
        suite.equal(nestedFolder.depth, 1, "and reads as nested")

        // Deleting a folder takes its notes to the trash with it.
        let notesBefore = model.notes.count
        model.deleteFolder("Archive")
        suite.isTrue(!model.folders.contains { $0.id.hasPrefix("Archive") }, "the folder is gone")
        suite.equal(model.notes.count, notesBefore - 1, "and its notes went with it")
        suite.isTrue(model.notes.count >= 1, "a library always keeps a note to write in")

        // A folder can be made inside another, and a folder can be dragged into another still.
        let choiceBefore = model.folderChoice
        suite.equal(model.createFolder(named: "Inner", in: "Work 2"), "Work 2/Inner",
                    "a folder is made inside another")
        suite.equal(model.folderChoice, choiceBefore, "and does not change where you are")
        guard let inner = model.folders.first(where: { $0.id == "Work 2/Inner" }) else {
            suite.isTrue(false, "the nested folder is listed")
            return
        }
        suite.equal(inner.depth, 1, "the nested folder reads as nested")
        suite.equal(inner.displayName, "Work 2 / Inner", "and is named with the way in")
        suite.isTrue(model.moveFolder("Work 2/Inner", into: ""), "a nested folder can move to the top")
        suite.isTrue(model.folders.contains { $0.id == "Inner" }, "and is listed there")
        suite.isTrue(!model.moveFolder("Inner", into: "Inner"), "a folder cannot be put inside itself")
        suite.equal(model.folders.first(where: { $0.id == "Inner" })?.displayName, "Inner",
                    "a top-level folder is named by its name alone")
        model.deleteFolder("Inner")

        // A note has no file name of its own — its title is its first line — so renaming a note
        // means rewriting that line, and nothing else.
        model.folderChoice = .all
        model.textEdited("Old title\nbody line")
        model.saveNow()
        guard let renameID = model.selectedNoteID else { return }
        suite.isTrue(model.renameNote(renameID, to: "New title"), "a note can be renamed")
        suite.equal(model.notes.first(where: { $0.id == renameID })?.title, "New title",
                    "the title follows the new first line")
        suite.equal(model.currentText, "New title\nbody line", "the rest of the note is untouched")
        suite.isTrue(!model.renameNote(renameID, to: "   "), "a note needs a name to be renamed")

        // The open folder is remembered between launches.
        model.folderChoice = .folder("Work 2")
        let reread = AppModel(directory: directory)
        suite.equal(reread.folderChoice, .folder("Work 2"), "the app comes back to the folder it was left on")
        suite.equal(reread.folders.map(\.name), ["Work 2"], "and to the folders it had")

        // Renaming the folder being looked at keeps the look on it: the grid does not go to a
        // path that is no longer there.
        suite.equal(model.createFolder(named: "Front"), "Front", "a folder to be renamed in place")
        model.browse("Front")
        model.renameFolder("Front", to: "Door")
        suite.equal(model.browsingFolder, "Door", "the folder being looked at follows its new name")
    }

    // MARK: - Drafts

    /// A note that has not been typed into is a draft: in the library's memory, never on disk.
    /// It becomes a file the moment words are entered, and an abandoned draft leaves nothing —
    /// which is why a library cannot fill up with empty notes.
    @MainActor
    static func draftChecks(_ suite: CheckSuite) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FewNoteDrafts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = AppModel(directory: directory)

        // An empty library is not written an empty note: it holds a draft, in memory only.
        suite.isTrue(model.notes.first?.isDraft ?? false, "a new library begins with a draft, not a file")
        suite.equal(model.listedNotes.count, 0, "the draft is not listed among the notes yet")
        suite.equal(model.noteCount(in: ""), 0, "and is not counted")
        if let url = model.notes.first?.url {
            suite.isTrue(!FileManager.default.fileExists(atPath: url.path), "and nothing is on disk")
        }

        // Entering something is what makes it a note.
        model.textEdited("Now there are words")
        model.saveNow()
        guard let written = model.notes.first else { return }
        suite.isTrue(!written.isDraft, "a draft typed into is a note")
        suite.isTrue(FileManager.default.fileExists(atPath: written.url.path), "and it lives on disk")
        suite.equal(model.listedNotes.count, 1, "and it is listed as any other")

        // A draft left without being typed into is dropped, not kept.
        model.createNote()
        guard let draftID = model.selectedNoteID else { return }
        suite.isTrue(model.notes.first(where: { $0.id == draftID })?.isDraft ?? false,
                     "a new note begins as a draft")
        suite.equal(model.listedNotes.count, 1, "and only the written one is listed")
        model.selectedNoteID = written.id
        suite.isTrue(!model.notes.contains { $0.id == draftID }, "leaving an untouched draft drops it")

        // Pressing new file twice cannot pile up empty notes: the one draft is replaced.
        model.createNote()
        model.createNote()
        guard let last = model.selectedNoteID else { return }
        suite.isTrue(model.notes.filter(\.isDraft).count == 1,
                     "a new file pressed twice still leaves a single draft")
        suite.isTrue(model.notes.first(where: { $0.id == last })?.isDraft ?? false,
                     "and the draft in hand is the newest one")

        // A draft deleted is dropped without a trip to the trash: there is no file to trash.
        let beforeTrash = try? FileManager.default.contentsOfDirectory(
            at: directory.appending(path: AppModel.trashFolderName), includingPropertiesForKeys: nil)
        model.deleteNote(last)
        let afterTrash = try? FileManager.default.contentsOfDirectory(
            at: directory.appending(path: AppModel.trashFolderName), includingPropertiesForKeys: nil)
        suite.equal(afterTrash?.count, beforeTrash?.count, "deleting a draft does not trash a file")
        suite.isTrue(!model.notes.contains { $0.id == last }, "and the draft is simply gone")
    }

    // MARK: - Search

    @MainActor
    static func searchChecks(_ suite: CheckSuite) {
        let text = "First line\nA recipe for café au lait\nLast line"
        suite.equal(Search.snippet(in: text, for: "recipe"), "A recipe for café au lait",
                    "the line the words are on is the snippet")
        suite.equal(Search.snippet(in: text, for: "CAFÉ"), "A recipe for café au lait",
                    "matching ignores case")
        suite.equal(Search.snippet(in: text, for: "cafe"), "A recipe for café au lait",
                    "matching ignores accents")
        suite.equal(Search.snippet(in: text, for: "lait"), "A recipe for café au lait",
                    "the words after the match are in the snippet too")
        suite.equal(Search.snippet(in: text, for: "nothing here"), nil, "a query that is not there finds nothing")
        suite.equal(Search.snippet(in: text, for: "   "), nil, "an empty query finds nothing")

        // A long line is clipped around the match rather than from the front.
        let long = String(repeating: "padding ", count: 40) + "needle" + String(repeating: " tail", count: 40)
        let clipped = Search.snippet(in: long, for: "needle")
        suite.isTrue(clipped.map { $0.count <= 100 } ?? false, "a long line is clipped to fit a row")
        suite.isTrue(clipped?.contains("needle") ?? false, "and the match is still in it")
        suite.isTrue(clipped?.hasPrefix("…") ?? false, "with the hidden beginning marked")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FewNoteSearch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = AppModel(directory: directory)
        model.textEdited("Shopping: coffee and milk")
        model.createNote()
        model.textEdited("A note about nothing in particular")
        model.createNote()
        model.textEdited("Bits and pieces")

        let byTitle = Search.hits(in: model.notes, query: "Shopping")
        suite.equal(byTitle.count, 1, "a note is found by its title")
        suite.isTrue(byTitle.first?.snippet != nil, "and the row can show the line it was found on")

        let byText = Search.hits(in: model.notes, query: "nothing in particular")
        suite.equal(byText.count, 1, "a note is found by what is written in it")
        suite.isTrue(byText.first?.note.title.contains("nothing") ?? false, "and it is the right note")
        suite.equal(Search.hits(in: model.notes, query: "SHOPPING").count, 1, "case does not matter here either")
        suite.equal(Search.hits(in: model.notes, query: "zzz").count, 0,
                    "a query nothing matches finds nothing")
        suite.equal(Search.hits(in: model.notes, query: "coffee").count, 1, "a word in one note finds one note")

        // The query drives the list: titles match at once, and the notes are read a moment later.
        model.search("Shopping")
        suite.isTrue(model.isSearching, "a query puts the list into search mode")
        suite.equal(model.searchHits.count, 1, "a title is matched before any note has been read")
        suite.isTrue(pump(until: { model.searchHits.first?.snippet != nil }),
                     "and the line it matched on follows")

        // Typing in the field and asking for a search are the same thing: the query is the switch.
        model.searchQuery = "coffee"
        suite.isTrue(pump(until: { model.searchHits.count == 1 && model.searchHits.first?.snippet != nil }),
                     "a word inside a note is found by typing the query")

        model.searchQuery = "not-a-word-anywhere"
        suite.isTrue(pump(until: { model.searchHits.isEmpty }), "a query that matches nothing leaves no hits")
        suite.isTrue(model.isSearching, "though the list is still in search mode")

        model.clearSearch()
        suite.isTrue(!model.isSearching, "clearing the search leaves search mode")
        suite.equal(model.searchHits.count, 0, "with nothing left over")
    }

    // MARK: - Library

    /// The things the note list does: keeping an empty note, trashing, and undoing.
    @MainActor
    static func libraryChecks(_ suite: CheckSuite) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FewNoteLibrary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = AppModel(directory: directory)
        suite.isTrue(!model.canCreateNote, "an empty note cannot be added to")
        suite.isTrue(model.lastDeleted == nil, "nothing has been deleted yet")

        model.textEdited("something worth keeping")
        model.saveNow()
        suite.isTrue(model.canCreateNote, "a note with writing in it can be added to")

        let firstID = model.selectedNoteID
        model.createNote()
        suite.equal(model.notes.count, 2, "a new note joins the library")
        suite.isTrue(!model.canCreateNote, "and the new, empty note cannot be added to either")
        _ = model.selectedNoteID

        guard let id = firstID else { return }
        model.deleteNote(id)
        suite.equal(model.notes.count, 1, "deleting removes the note")
        suite.equal(model.lastDeleted?.note.id, id, "the deletion is remembered")
        suite.equal(model.selectedNoteID, model.notes.first?.id, "selection falls back")

        let trash = directory.appendingPathComponent(AppModel.trashFolderName, isDirectory: true)
        let trashed = (try? FileManager.default.contentsOfDirectory(atPath: trash.path)) ?? []
        suite.equal(trashed.count, 1, "the deleted note is kept, not destroyed")

        model.undoDelete()
        suite.equal(model.notes.count, 1, "undo puts the note back, and the untyped draft beside it did not stay")
        suite.equal(model.selectedNoteID, id, "undo selects the note it brought back")
        suite.equal(model.notes.map(\.id), [id], "and puts it back where it was")
        let afterUndo = (try? FileManager.default.contentsOfDirectory(atPath: trash.path)) ?? []
        suite.equal(afterUndo.count, 0, "the note leaves the trash when it is restored")
        if let restored = model.notes.first(where: { $0.id == id }) {
            suite.equal(model.loadAttributed(for: restored).string, "something worth keeping",
                        "the restored note still has its writing")
        }

        // A note from the plain-text era opens, and is written again as rich text.
        let legacy = directory.appendingPathComponent("Note-\(UUID().uuidString).md")
        try? "old notes still open".write(to: legacy, atomically: true, encoding: .utf8)

        let reopened = AppModel(directory: directory)
        suite.isTrue(reopened.notes.contains { $0.url.pathExtension == "md" },
                     "a plain-text note is still listed")
        let legacyNote = reopened.notes.first { $0.url.pathExtension == "md" }
        suite.equal(legacyNote.map { reopened.loadAttributed(for: $0).string }, "old notes still open",
                    "a plain-text note opens as plain text")

        if let legacyNote {
            reopened.selectedNoteID = legacyNote.id
            reopened.textEdited("old notes still open, and styled")
            reopened.saveNow()
            suite.equal(reopened.selectedNote?.url.pathExtension, "rtf",
                        "a plain-text note becomes rich text when it is written again")
            suite.isTrue(!FileManager.default.fileExists(atPath: legacy.path),
                         "and the plain-text file is replaced, not duplicated")
            suite.equal(reopened.loadAttributed(for: reopened.selectedNote!).string,
                        "old notes still open, and styled",
                        "the upgraded note keeps its text")
        }

        // A deletion is registered with the window's undo stack, so ⌘Z takes the note back in its
        // turn with the typing.
        let undoDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FewNoteUndo-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: undoDirectory) }
        let undoModel = AppModel(directory: undoDirectory)
        let manager = UndoManager()
        manager.groupsByEvent = false
        undoModel.undoManager = manager
        undoModel.textEdited("worth taking back")
        undoModel.saveNow()
        guard let undoID = undoModel.selectedNoteID else { return }
        undoModel.createNote()
        undoModel.deleteNote(undoID)
        suite.equal(undoModel.notes.count, 1, "the deleted note leaves the list")
        suite.isTrue(manager.canUndo, "the deletion is on the undo stack")
        suite.equal(manager.undoActionName, "Delete Note", "and the undo is named for the menu")
        // Nothing else is running the run loop here, so close the group the registration opened
        // before taking the action back.
        while manager.groupingLevel > 0 { manager.endUndoGrouping() }
        manager.undo()
        suite.isTrue(undoModel.notes.contains { $0.id == undoID },
                     "and ⌘Z brings it back")
    }

    // MARK: - Pixels

    /// The colour of a point in a rendered bitmap. `scale` is pixels per point.
    @MainActor
    static func pixel(_ rep: NSBitmapImageRep, at point: CGPoint, scale: CGFloat) -> NSColor? {
        let x = Int((point.x * scale).rounded())
        let y = Int((point.y * scale).rounded())
        guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh else { return nil }
        return rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
    }

    /// Compares two colours channel by channel.
    static func closeEnough(_ lhs: NSColor?, _ rhs: NSColor?, tolerance: CGFloat) -> Bool {
        guard let lhs, let rhs else { return false }
        return abs(lhs.redComponent - rhs.redComponent) <= tolerance
            && abs(lhs.greenComponent - rhs.greenComponent) <= tolerance
            && abs(lhs.blueComponent - rhs.blueComponent) <= tolerance
    }

    static func describe(_ colour: NSColor?) -> String {
        guard let colour else { return "none" }
        return String(format: "(%.3f, %.3f, %.3f)",
                      colour.redComponent, colour.greenComponent, colour.blueComponent)
    }

    /// Relative luminance, for asking whether one surface is brighter than another.
    static func luminance(_ colour: NSColor?) -> Double {
        guard let colour = colour?.usingColorSpace(.deviceRGB) else { return -1 }
        return 0.2126 * Double(colour.redComponent)
            + 0.7152 * Double(colour.greenComponent)
            + 0.0722 * Double(colour.blueComponent)
    }

    /// Spins the run loop so an in-flight replay task can make progress.
    @MainActor
    static func pump(until condition: () -> Bool, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }
}

/// Minimal assertion collector: counts failures and prints a readable summary.
final class CheckSuite {
    private var passed = 0
    private var failures: [String] = []

    func isTrue(_ condition: Bool, _ label: String) {
        if condition { passed += 1 } else { fail(label) }
    }

    func equal<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
        if actual == expected {
            passed += 1
        } else {
            fail("\(label) — expected \(expected), got \(actual)")
        }
    }

    func notEqual<T: Equatable>(_ actual: T, _ other: T, _ label: String) {
        if actual != other { passed += 1 } else { fail("\(label) — values should differ") }
    }

    func fail(_ label: String) {
        failures.append(label)
    }

    /// Prints a summary and returns a process exit code.
    func report() -> Int32 {
        for failure in failures {
            print("✗ \(failure)")
        }
        if failures.isEmpty {
            print("✓ All \(passed) checks passed.")
            return 0
        }
        print("\n\(failures.count) of \(passed + failures.count) checks failed.")
        return 1
    }
}
