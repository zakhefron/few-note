import AppKit

/// The styling a single run of a note carries: how it is struck, and its colour.
///
/// The matrix draws with its own 5×8 face at a fixed pitch, so a style cannot live in the font —
/// every run has to keep the one layout font that makes the grid line up. Styles therefore live in
/// custom attributes while the note is being edited, and are translated to and from the standard
/// font/colour attributes when the note is written to or read from disk. That translation is the
/// only place the two worlds meet, which is what keeps the file openable anywhere else.
public enum NoteStyle {
    public static let styleKey = NSAttributedString.Key("FewNoteStyle")
    public static let tintKey = NSAttributedString.Key("FewNoteTint")
    public static let decorKey = NSAttributedString.Key("FewNoteDecor")

    /// The ways a run can be dressed past its strike: a line under it, and a line through it.
    /// Stored as one mask, because they are chosen independently and travel together.
    public struct Decoration: OptionSet, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let underline = Decoration(rawValue: 1)
        public static let strike = Decoration(rawValue: 2)
    }

    static func style(in attributes: [NSAttributedString.Key: Any]) -> GlyphFont.Style {
        (attributes[styleKey] as? String).flatMap(GlyphFont.Style.init(rawValue:)) ?? .regular
    }

    static func tint(in attributes: [NSAttributedString.Key: Any]) -> GlyphTint? {
        (attributes[tintKey] as? String).flatMap(GlyphTint.init(rawValue:))
    }

    static func decoration(in attributes: [NSAttributedString.Key: Any]) -> Decoration {
        (attributes[decorKey] as? Int).flatMap(Decoration.init(rawValue:)) ?? []
    }
}

/// Reads and writes notes: the matrix's attributes in memory, RTF on disk.
public enum NoteDocument {

    // MARK: - Carrier fonts

    /// The fonts used to carry a style through RTF. Courier is used because it has all four faces
    /// on every Mac, so a bold or italic run survives the file — and because it is only ever a
    /// carrier: the matrix never draws it.
    private static let regularCarrier = NSFont(name: "Courier", size: 12)
        ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let boldCarrier = NSFontManager.shared.convert(regularCarrier, toHaveTrait: .boldFontMask)
    private static let italicCarrier = NSFontManager.shared.convert(regularCarrier, toHaveTrait: .italicFontMask)
    private static let boldItalicCarrier = NSFontManager.shared.convert(boldCarrier, toHaveTrait: .italicFontMask)

    static func carrier(for style: GlyphFont.Style) -> NSFont {
        switch style {
        case .regular: return regularCarrier
        case .bold: return boldCarrier
        case .italic: return italicCarrier
        case .boldItalic: return boldItalicCarrier
        }
    }

    static func style(ofCarrier font: NSFont) -> GlyphFont.Style {
        let traits = NSFontManager.shared.traits(of: font)
        return GlyphFont.Style(bold: traits.contains(.boldFontMask),
                               italic: traits.contains(.italicFontMask))
    }

    // MARK: - Canvas attributes

