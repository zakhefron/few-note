import AppKit

/// A note drawn as a picture.
///
/// The picture is not a screenshot of the window: the note is drawn again, through the very same
/// matrix the editor draws on — so the dot field, the bloom, the text colour, the text size and
/// the theme are the note's own, and the picture is right at whatever size the note is set to.
/// What is left out is everything that is not the note: no window, no toolbar, no caret.
@MainActor
public enum NoteImage {

    /// How much room is left around the note, in points.
    public static let margin: CGFloat = 26
    /// The widest a picture is allowed to be, in cells. Past this a long note wraps, which is what
    /// keeps an exported note a note rather than a strip.
    public static let maximumColumns = 84

    // MARK: - Drawing

    /// Draws a note as a card: the matrix it is written on, with a margin around it.
    public static func bitmap(of note: NSAttributedString,
                              tint: GlyphTint,
                              appearance: NSAppearance? = nil) -> NSBitmapImageRep? {
        guard let resolved = appearance ?? NSApp?.effectiveAppearance ?? NSAppearance(named: .aqua) else {
            return nil
        }
        // The note is drawn as the app would draw it, so the theme in the picture is the theme on
        // the screen.
        var result: NSBitmapImageRep?
        resolved.performAsCurrentDrawingAppearance {
            result = draw(note: note, tint: tint, appearance: resolved)
        }
        return result
    }

    private static func draw(note: NSAttributedString,
                             tint: GlyphTint,
                             appearance: NSAppearance) -> NSBitmapImageRep? {

        // The note is laid out on a surface wide enough for its longest line, so the picture
        // hugs the writing instead of trailing off into empty dots.
        let width = CGFloat(columns(for: note)) * GlyphMatrix.Metrics.cellWidth
            + GlyphMatrix.Metrics.insetSize.width * 2

        let view = GlyphMatrixTextView(width: width, isEditable: false)
        // There is no window here for the surface to read its appearance from, so it is given one;
        // otherwise a picture of a light note would come out in whatever the Mac happens to be.
        view.drawingAppearance = appearance
        view.tint = tint
        view.setNote(note)
        // `fit` sizes the surface to the note: give it no height at all and it uses exactly what
        // the writing needs, which is what the picture should be.
        view.fit(width: width, height: 0)

        guard let noteRep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: noteRep)
        noteRep.size = view.bounds.size
        let noteImage = NSImage(size: view.bounds.size)
        noteImage.addRepresentation(noteRep)

        return card(noteImage, content: view.bounds.size, panel: view.matrixAppearance.panel)
    }

    /// The note's pixels mounted on a panel-coloured card with rounded corners and a hairline, so
    /// the picture stands on its own wherever it is pasted.
    private static func card(_ note: NSImage, content: NSSize, panel: NSColor) -> NSBitmapImageRep? {
        let size = NSSize(width: content.width + margin * 2, height: content.height + margin * 2)
        // Twice the points, as the screen is: an exported note is as sharp as the one it came from.
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((size.width * scale).rounded()),
            pixelsHigh: Int((size.height * scale).rounded()),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = size

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        let area = NSRect(origin: .zero, size: size)
        let radius: CGFloat = 18
        panel.setFill()
        NSBezierPath(roundedRect: area, xRadius: radius, yRadius: radius).fill()

        note.draw(in: NSRect(x: margin, y: margin, width: content.width, height: content.height))

        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        let border = NSBezierPath(roundedRect: area.insetBy(dx: 0.5, dy: 0.5),
                                  xRadius: radius, yRadius: radius)
        border.lineWidth = 1
        border.stroke()

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// The note as PNG data.
    public static func pngData(of note: NSAttributedString,
                               tint: GlyphTint,
                               appearance: NSAppearance? = nil) -> Data? {
        bitmap(of: note, tint: tint, appearance: appearance)?
            .representation(using: .png, properties: [:])
    }

    // MARK: - Saving

    /// Writes a note as a PNG. Returns whether anything was written.
    @discardableResult
    public static func writePNG(of note: NSAttributedString,
                                title: String,
                                tint: GlyphTint,
                                to url: URL,
                                appearance: NSAppearance? = nil) -> Bool {
        guard let data = pngData(of: note, tint: tint, appearance: appearance) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Asks where to put a picture of a note, and writes it there.
    ///
    /// The panel suggests the note's own name, so exporting a few notes in a row does not mean
    /// typing a name each time.
    public static func export(note: NSAttributedString,
                              title: String,
                              tint: GlyphTint,
                              appearance: NSAppearance? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = fileName(for: title)
        panel.title = String(localized: "Save Note as Image")
        panel.message = String(localized: "The note is drawn as a picture, exactly as it looks in FewNote.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writePNG(of: note, title: title, tint: tint, to: url, appearance: appearance)
    }

    /// A file name that is the note's title, made safe to be a file name.
    static func fileName(for title: String) -> String {
        let clean = title
            .components(separatedBy: .newlines).first?
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = clean.isEmpty ? "Note" : String(clean.prefix(60))
        return "\(name).png"
    }

    /// How many cells wide the picture should be: enough for the note's longest line, and no more
    /// than a note reads well at.
    static func columns(for note: NSAttributedString) -> Int {
        var longest = 0
        for line in note.string.components(separatedBy: .newlines) {
            longest = max(longest, (line as NSString).length)
        }
        // Two cells of breathing room, and a list wraps two cells in under its bullet.
        return min(maximumColumns, max(GlyphMatrix.Metrics.minimumColumns, longest + 2))
    }
}