    /// The attributes every run of an editable note carries: the one layout font, an invisible
    /// colour (the dots are drawn, not the text) and the matrix's line height.
    static func canvasAttributes(style: GlyphFont.Style = .regular,
                                 tint: GlyphTint? = nil,
                                 decor: NoteStyle.Decoration = []) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: GlyphMatrix.Metrics.layoutFont,
            .foregroundColor: NSColor.clear,
            .paragraphStyle: GlyphMatrix.paragraphStyle(),
            // Every character must take exactly one cell, so a glyph is never merged into another:
            // the drawing counts columns character by character.
            .ligature: 0
        ]
        if style != .regular { attributes[NoteStyle.styleKey] = style.rawValue }
        if let tint { attributes[NoteStyle.tintKey] = tint.rawValue }
        if !decor.isEmpty { attributes[NoteStyle.decorKey] = decor.rawValue }
        return attributes
    }

    public static func empty() -> NSAttributedString {
        NSAttributedString(string: "", attributes: canvasAttributes())
    }

    // MARK: - Reading

    /// Reads a note file, whatever era it was written in.
    ///
    /// RTF is parsed and its styles taken back out of the standard attributes; a plain-text note
    /// from the days before styling is read as it is, unstyled.
    public static func attributed(fromFileExtension pathExtension: String, data: Data) -> NSAttributedString {
        guard pathExtension.lowercased() == "rtf",
              let rich = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
              )
        else {
            let text = String(data: data, encoding: .utf8) ?? ""
            return NSAttributedString(string: text, attributes: canvasAttributes())
        }
        return canvas(from: rich)
    }

    /// The words in a note on disk, without its styling.
    ///
    /// Read through the same path the editor uses, so a search finds what you would see if you
    /// opened the note rather than the file's markup.
    public static func text(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return attributed(fromFileExtension: url.pathExtension, data: data).string
    }

    /// Re-dresses a document in the matrix's own attributes, keeping the styles it carries.
    ///
    /// Safe to apply to a document that is already dressed: a run's style is taken from the
    /// matrix's own attribute when it has one, and only read out of the font when it does not
    /// (which is the case for a file that has just been parsed).
    static func canvas(from document: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(string: document.string)
        let whole = NSRange(location: 0, length: (document.string as NSString).length)
        document.enumerateAttributes(in: whole, options: []) { attributes, range, _ in
            let carried = NoteStyle.style(in: attributes)
            let style = carried != .regular
                ? carried
                : attributes[.font].flatMap { ($0 as? NSFont).map(NoteDocument.style(ofCarrier:)) } ?? .regular
            let tint = NoteStyle.tint(in: attributes)
                ?? (attributes[.foregroundColor] as? NSColor).flatMap({ GlyphTint.matching($0) })
            // The mask this file already carries wins; past that the standard attributes a foreign
            // writer would have used carry the answer.
            var decor = NoteStyle.decoration(in: attributes)
            if let underlined = attributes[.underlineStyle] as? Int, underlined != 0 {
                decor.insert(.underline)
            }
            if let struck = attributes[.strikethroughStyle] as? Int, struck != 0 {
                decor.insert(.strike)
            }
            result.setAttributes(canvasAttributes(style: style, tint: tint, decor: decor),
                                 range: range)
        }
        applyRuler(to: result)
        return result
    }

    /// Puts a document in the matrix's ruler: the one layout font, and — line by line — the
    /// paragraph style a line needs, which is a hanging indent when it is a list item.
    ///
    /// Used both when a document is dressed for the first time and when the surface changes size,
    /// so there is exactly one place that decides how a line is laid out.
    static func applyRuler(to document: NSMutableAttributedString) {
        let length = document.length
        guard length > 0 else { return }

        document.addAttribute(.font, value: GlyphMatrix.Metrics.layoutFont,
                              range: NSRange(location: 0, length: length))

        let text = document.string as NSString
        var location = 0
        while location < length {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            let range = NSRange(location: line.location,
                                length: min(line.length, length - line.location))
            if range.length > 0 {
                let bulleted = NoteList.isBulletedLine(text, at: range.location)
                document.addAttribute(.paragraphStyle,
                                      value: GlyphMatrix.paragraphStyle(list: bulleted),
                                      range: range)
            }
            location = line.location + max(line.length, 1)
        }
    }

    // MARK: - Writing

    /// The RTF a note is stored as: the styles put back into the standard attributes the format
    /// understands, and the layout attributes left behind.
    public static func rtfData(for attributed: NSAttributedString) -> Data? {
        let document = NSMutableAttributedString(string: attributed.string)
        let whole = NSRange(location: 0, length: (attributed.string as NSString).length)
        attributed.enumerateAttributes(in: whole, options: []) { attributes, range, _ in
            var carried: [NSAttributedString.Key: Any] = [.font: carrier(for: NoteStyle.style(in: attributes))]
            if let tint = NoteStyle.tint(in: attributes) {
                // Always the light surface's version of the colour, so the file reads the same
                // whichever theme it was written in and can be matched back to the palette.
                carried[.foregroundColor] = tint.colour(darkMode: false)
            }
            let decor = NoteStyle.decoration(in: attributes)
            if decor.contains(.underline) {
                carried[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if decor.contains(.strike) {
                carried[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            document.setAttributes(carried, range: range)
        }
        return try? document.data(
            from: NSRange(location: 0, length: document.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}

/// Bulleted lines.
///
/// A list is a literal "• " at the start of the line rather than a paragraph style, so it is part
/// of the note's own text: it copies, pastes, exports and opens elsewhere like anything else, and
/// the matrix draws the bullet with every other character.
public enum NoteList {

    public static let bullet = "• "

    /// How far a wrapped list line is indented, in cells. The bullet is one cell wide and the
    /// space after it is another, so two cells puts the text of a wrapped line exactly under the
    /// text of the first one — a hanging indent, the way a list works in Notes.
    public static let indentCells = 2

    /// The length, in UTF-16 units, of the bullet at the start of a line, or zero when the line
    /// does not start with one.
    public static func bulletPrefix(of line: String) -> Int {
        line.hasPrefix(bullet) ? bullet.count : (line.hasPrefix("•") ? 1 : 0)
    }

    /// The same, for the line starting at `location` — read from the line itself, so a bullet with
    /// the space after it counts as both.
    public static func bulletPrefix(in text: NSString, at location: Int) -> Int {
        guard location >= 0, location < text.length else { return 0 }
        let length = min(bullet.count, text.length - location)
        return bulletPrefix(of: text.substring(with: NSRange(location: location, length: length)))
    }

    /// Whether the line starting at `location` is a list item.
    public static func isBulletedLine(_ text: NSString, at location: Int) -> Bool {
        bulletPrefix(in: text, at: location) > 0
    }

    /// Whether every line the range touches is already bulleted.
    public static func isBulleted(_ text: NSString, in range: NSRange) -> Bool {
        let lines = lineRanges(in: text, for: range)
        let content = lines
            .map { text.substring(with: NSRange(location: $0.location,
                                                length: min($0.length, text.length - $0.location))) }
            .filter { !$0.isEmpty }
        guard !content.isEmpty else { return false }
        return content.allSatisfy { $0.hasPrefix("•") }
    }

    /// The whole lines the range touches, in order. Called with a selection, this is the list of
    /// lines a control is about to work on.
    public static func lineRanges(in text: NSString, for range: NSRange) -> [NSRange] {
        let span = lineSpan(in: text, for: range)
        guard span.length > 0 else { return [] }

        var lines: [NSRange] = []
        var location = span.location
        while location < span.location + span.length {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            // `lineRange` clamps at the end of the text; stop if it cannot make progress.
            guard line.length > 0 || line.location + line.length > location else { break }
            lines.append(NSRange(location: line.location,
                                 length: min(line.length, text.length - line.location)))
            location = line.location + max(line.length, 1)
        }
        return lines
    }

    /// The whole lines the range touches, including their line endings.
    static func lineSpan(in text: NSString, for range: NSRange) -> NSRange {
        let length = text.length
        guard length > 0 else { return NSRange(location: 0, length: 0) }

        let start = min(max(range.location, 0), length)
        let end = min(max(range.location + range.length, start), length)

        let firstLine = text.lineRange(for: NSRange(location: min(start, length - 1), length: 0))
        let lastIndex = end > start ? end - 1 : start
        let lastLine = text.lineRange(for: NSRange(location: min(lastIndex, length - 1), length: 0))
        return NSRange(location: firstLine.location,
                       length: lastLine.location + lastLine.length - firstLine.location)
    }
}
