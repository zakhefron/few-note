import AppKit

/// The glyph matrix: the surface a note is written on.
///
/// A note is not a word-processing page here. The surface is a field of dots — the unlit dots of
/// a dot-matrix display — and every character is drawn into it as a pattern of lit dots taken
/// from `GlyphFont`. A replay types into that very same surface, so watching a note being typed
/// looks exactly like typing it. Everything in this file is shared by both, which is what keeps
/// them from ever drifting apart.
enum GlyphMatrix {

    // MARK: - Metrics

    /// The dot grid, the size of a character cell, and how many cells fit across.
    ///
    /// A cell is six dots wide (five for the character, one for the gap) and nine tall (eight for
    /// the character including its descender row, one for the line gap). The dots are spaced at
    /// 7/3 points, which makes a cell exactly 14 × 21 points — whole points at 1× and whole
    /// pixels at 2×, so the field stays crisp.
    struct Metrics: Equatable {
        let dotPitch: CGFloat
        let dotDiameter: CGFloat
        /// Set from the surface's width; everything else about the matrix is fixed.
        var columnCount: Int
        let inset: NSSize
        /// A monospaced font whose advance is exactly one cell.
        ///
        /// The text itself is never drawn — the dots are — but the text system still uses this
        /// font to lay out, wrap, select and place the caret, so matching the advance to the cell
        /// keeps all of that on the grid.
        let layoutFont: NSFont

        static let glyphColumns = GlyphFont.columns        // 5
        static let glyphRows = GlyphFont.rows              // 8
        static let gapColumns = 1
        static let gapRows = 1
        /// The first row under the glyph field, where an underline is drawn.
        static let glyphGapRowStart = glyphRows

        /// The dot spacing, set from the user's text-size choice before the surface is built.
        /// Everything else about the matrix is derived from it, and the editor and a replay both
        /// read the same value, so they can never disagree about the grid.
        static var pitch: CGFloat = MatrixSize.defaultPitch

        /// The dot is a fixed fraction of the pitch, so a bigger matrix is a scaled-up matrix
        /// rather than a sparser one.
        static var diameter: CGFloat { pitch * (1.6 / MatrixSize.defaultPitch) }

        static let minimumColumns = 12
        static let maximumColumns = 300

        static var cellWidth: CGFloat { CGFloat(glyphColumns + gapColumns) * pitch }
        static var cellHeight: CGFloat { CGFloat(glyphRows + gapRows) * pitch }
        /// One cell of margin, so the first character is not glued to the window edge.
        static var insetSize: NSSize { NSSize(width: cellWidth, height: cellHeight) }

        init(width: CGFloat) {
            self.dotPitch = Self.pitch
            self.dotDiameter = Self.diameter
            self.inset = Self.insetSize
            self.layoutFont = Self.layoutFont
            self.columnCount = Self.columns(forWidth: width, inset: Self.insetSize)
        }

        /// How many whole cells fit across `width`. Shared by the editor and the replay.
        static func columns(forWidth width: CGFloat, inset: NSSize) -> Int {
            let usable = width - inset.width * 2
            return min(maximumColumns, max(minimumColumns, Int(usable / cellWidth)))
        }

        /// The width the text container is pinned to: a whole number of cells, so a line wraps
        /// exactly on the matrix's right edge.
        var contentWidth: CGFloat { CGFloat(columnCount) * Self.cellWidth }

        /// The ruler font for the current pitch, cached because it is asked for on every layout
        /// and every note load.
        static var layoutFont: NSFont {
            if let cachedLayoutFont, cachedLayoutFont.width == cellWidth { return cachedLayoutFont.font }
            let font = font(matching: cellWidth)
            cachedLayoutFont = (cellWidth, font)
            return font
        }

        private static var cachedLayoutFont: (width: CGFloat, font: NSFont)?

        /// Finds the monospaced size whose advance is the cell width, by fixed-point iteration.
        private static func font(matching width: CGFloat) -> NSFont {
            var size = width / 0.6
            for _ in 0..<6 {
                let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
                let advance = ("0" as NSString).size(withAttributes: [.font: font]).width
                guard advance > 0 else { break }
                size *= width / advance
            }
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    /// The line height the text system lays a matrix line out at: exactly one cell, so a wrapped
    /// line sits on the row below with no gap and no overlap.
    ///
    /// A bulleted line hangs, exactly the way a list does in Notes: the bullet sits at the left
    /// margin and everything that wraps under it lines up two cells in, which is where the text
    /// after the bullet begins.
    static func paragraphStyle(list: Bool = false) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Metrics.cellHeight
        paragraph.maximumLineHeight = Metrics.cellHeight
        paragraph.lineSpacing = 0
        paragraph.paragraphSpacing = 0
        paragraph.firstLineHeadIndent = 0
        paragraph.headIndent = list ? CGFloat(NoteList.indentCells) * Metrics.cellWidth : 0
        return paragraph
    }

    // MARK: - Appearance

    /// The matrix's colours, resolved from the effective appearance so the surface follows the app
    /// theme (Light / Dark / System) along with everything else.
    struct Appearance: Equatable {
        /// Behind the dots.
        var panel: NSColor
        /// An unlit dot — the field every character is drawn on.
        var field: NSColor
        /// A lit dot — the characters themselves.
        var glyph: NSColor
        var caret: NSColor
        /// The bloom behind the lit dots. `nil` draws the dots with no glow at all.
        var glow: Glow?
        /// Whether this is the dark surface, which decides how a palette colour resolves.
        var darkSurface: Bool

        /// A glow is a blurred copy of the dots behind them, in the same colour.
        struct Glow: Equatable {
            var colour: NSColor
            /// A tight, bright pass right at the strokes…
            var innerBlur: CGFloat
            var innerAlpha: CGFloat
            /// …and a wide, faint one for the falloff.
            var outerBlur: CGFloat
            var outerAlpha: CGFloat
        }

        /// The same surface, drawing in another colour. Used for the runs of a note that carry
        /// their own colour: they bloom in that colour too.
        func painting(in colour: NSColor) -> Appearance {
            var copy = self
            copy.glyph = colour
            copy.glow?.colour = colour
            return copy
        }

        /// Resolves the surface's colours for an appearance and a chosen text colour.
        ///
        /// The glow is stronger on the dark surface, where the characters really are light
        /// sources, and restrained on the light one, where a bloom would only smudge the ink.
        static func resolve(_ appearance: NSAppearance?, tint: GlyphTint = .chalk) -> Appearance {
            let isDark = appearance?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let colour = tint.colour(darkMode: isDark)
            return isDark
                ? Appearance(panel: NSColor(calibratedWhite: 0.06, alpha: 1),
                             field: NSColor(calibratedWhite: 1, alpha: 0.20),
                             glyph: colour,
                             caret: colour,
                             glow: Glow(colour: colour,
                                        innerBlur: 8, innerAlpha: 0.75,
                                        outerBlur: 22, outerAlpha: 0.34),
                             darkSurface: true)
                : Appearance(panel: NSColor(calibratedWhite: 0.985, alpha: 1),
                             field: NSColor(calibratedWhite: 0, alpha: 0.16),
                             glyph: colour,
                             caret: colour,
                             glow: Glow(colour: colour,
                                        innerBlur: 5, innerAlpha: 0.26,
                                        outerBlur: 11, outerAlpha: 0.12),
                             darkSurface: false)
        }
    }

    // MARK: - Cells

    /// Where a cell's top-left corner is, in view coordinates.
    static func cellOrigin(column: Int, row: Int, origin: NSPoint, metrics: Metrics) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(column) * Metrics.cellWidth,
                y: origin.y + CGFloat(row) * Metrics.cellHeight)
    }

    /// The rect of a cell, which is also the size of the caret.
    static func cellRect(column: Int, row: Int, origin: NSPoint, metrics: Metrics) -> NSRect {
        NSRect(origin: cellOrigin(column: column, row: row, origin: origin, metrics: metrics),
               size: NSSize(width: Metrics.cellWidth, height: Metrics.cellHeight))
    }

    /// The centre of one dot within a cell. `column` is fractional so an italic glyph can lean.
    static func dotCentre(column: Double, row: Int, cell: CGPoint, metrics: Metrics) -> CGPoint {
        CGPoint(x: cell.x + (CGFloat(column) + 0.5) * metrics.dotPitch,
                y: cell.y + (CGFloat(row) + 0.5) * metrics.dotPitch)
    }

    static func dotCentre(column: Int, row: Int, cell: CGPoint, metrics: Metrics) -> CGPoint {
        dotCentre(column: Double(column), row: row, cell: cell, metrics: metrics)
    }

    /// The matrix's pixels are square, the way the pixels of a real dot-matrix display are.
    ///
    /// They are drawn as small rectangles rather than circles for the simplest possible reason:
    /// rounding twenty-four thousand tiny circles costs about sixty-five milliseconds, and the
    /// same number of squares costs two. That is the difference between a surface that can be
    /// redrawn on every keystroke and one that cannot. The squares are very slightly smaller than
    /// the circle they replace, so a character keeps the weight it always had.
    static let pixel = 0.92

    private static func addDot(at centre: CGPoint, diameter: CGFloat, into path: CGMutablePath) {
        let side = diameter * pixel
        path.addRect(CGRect(x: centre.x - side / 2, y: centre.y - side / 2,
                            width: side, height: side))
    }

    /// The ink a style is struck with: a bold dot is fatter, which is what makes a bold stroke
    /// read as one solid line rather than as a denser row of dots.
    static func ink(for style: GlyphFont.Style, metrics: Metrics) -> CGFloat {
        metrics.dotDiameter * (style.isBold ? GlyphFont.boldInk : 1)
    }

    /// Adds one character's lit dots, drawn into the cell at `cell`.
    ///
    /// `scale` shrinks or grows the dots about their own centres, which is how a growing arrival
    /// is drawn — the cell does not move, only the light in it.
    static func addDots(for character: Character,
                        style: GlyphFont.Style = .regular,
                        inCell cell: CGPoint,
                        metrics: Metrics,
                        scale: CGFloat = 1,
                        decor: NoteStyle.Decoration = [],
                        into path: CGMutablePath) {
        let diameter = ink(for: style, metrics: metrics) * scale
        for dot in GlyphFont.placedDots(for: character, style: style) {
            addDot(at: dotCentre(column: dot.column, row: dot.row, cell: cell, metrics: metrics),
                   diameter: diameter, into: path)
        }
        // A struck-through run draws the line through the x-height's middle row, an underlined
        // run draws theirs in the row under the glyphs; both end-to-end across the cell, gaps
        // included, so the letters join into one line rather than dashing at every cell edge.
        for decorRow in decorRows(metrics: metrics, for: decor) {
            for column in 0..<(GlyphFont.columns + Metrics.gapColumns) {
                addDot(at: dotCentre(column: column, row: decorRow, cell: cell, metrics: metrics),
                       diameter: diameter, into: path)
            }
        }
    }

    /// The cell rows a decoration covers: the x-height's middle, and the first gap row below
    /// the glyphs — under the descenders, where a typewriter's underline actually sits.
    static func decorRows(metrics: Metrics, for decor: NoteStyle.Decoration) -> [Int] {
        var rows: [Int] = []
        if decor.contains(.strike) { rows.append(3) }
        if decor.contains(.underline) { rows.append(Metrics.glyphGapRowStart) }
        return rows
    }

    /// Adds every dot of a cell — the whole field square, lit or not.
    static func addFieldDots(inCell cell: CGPoint, metrics: Metrics, into path: CGMutablePath) {
        for row in 0..<(Metrics.glyphRows + Metrics.gapRows) {
            for column in 0..<(Metrics.glyphColumns + Metrics.gapColumns) {
                addDot(at: dotCentre(column: column, row: row, cell: cell, metrics: metrics),
                       diameter: metrics.dotDiameter, into: path)
            }
        }
    }

    // MARK: - Drawing

    /// Builds the tile the dot field is drawn from: one cell's worth of dots.
    ///
    /// The empty matrix is tens of thousands of dots, which is far too many to stroke one at a
    /// time every frame. One tile plus a tiled fill draws the whole field in a single operation.
    static func fieldTile(metrics: Metrics, appearance: Appearance, scale: CGFloat) -> CGImage? {
        let width = Int((Metrics.cellWidth * scale).rounded())
        let height = Int((Metrics.cellHeight * scale).rounded())
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        context.scaleBy(x: scale, y: scale)
        context.setFillColor(appearance.field.cgColor)
        let path = CGMutablePath()
        addFieldDots(inCell: .zero, metrics: metrics, into: path)
        context.addPath(path)
        context.fillPath()
        return context.makeImage()
    }

    /// Fills the field of dots across the surface.
    ///
    /// The fill is a repeating pattern anchored at the view's origin, so the field stays in phase
    /// with the cell grid — and stays put while the note scrolls — no matter which part of it is
    /// being redrawn.
    static func drawField(in rect: NSRect, metrics: Metrics, colour: NSColor?) {
        guard let colour else { return }
        colour.setFill()
        rect.fill()
    }

    /// How many device pixels the context draws per point.
    static func deviceScale(of context: CGContext) -> CGFloat {
        let scale = abs(context.ctm.a)
        guard scale.isFinite, scale > 0 else { return 1 }
        return min(4, max(1, (scale * 10).rounded() / 10))
    }

    

    /// Paints only the bloom, leaving the dots to be drawn at full resolution on top.
    ///
    /// A shadow always arrives with the shape it belongs to, so the shape is sent far out of the
    /// picture and its shadow left behind: the path is drawn a long way off to the left, with a
    /// shadow offset that brings the shadow back to where the path really is.
    static func fillGlow(_ path: CGPath, appearance: Appearance, into context: CGContext) {
        guard let glow = appearance.glow else { return }

        let away = 100_000.0
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: -away, y: 0)

        context.setShadow(offset: CGSize(width: away, height: 0),
                          blur: glow.innerBlur,
                          color: glow.colour.withAlphaComponent(glow.innerAlpha).cgColor)
        context.addPath(path)
        context.fillPath()

        context.setShadow(offset: CGSize(width: away, height: 0),
                          blur: glow.outerBlur,
                          color: glow.colour.withAlphaComponent(glow.outerAlpha).cgColor)
        context.addPath(path)
        context.fillPath()
    }

    /// Paints the lit dots on their own, with no bloom: the bloom comes from a layer of its own.
    static func fillDots(_ path: CGPath, colour: NSColor, into context: CGContext) {
        context.setFillColor(colour.cgColor)
        context.addPath(path)
        context.fillPath()
    }
}

// MARK: - The matrix text view

/// A layout manager that never draws text glyphs. Every character is drawn as dots by
/// `drawLitDots` instead, so digits (or any text with a visible foreground colour) cannot
/// render as glyphs on top of the dot matrix.
final class SilentLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
        // Intentionally empty: drawLitDots paints the matrix instead.
    }
}

/// An `NSTextView` that draws the glyph matrix instead of text.
///
/// The text itself is kept (and laid out) by AppKit, but its colour is clear: every character the
/// user types is drawn by this view as lit dots on the dot field, so a note reads as a
/// dot-matrix display rather than as small text. Undo, selection, find, spell checking and
/// copy/paste all keep working, because underneath it is still a real text view.
final class GlyphMatrixTextView: NSTextView {

    typealias Metrics = GlyphMatrix.Metrics
    typealias Appearance = GlyphMatrix.Appearance

    private(set) var metrics: Metrics
    private var palette: Appearance

    /// The colour the characters are drawn in, and the colour they glow.
    var tint: GlyphTint = .chalk {
        didSet {
            guard tint != oldValue else { return }
            applyAppearance()
            needsDisplay = true
        }
    }

    /// Whether the matrix paints a caret of its own. A replay surface is read-only and has no
    /// insertion point, so it parks the caret after the last glyph it has typed.
    var showsCaretCell = false {
        didSet {
            guard showsCaretCell != oldValue else { return }
            updateBlinkTimer()
            needsDisplay = true
        }
    }

    private var fieldColour: NSColor?
    private var fieldColourKey: String?
    private var blinkTimer: Timer?
    private var caretOn = true
    private var lastCaretCell: NSRect?

    /// Guards `restyleLine` against re-entering itself: writing a paragraph style back into the
    /// storage can bring us straight back here.
    private var isRestyling = false

    /// The style the next typed characters are struck in, shown by the Bold and Italic controls.
    /// With a selection, those controls restyle the selection instead.
    private(set) var typingStyle: GlyphFont.Style = .regular

    /// What the next typed characters carry past their strike: underline, strikethrough.
    private(set) var typingDecor: NoteStyle.Decoration = []

    /// The appearance to draw in when there is no window to take one from — a note being rendered
    /// as a picture, say. Nil in the editor, which follows the window and the app's own theme.
    var drawingAppearance: NSAppearance? {
        didSet {
            guard drawingAppearance !== oldValue else { return }
            applyAppearance()
            needsDisplay = true
        }
    }

    /// How much of the note is lit. Nil means all of it, which is what the editor wants; a replay
    /// sets it so only the part struck so far is drawn.
    private(set) var litCount: Int?

    /// The note this surface is holding, by identity, so a replay that hands over the same note
    /// again is not read a second time.
    private weak var heldNote: NSAttributedString?

    init(width: CGFloat, isEditable: Bool) {
        self.metrics = Metrics(width: width)
        self.palette = Appearance.resolve(nil, tint: .chalk)

        // The text system is built here rather than left to `NSTextView`, so the container is
        // pinned to whole cells from the first layout onwards.
        let storage = NSTextStorage()
        let layoutManager = SilentLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                     height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        layoutManager.addTextContainer(container)

        super.init(frame: .zero, textContainer: container)
        configure(isEditable: isEditable)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sizePreferenceChanged),
                                               name: UserDefaults.didChangeNotification,
                                               object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("GlyphMatrixTextView is created in code")
    }

    deinit {
        blinkTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    var columnCount: Int { metrics.columnCount }

    /// The colours currently in use, readable so a check can compare them with what was drawn.
    var matrixAppearance: Appearance { palette }

    // MARK: Configuration

    private func configure(isEditable: Bool) {
        isRichText = false
        allowsUndo = isEditable
        self.isEditable = isEditable
        isSelectable = isEditable
        usesFindBar = isEditable
        isIncrementalSearchingEnabled = isEditable

        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = []
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        drawsBackground = true
        applyAppearance()

        // A selection is drawn by the text system, and it would draw the characters themselves as
        // text on top of the dots. Naming the foreground colour here keeps a selection reading as
        // the same matrix it is when it is not selected — only the highlight changes.
        selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor,
            .foregroundColor: NSColor.clear
        ]

        // Keep the text exactly as typed: no smart quotes/dashes/substitutions.
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = isEditable
        smartInsertDeleteEnabled = false

        // The layout font is only a ruler: its advance is one cell wide and its lines are pinned
        // to one cell tall, so wrapping, selection and the caret all land on the matrix.
        font = metrics.layoutFont
        textContainerInset = metrics.inset
        // Padding would push the first character off the first cell.
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = false
        textContainer?.heightTracksTextView = false

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Metrics.cellHeight
        paragraph.maximumLineHeight = Metrics.cellHeight
        paragraph.lineSpacing = 0
        paragraph.paragraphSpacing = 0
        defaultParagraphStyle = paragraph
        refreshTypingAttributes()
    }

    /// Rebuilds the attributes the next typed character will carry: the layout ruler, an invisible
    /// colour (the dots are drawn, not the text) and the style the controls are showing.
    func refreshTypingAttributes() {
        typingAttributes = NoteDocument.canvasAttributes(style: typingStyle, decor: typingDecor)
    }

    // MARK: Metrics

    /// Re-derives the column count from a new width. Called when the surface is resized, so the
    /// matrix always fills the available area with whole cells.
    @discardableResult
    func updateMetrics(forWidth width: CGFloat) -> Bool {
        let columns = Metrics.columns(forWidth: width, inset: metrics.inset)
        let columnsChanged = columns != metrics.columnCount
        // Re-applying the container size invalidates layout, so only do it when the pinned width
        // really is different — resizing, not every keystroke.
        let widthIsStale = textContainer.map { $0.containerSize.width != metrics.contentWidth } ?? true
        guard columnsChanged || widthIsStale else { return false }
        metrics.columnCount = columns
        applyContainerSize()
        return columnsChanged
    }

    private func applyContainerSize() {
        guard let textContainer else { return }
        textContainer.containerSize = NSSize(width: metrics.contentWidth, height: .greatestFiniteMagnitude)
        textContainer.widthTracksTextView = false
        let width = metrics.inset.width * 2 + metrics.contentWidth
        minSize = NSSize(width: width, height: 0)
        maxSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        var frame = self.frame
        frame.size.width = width
        self.frame = frame
        needsDisplay = true
    }

    /// Sizes the surface so the field covers the whole visible area even for a short note, and
    /// grows with the text when there is more of it than fits.
    func fit(width: CGFloat, height: CGFloat) {
        // A change of text size is a change of pitch, which rebuilds the whole grid.
        if abs(metrics.dotPitch - Metrics.pitch) > 0.0001 {
            applyPitch(Metrics.pitch, width: width)
        }
        updateMetrics(forWidth: width)

        var usedHeight: CGFloat = 0
        if let layoutManager, let textContainer {
            layoutManager.ensureLayout(for: textContainer)
            usedHeight = layoutManager.usedRect(for: textContainer).height
        }

        let target = NSRect(x: 0,
                            y: 0,
                            width: metrics.inset.width * 2 + metrics.contentWidth,
                            height: max(usedHeight + metrics.inset.height * 2, height))
        if frame != target { frame = target }
    }

    /// Rebuilds the grid at a new dot spacing. The note keeps its text and its styles; only the
    /// ruler it is laid out with changes.
    private func applyPitch(_ pitch: CGFloat, width: CGFloat) {
        metrics = Metrics(width: width)
        font = metrics.layoutFont
        textContainerInset = metrics.inset
        defaultParagraphStyle = GlyphMatrix.paragraphStyle()
        refreshTypingAttributes()
        applyContainerSize()
        // Every run is re-dressed in the new ruler in place — the note is never copied, so a drag
        // of the size slider stays smooth however long the note is.
        if let textStorage, textStorage.length > 0 {
            textStorage.beginEditing()
            NoteDocument.applyRuler(to: textStorage)
            textStorage.endEditing()
        }
        fieldColour = nil
        fieldColourKey = nil
        needsDisplay = true
    }

    /// The text size is one shared preference, and dragging its slider has to change the surface
    /// on the frame it happens on. Watching the preference here means the surface re-draws at the
    /// new size directly, rather than waiting for whichever view happens to own the slider to be
    /// rebuilt.
    @objc private func sizePreferenceChanged() {
        let stored = MatrixSize.stored()
        // The size this surface is drawn at, not the shared one: with more than one surface on
        // screen the first to hear the change settles the shared value, and the rest would then
        // think there was nothing to do and keep the old grid.
        guard abs(CGFloat(stored) - metrics.dotPitch) > 0.0001 else { return }
        Metrics.pitch = CGFloat(stored)
        let available = enclosingScrollView?.contentSize.width ?? bounds.width
        guard available > 0 else { return }
        applyPitch(CGFloat(stored), width: available)
        fit(width: available, height: enclosingScrollView?.contentSize.height ?? bounds.height)
    }

    // MARK: Appearance

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
        needsDisplay = true
    }

    private func applyAppearance() {
        palette = Appearance.resolve(drawingAppearance ?? effectiveAppearance, tint: tint)
        backgroundColor = palette.panel
        // The characters are drawn as dots, never as text. Clear the default colour so any run
        // that carries a visible foreground colour (pasted text, imported RTF, digits) does not
        // render as glyphs on top of the matrix.
        textColor = .clear
        insertionPointColor = palette.caret
        typingAttributes[.foregroundColor] = NSColor.clear
        fieldColour = nil
        fieldColourKey = nil
        clearForegroundColours()
    }

    /// Ensures no attributed run carries a visible foreground colour: every character is drawn
    /// as dots, so the underlying text must stay invisible. Called whenever the surface is
    /// styled or the text changes (typing, paste, import).
    private func clearForegroundColours() {
        guard let textStorage, textStorage.length > 0 else { return }
        let whole = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttributes(in: whole, options: []) { attributes, range, _ in
            if let color = attributes[.foregroundColor] as? NSColor, color.alphaComponent > 0 {
                textStorage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
            }
        }
    }

    /// The dot field as a repeating pattern colour, built once per appearance, text size and
    /// device scale.
    private func fieldColour(for scale: CGFloat) -> NSColor? {
        let key = "\(scale)-\(metrics.dotPitch)-\(palette)"
        if let fieldColour, fieldColourKey == key { return fieldColour }
        guard let tile = GlyphMatrix.fieldTile(metrics: metrics, appearance: palette, scale: scale) else { return nil }

        // The tile is a bitmap, so give it its size in points: 14 × 21 at 2× is a 28 × 42 pixel
        // image, and the pattern then repeats every 14 × 21 points.
        let rep = NSBitmapImageRep(cgImage: tile)
        rep.size = NSSize(width: Metrics.cellWidth, height: Metrics.cellHeight)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)

        let colour = NSColor(patternImage: image)
        fieldColour = colour
        fieldColourKey = key
        return colour
    }

    // MARK: Text

    /// Replaces the whole note, styling and all. Used when a different note is opened.
    func setNote(_ attributed: NSAttributedString) {
        guard let textStorage else { return }
        textStorage.setAttributedString(NoteDocument.canvas(from: attributed))
        // Everything is lit: this is the editor, not a replay.
        litCount = nil
        heldNote = nil
        refreshCaretCell()
        needsDisplay = true
        clearForegroundColours()
    }

    /// Shows a note being struck out: everything up to `count` is lit, and nothing after it is
    /// drawn.
    ///
    /// The whole note is held — not a prefix — so the lines ahead still take their places and the
    /// text never reflows as it is struck. Only what has changed is invalidated, so a long note
    /// still costs nothing per frame.
    func reveal(_ note: NSAttributedString, upTo count: Int) {
        guard let textStorage else { return }
        let target = min(max(count, 0), note.length)
        let previous = litCount ?? textStorage.length

        if heldNote !== note || textStorage.length != note.length {
            textStorage.setAttributedString(NoteDocument.canvas(from: note))
            heldNote = note
            litCount = target
            refreshCaretCell()
            needsDisplay = true
            return
        }

        litCount = target
        refreshCaretCell()

        if target < previous {
            // A rewind — a new replay, or one that has been stopped — clears what was there.
            needsDisplay = true
            return
        }

        // Invalidate only what has just been lit, so a frame costs what it revealed.
        invalidate(charactersIn: NSRange(location: previous, length: max(0, target - previous)))
    }

    /// Convenience for callers that only have the text.
    func reveal(_ text: String) {
        reveal(NSAttributedString(string: text, attributes: NoteDocument.canvasAttributes()),
               upTo: (text as NSString).length)
    }

    // MARK: Caret

    /// Where the caret sits, snapped to the matrix. `index` is an insertion point: the caret cell
    /// is the cell holding the character after it, or the empty cell past the last character.
    func caretCell(forInsertionAt index: Int) -> NSRect? {
        let cell = caretCellCoordinates(forInsertionAt: index)
        return cell.map { GlyphMatrix.cellRect(column: $0.column, row: $0.row, origin: textContainerOrigin, metrics: metrics) }
    }

    private func caretCellCoordinates(forInsertionAt index: Int) -> (column: Int, row: Int)? {
        guard let layoutManager else { return nil }
        let text = string as NSString
        let length = text.length

        guard length > 0 else { return (0, 0) }

        // A trailing newline parks the caret at the start of the line after it, which the layout
        // manager keeps as an "extra" fragment.
        if index >= length, text.character(at: length - 1) == 0x0A {
            let extra = layoutManager.extraLineFragmentRect
            if extra.height > 0 {
                return (0, Int((extra.minY / Metrics.cellHeight).rounded()))
            }
        }

        let reference = min(max(index, 0), length - 1)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: reference, length: 1),
                                                 actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return (0, 0) }
        let placement = cellCoordinates(forGlyphAt: glyphRange.location)
        return (placement.column + (index > reference ? 1 : 0), placement.row)
    }

    /// Which cell a glyph was laid out in.
    ///
    /// A glyph's own location is measured from its line fragment's origin, and a hanging indent
    /// moves that origin (the continuation lines of a list item start two cells in), so the
    /// fragment's own left edge has to be added back to land on the matrix.
    private func cellCoordinates(forGlyphAt glyphIndex: Int) -> (column: Int, row: Int) {
        guard let layoutManager else { return (0, 0) }
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let location = layoutManager.location(forGlyphAt: glyphIndex)
        return (Int(((lineRect.minX + location.x) / Metrics.cellWidth).rounded()),
                Int((lineRect.minY / Metrics.cellHeight).rounded()))
    }

    /// The character the caret is sitting on, if any.
    private var characterAtCaret: Character? {
        guard !showsCaretCell else { return nil }
        let nsText = string as NSString
        let location = selectedRange().location
        guard location >= 0, location < nsText.length else { return nil }
        let range = nsText.rangeOfComposedCharacterSequence(at: location)
        let substring = nsText.substring(with: range)
        return substring.isEmpty ? nil : Character(substring)
    }

    /// The caret cell for wherever the caret is right now.
    private var currentCaretCell: NSRect? {
        if showsCaretCell {
            return caretCell(forInsertionAt: litCount ?? (string as NSString).length)
        }
        guard isEditable, selectedRange().length == 0 else { return nil }
        return caretCell(forInsertionAt: selectedRange().location)
    }

    private var caretIsVisible: Bool {
        guard caretOn else { return false }
        if showsCaretCell { return true }
        return isEditable && window?.firstResponder === self
    }

    /// The caret is a whole cell, drawn by the matrix rather than by the text system, so its
    /// blinking invalidates exactly that cell.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        // Intentionally empty: the block caret is painted in `draw(_:)`.
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        updateBlinkTimer()
        restartBlink()
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        updateBlinkTimer()
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBlinkTimer()
    }

    private func updateBlinkTimer() {
        let needed = showsCaretCell || (isEditable && window?.firstResponder === self)
        if needed, blinkTimer == nil {
            let timer = Timer(timeInterval: 0.53, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.caretOn.toggle()
                // Only the caret's own cell changes, so that is all that is redrawn.
                if let cell = self.lastCaretCell { self.setNeedsDisplay(cell) }
            }
            RunLoop.current.add(timer, forMode: .common)
            blinkTimer = timer
        } else if !needed {
            blinkTimer?.invalidate()
            blinkTimer = nil
        }
    }

    /// Shows the caret again (the way a terminal does) after a keystroke.
    private func restartBlink() {
        caretOn = true
        if let cell = lastCaretCell { setNeedsDisplay(cell) }
        refreshCaretCell()
    }

    override func didChangeText() {
        super.didChangeText()
        // Keep every run invisible: pasted or imported text may carry a visible foreground colour
        // that would render as glyphs instead of dots.
        clearForegroundColours()
        // The line the caret is on may have just become a list item (or stopped being one).
        restyleLine(at: selectedRange().location)
        restartBlink()
        // The styling controls may now be out of date: a keystroke can change the run being
        // typed into, and every style change comes through here.
        syncEditorState()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        let before = lastCaretCell
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        restartBlink()
        if let before { setNeedsDisplay(before.insetBy(dx: -1, dy: -1)) }
        syncEditorState()
    }

    /// Remembers where the caret is now and repaints that cell.
    private func refreshCaretCell() {
        let cell = currentCaretCell
        lastCaretCell = cell
        if let cell { setNeedsDisplay(cell.insetBy(dx: -1, dy: -1)) }
    }

    // MARK: Drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        let scale = NSGraphicsContext.current.map { GlyphMatrix.deviceScale(of: $0.cgContext) } ?? 1
        GlyphMatrix.drawField(in: rect, metrics: metrics, colour: fieldColour(for: scale))
    }

    override func draw(_ dirtyRect: NSRect) {
        // Make sure no run carries a visible foreground colour: every character is drawn as dots,
        // so the text layer itself must stay invisible. This is the last line of defence for text
        // that was pasted in or imported from RTF with a visible colour.
        clearForegroundColours()
        // Background (panel + dot field), selection highlight and the invisible text all come from
        // the text system; the bloom and the lit dots are ours.
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        drawBloom(in: dirtyRect, into: context)
        drawLitDots(in: dirtyRect, into: context)
        drawEmoji(in: dirtyRect, into: context)
        drawCaret(in: dirtyRect, into: context)
    }

    /// The characters are drawn as dots, never as text glyphs. Suppress glyph drawing entirely so
    /// digits (or any text with a visible foreground colour) cannot render on top of the matrix.
    override func drawGlyphs(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
        // Intentionally empty: drawLitDots paints the matrix instead.
    }

    // MARK: The bloom

    /// How a run of characters is painted: the two things that decide where its dots go.
    private struct Strike: Hashable {
        let style: GlyphFont.Style
        let colour: NSColor
        let decor: NoteStyle.Decoration
    }

    /// What the bloom is keyed on: the things that mean it has to be painted from scratch.
    private struct BloomKey: Equatable {
        let pitch: CGFloat
        let tile: NSRect
        let appearance: Appearance
    }

    private var bloomLayer: (key: BloomKey, signature: Int, image: CGImage)?
    private var bloomBitmap: CGContext?

    /// How far the bloom reaches beyond what is on the screen, so nothing is cut off at its edge.
    private var bloomMargin: CGFloat { (palette.glow?.outerBlur ?? 0) + Metrics.cellHeight }

    /// Paints the bloom behind the dots from an image of its own.
    ///
    /// A blur costs time in proportion to the area it covers, and the bloom covers everything on
    /// the screen — so drawing it afresh on every pass is exactly what makes a surface feel heavy.
    /// It is painted once into a bitmap of its own instead, at one pixel per point (it is a soft
    /// glow; none of it needs a Retina screen's resolution) and blitted from then on. It is painted
    /// again only when what it is a picture of has changed: the writing on the screen, the text
    /// size, the colour, or where the screen is looking.
    private func drawBloom(in dirtyRect: NSRect, into context: CGContext) {
        guard palette.glow != nil, let layoutManager, layoutManager.numberOfGlyphs > 0 else { return }

        // What is on the screen: the part of the surface that is actually being looked at. A
        // surface that is not inside a scroll view is looked at all at once.
        let onScreen: NSRect
        if let clip = enclosingScrollView?.contentView {
            onScreen = convert(clip.bounds, from: clip)
        } else {
            onScreen = bounds
        }
        let tile = onScreen.insetBy(dx: -bloomMargin, dy: -bloomMargin)
        guard tile.width >= 1, tile.height >= 1, tile.width < 20_000, tile.height < 20_000 else { return }

        let key = BloomKey(pitch: metrics.dotPitch, tile: tile, appearance: palette)
        let signature = bloomSignature(in: tile)
        let image: CGImage
        if let layer = bloomLayer, layer.key == key, layer.signature == signature {
            image = layer.image
        } else {
            guard let bitmap = bloomBitmap(for: tile) else { return }
            bitmap.clear(CGRect(origin: .zero, size: tile.size))
            bitmap.saveGState()
            bitmap.translateBy(x: -tile.minX, y: -tile.minY)
            for (strike, path) in strikePaths(in: tile) {
                GlyphMatrix.fillGlow(path, appearance: palette.painting(in: strike.colour), into: bitmap)
            }
            bitmap.restoreGState()
            guard let painted = bitmap.makeImage() else { return }
            bloomLayer = (key, signature, painted)
            image = painted
        }

        // Only the part of it that is being repainted is composited: a caret blinking costs a
        // cell's worth of blit, not the screen's.
        context.saveGState()
        context.clip(to: dirtyRect)
        // The bloom is a soft, wide thing painted at one pixel per point: blowing it up to the
        // screen's resolution with interpolation costs far more than it is worth. Nothing about a
        // glow is sharp enough for the difference to be seen.
        context.interpolationQuality = .none
        context.draw(image, in: tile)
        context.restoreGState()
    }

    /// A bitmap for the bloom: one pixel per point, kept between paintings.
    private func bloomBitmap(for tile: NSRect) -> CGContext? {
        let width = Int(tile.width.rounded(.up))
        let height = Int(tile.height.rounded(.up))
        guard width > 0, height > 0 else { return nil }
        if let bloomBitmap, bloomBitmap.width == width, bloomBitmap.height == height {
            return bloomBitmap
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        bloomBitmap = context
        return context
    }

    /// A fingerprint of everything the bloom is a picture of: the writing in the tile, how it is
    /// struck and coloured, and where it sits.
    private func bloomSignature(in tile: NSRect) -> Int {
        guard let layoutManager, let textContainer, let textStorage else { return 0 }
        let containerRect = tile.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
        let glyphs = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        guard characters.length > 0, characters.location + characters.length <= textStorage.length
        else { return 0 }

        var hasher = Hasher()
        hasher.combine(characters.location)
        hasher.combine(characters.length)
        hasher.combine((string as NSString).substring(with: characters))
        // How much of it is lit: a replay advances this every frame, and the bloom has to follow.
        hasher.combine(litCount ?? Int.max)
        textStorage.enumerateAttributes(in: characters, options: []) { attributes, run, _ in
            hasher.combine(run.location)
            hasher.combine(run.length)
            hasher.combine(NoteStyle.style(in: attributes).rawValue)
            hasher.combine(NoteStyle.decoration(in: attributes).rawValue)
            hasher.combine(NoteStyle.tint(in: attributes)?.rawValue)
        }
        return hasher.finalize()
    }

    /// Walks every visible character, handing each one its style, its colour and the cell it sits in.
    ///
    /// The cells are worked out a line at a time rather than by asking the text system where each
    /// character went: a line fragment is one query, and every character on it is then arithmetic.
    /// That is what keeps the cost of a pass proportional to what is on the screen, whether the
    /// pass is building one path per strike or animating a replay.
    private func walkCharacters(in viewRect: NSRect,
                                _ visit: (Character, Int, GlyphFont.Style,
                                          NoteStyle.Decoration, GlyphTint?, NSColor, CGPoint) -> Void) {
        guard let layoutManager, let textContainer, let textStorage,
              layoutManager.numberOfGlyphs > 0 else { return }

        let containerRect = viewRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
        let visible = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        guard visible.length > 0 else { return }

        let text = string as NSString
        let glyphCount = layoutManager.numberOfGlyphs
        var glyph = min(visible.location, glyphCount - 1)

        while glyph < glyphCount {
            var lineGlyphs = NSRange()
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineGlyphs)
            glyph = lineGlyphs.location + lineGlyphs.length

            let lineRect = fragment.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            guard lineRect.intersects(viewRect) else { continue }

            let row = Int((fragment.minY / Metrics.cellHeight).rounded())
            let characters = layoutManager.characterRange(forGlyphRange: lineGlyphs,
                                                          actualGlyphRange: nil)
            guard characters.length > 0, characters.location < text.length else { continue }
            // A hanging indent starts the line's cells further along the matrix.
            var column = Int((fragment.minX / Metrics.cellWidth).rounded())
            var offset = characters.location
            guard !text.substring(with: characters).isEmpty else { continue }

            textStorage.enumerateAttributes(in: characters, options: []) { attributes, run, _ in
                // Catch the walk up to this run, a character at a time so a character made of
                // more than one unit still takes exactly one cell.
                while offset < run.location, offset < text.length {
                    offset += text.rangeOfComposedCharacterSequence(at: offset).length
                    column += 1
                }

                let style = NoteStyle.style(in: attributes)
                let decor = NoteStyle.decoration(in: attributes)
                let tint = NoteStyle.tint(in: attributes)
                let colour = tint?.colour(darkMode: palette.darkSurface) ?? palette.glyph

                for character in text.substring(with: run) {
                    defer {
                        offset += character.utf16.count
                        column += 1
                    }
                    // Line breaks and tabs are layout, not pattern.
                    guard !character.isNewline, character != "\t" else { continue }

                    let cell = min(column, metrics.columnCount - 1)
                    let origin = GlyphMatrix.cellOrigin(column: cell, row: row,
                                                        origin: textContainerOrigin, metrics: metrics)
                    visit(character, offset, style, decor, tint, colour, origin)
                }
            }
        }
    }

    /// Every lit dot in a rect of the view, gathered into one path per strike.
    ///
    /// Characters are grouped by how they are struck and in what colour, so an unstyled note costs
    /// exactly one path, and only a note with styling pays for the extra passes a bloom needs.
    private func strikePaths(in viewRect: NSRect) -> [Strike: CGMutablePath] {
        var groups: [Strike: CGMutablePath] = [:]
        // A long run of the same style keeps its path, so the dictionary is consulted once a run
        // rather than once a character.
        var lastStrike: Strike?
        var lastPath: CGMutablePath?
        let lit = litCount ?? Int.max

        walkCharacters(in: viewRect) { character, location, style, decor, tint, colour, origin in
            // Emoji are drawn as the real glyph, not as dots, so they take no part in the bloom.
            guard !GlyphFont.isEmoji(character) else { return }
            // What has not been struck yet takes no part in the bloom either.
            guard location < lit else { return }
            let strike = Strike(style: style, colour: colour, decor: decor)
            let path: CGMutablePath
            if let lastStrike, lastStrike == strike, let lastPath {
                path = lastPath
            } else {
                path = groups[strike] ?? CGMutablePath()
                groups[strike] = path
                lastStrike = strike
                lastPath = path
            }
            GlyphMatrix.addDots(for: character, style: style, inCell: origin, metrics: metrics,
                                decor: decor, into: path)
        }
        return groups
    }

    /// Draws every visible character as lit dots, up to the point a replay has struck.
    ///
    /// A replay is drawn exactly as the editor draws — except that only the characters struck so far
    /// are drawn at all. That, and nothing else, is what makes a replay look like writing.
    private func drawLitDots(in dirtyRect: NSRect, into context: CGContext) {
        guard let litCount else {
            // Everything is lit: one path per strike, straight through.
            for (strike, path) in strikePaths(in: dirtyRect) where !path.isEmpty {
                GlyphMatrix.fillDots(path, colour: palette.painting(in: strike.colour).glyph,
                                     into: context)
            }
            return
        }

        // A replay: the same pass, stopping at the struck character.
        var groups: [Strike: CGMutablePath] = [:]
        walkCharacters(in: dirtyRect) { character, location, style, decor, tint, colour, origin in
            // Emoji are drawn as the real glyph elsewhere, so skip them here.
            guard !GlyphFont.isEmoji(character) else { return }
            guard location < litCount else { return }
            let strike = Strike(style: style, colour: colour, decor: decor)
            let path = groups[strike] ?? CGMutablePath()
            groups[strike] = path
            GlyphMatrix.addDots(for: character, style: style, inCell: origin, metrics: metrics,
                                decor: decor, into: path)
        }
        for (strike, path) in groups where !path.isEmpty {
            GlyphMatrix.fillDots(path, colour: palette.painting(in: strike.colour).glyph,
                                 into: context)
        }
    }

    /// Draws the real colour glyphs for emoji, which the dot matrix cannot represent.
    private func drawEmoji(in dirtyRect: NSRect, into context: CGContext) {
        guard let layoutManager, let textContainer else { return }
        let lit = litCount ?? Int.max
        let emojiFont = NSFont(name: "Apple Color Emoji", size: Metrics.cellHeight * 0.72)
            ?? NSFont.systemFont(ofSize: Metrics.cellHeight * 0.72)
        // Emoji are allowed to spill slightly past their cell, so lift the clip off the dirty
        // rect for the duration of this pass.
        context.saveGState()
        context.resetClip()
        walkCharacters(in: dirtyRect) { character, location, style, decor, tint, colour, origin in
            guard GlyphFont.isEmoji(character) else { return }
            guard location < lit else { return }
            let attributed = NSAttributedString(string: String(character), attributes: [
                .font: emojiFont
            ])
            let size = attributed.size()
            let point = NSPoint(x: origin.x + (Metrics.cellWidth - size.width) / 2,
                                y: origin.y + (Metrics.cellHeight - size.height) / 2)
            attributed.draw(at: point)
        }
        context.restoreGState()
    }

    /// Draws the caret as a lit cell: the block is filled with the accent colour and the cell's
    /// dots are knocked out of it, so the character under the caret stays readable.
    private func drawCaret(in dirtyRect: NSRect, into context: CGContext) {
        guard caretIsVisible, let cell = currentCaretCell, cell.intersects(dirtyRect) else { return }

        context.setFillColor(palette.caret.cgColor)
        context.fill(cell)

        let knockedOut = CGMutablePath()
        let corner = CGPoint(x: cell.minX, y: cell.minY)
        GlyphMatrix.addFieldDots(inCell: corner, metrics: metrics, into: knockedOut)
        if let character = characterAtCaret {
            GlyphMatrix.addDots(for: character, style: styleAtCaret, inCell: corner, metrics: metrics,
                                decor: decorAtCaret, into: knockedOut)
        }
        context.addPath(knockedOut)
        context.setFillColor(palette.panel.cgColor)
        context.fillPath()
    }

    // MARK: Styling

    /// The style the caret is sitting on, so a knocked-out character keeps its weight.
    private var styleAtCaret: GlyphFont.Style {
        guard let textStorage, textStorage.length > 0 else { return .regular }
        let location = min(selectedRange().location, textStorage.length - 1)
        return NoteStyle.style(in: textStorage.attributes(at: max(location, 0), effectiveRange: nil))
    }

    /// The decoration at the caret, for the same reason.
    private var decorAtCaret: NoteStyle.Decoration {
        guard let textStorage, textStorage.length > 0 else { return [] }
        let location = min(selectedRange().location, textStorage.length - 1)
        return NoteStyle.decoration(in: textStorage.attributes(at: max(location, 0), effectiveRange: nil))
    }

    @objc func toggleBold(_ sender: Any?) {
        apply(style: GlyphFont.Style(bold: !currentStyle.isBold, italic: currentStyle.isItalic))
    }

    @objc func toggleItalic(_ sender: Any?) {
        apply(style: GlyphFont.Style(bold: currentStyle.isBold, italic: !currentStyle.isItalic))
    }

    @objc func toggleUnderline(_ sender: Any?) {
        let decor = currentDecor
        apply(decor: decor.contains(.underline) ? decor.subtracting(.underline) : decor.union(.underline))
    }

    @objc func toggleStrikethrough(_ sender: Any?) {
        let decor = currentDecor
        apply(decor: decor.contains(.strike) ? decor.subtracting(.strike) : decor.union(.strike))
    }

    /// The style the controls are worked on: the selection's, or the one being typed.
    private var currentStyle: GlyphFont.Style {
        guard let textStorage, selectedRange().length > 0, textStorage.length > 0 else { return typingStyle }
        let location = min(selectedRange().location, textStorage.length - 1)
        return NoteStyle.style(in: textStorage.attributes(at: max(location, 0), effectiveRange: nil))
    }

    /// The decoration the controls are worked on: the selection's, or the one being typed.
    private var currentDecor: NoteStyle.Decoration {
        guard let textStorage, selectedRange().length > 0, textStorage.length > 0 else { return typingDecor }
        let location = min(selectedRange().location, textStorage.length - 1)
        return NoteStyle.decoration(in: textStorage.attributes(at: location, effectiveRange: nil))
    }

    /// Applies a decoration to the selection, or to the next typed characters when nothing is
    /// selected.
    func apply(decor: NoteStyle.Decoration) {
        let range = selectedRange()
        guard range.length > 0, let textStorage else {
            typingDecor = decor
            refreshTypingAttributes()
            syncEditorState()
            return
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }

        textStorage.beginEditing()
        if decor.isEmpty {
            textStorage.removeAttribute(NoteStyle.decorKey, range: range)
        } else {
            textStorage.addAttribute(NoteStyle.decorKey, value: decor.rawValue, range: range)
        }
        textStorage.endEditing()

        didChangeText()
        invalidate(charactersIn: range)
    }

    /// Applies a style to the selection, or to the next typed characters when nothing is selected.
    func apply(style: GlyphFont.Style) {
        let range = selectedRange()
        guard range.length > 0, let textStorage else {
            typingStyle = style
            refreshTypingAttributes()
            syncEditorState()
            return
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }

        textStorage.beginEditing()
        if style == .regular {
            textStorage.removeAttribute(NoteStyle.styleKey, range: range)
        } else {
            textStorage.addAttribute(NoteStyle.styleKey, value: style.rawValue, range: range)
        }
        textStorage.endEditing()

        didChangeText()
        invalidate(charactersIn: range)
    }

    /// Colours the selection. Returns false when there is no selection, in which case the colour
    /// is the note's own and belongs to the app rather than to this run of text.
    @discardableResult
    func applyTintToSelection(_ tint: GlyphTint) -> Bool {
        let range = selectedRange()
        guard range.length > 0, let textStorage else { return false }
        guard shouldChangeText(in: range, replacementString: nil) else { return true }

        textStorage.beginEditing()
        textStorage.addAttribute(NoteStyle.tintKey, value: tint.rawValue, range: range)
        textStorage.endEditing()

        didChangeText()
        invalidate(charactersIn: range)
        return true
    }

    /// Puts the selection back in the note's own colour.
    @objc func clearTint(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0, let textStorage else { return }
        guard shouldChangeText(in: range, replacementString: nil) else { return }

        textStorage.beginEditing()
        textStorage.removeAttribute(NoteStyle.tintKey, range: range)
        textStorage.endEditing()

        didChangeText()
        invalidate(charactersIn: range)
    }

    /// Carries a colour through the responder chain: the swatches are in the status bar, and the
    /// text they colour is here.
    final class TintAction: NSObject {
        let tint: GlyphTint
        init(_ tint: GlyphTint) { self.tint = tint }
    }

    /// Colours the selection. Sent by the swatches when something is selected; with nothing
    /// selected the colour belongs to the note and the picker's own value is the answer.
    @objc func applyTint(_ sender: Any?) {
        guard let action = sender as? TintAction else { return }
        applyTintToSelection(action.tint)
    }

    /// Publishes what the styling controls in the status bar should be showing.
    func syncEditorState() {
        let range = selectedRange()
        EditorState.shared.update(
            style: currentStyle,
            decor: range.length > 0 ? currentDecor : typingDecor,
            isBulleted: range.length > 0 && NoteList.isBulleted(string as NSString, in: range),
            hasSelection: range.length > 0 && window?.firstResponder === self
        )
    }

    /// Bullets the lines the selection touches, or takes the bullets away again.
    @objc func toggleList(_ sender: Any?) {
        guard let textStorage else { return }
        let range = selectedRange()
        let lines = NoteList.lineRanges(in: textStorage.string as NSString, for: range)
        guard let first = lines.first, let last = lines.last else { return }

        let adding = !NoteList.isBulleted(textStorage.string as NSString, in: range)
        let span = NSRange(location: first.location,
                           length: last.location + last.length - first.location)
        guard shouldChangeText(in: span, replacementString: nil) else { return }

        // Worked from the bottom up so the ranges above stay valid, and with each line's own
        // attributes carried onto the bullet, so a list keeps its style.
        var delta = 0
        textStorage.beginEditing()
        for line in lines.reversed() {
            let text = textStorage.string as NSString
            guard line.location <= text.length else { continue }
            let lineText = text.substring(with: NSRange(location: line.location,
                                                       length: min(line.length, text.length - line.location)))
            guard !lineText.isEmpty else { continue }

            if adding {
                guard !lineText.hasPrefix("•") else { continue }
                let attributes = textStorage.attributes(at: line.location, effectiveRange: nil)
                textStorage.insert(NSAttributedString(string: NoteList.bullet, attributes: attributes),
                                   at: line.location)
                delta += NoteList.bullet.count
            } else {
                let drop = NoteList.bulletPrefix(of: lineText)
                guard drop > 0 else { continue }
                textStorage.deleteCharacters(in: NSRange(location: line.location, length: drop))
                delta -= drop
            }
        }
        // A line that has just gained (or lost) its bullet hangs (or stops hanging).
        NoteDocument.applyRuler(to: textStorage)
        textStorage.endEditing()

        didChangeText()
        setSelectedRange(NSRange(location: first.location, length: max(0, span.length + delta)))
        invalidate(charactersIn: NSRange(location: first.location, length: max(0, span.length + delta)))
    }

    // MARK: Lists while writing

    /// The line the caret is on, clamped to the text.
    private func caretLine() -> NSRange? {
        guard let textStorage else { return nil }
        let text = textStorage.string as NSString
        guard text.length > 0 else { return nil }
        let caret = min(max(selectedRange().location, 0), text.length)
        let line = text.lineRange(for: NSRange(location: min(caret, text.length - 1), length: 0))
        return NSRange(location: line.location, length: min(line.length, text.length - line.location))
    }

    /// Puts one line's paragraph style right: a line that holds a bullet hangs under it, and a
    /// line that does not, does not. Only ever one line, so it is cheap enough to run on every
    /// keystroke — which is what keeps a list looking like a list as it is written.
    private func restyleLine(at location: Int) {
        guard !isRestyling, let textStorage, textStorage.length > 0 else { return }
        let text = textStorage.string as NSString
        let index = min(max(location, 0), text.length - 1)
        let line = text.lineRange(for: NSRange(location: index, length: 0))
        let range = NSRange(location: line.location,
                            length: min(line.length, text.length - line.location))
        guard range.length > 0 else { return }

        let bulleted = NoteList.isBulletedLine(text, at: range.location)
        let wanted = GlyphMatrix.paragraphStyle(list: bulleted)
        let current = textStorage.attribute(.paragraphStyle, at: range.location,
                                            effectiveRange: nil) as? NSParagraphStyle
        guard current?.headIndent != wanted.headIndent else { return }

        isRestyling = true
        textStorage.addAttribute(.paragraphStyle, value: wanted, range: range)
        isRestyling = false
    }

    /// Return, the way a list behaves in Notes: it starts the next item when the one you are on
    /// has something in it, and it ends the list when the item is empty.
    override func insertNewline(_ sender: Any?) {
        guard isEditable, selectedRange().length == 0,
              let textStorage, let line = caretLine() else {
            super.insertNewline(sender)
            return
        }
        let text = textStorage.string as NSString
        let caret = min(max(selectedRange().location, line.location), line.location + line.length)
        let prefix = NoteList.bulletPrefix(of: text.substring(
            with: NSRange(location: line.location, length: caret - line.location)))
        guard prefix > 0 else {
            super.insertNewline(sender)
            return
        }

        let contentStart = line.location + prefix
        let content = text.substring(with: NSRange(location: contentStart,
                                                  length: max(0, caret - contentStart)))
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            endList(line: line, caret: caret, contentStart: contentStart)
        } else {
            startListItem(at: caret, in: line)
        }
    }

    /// Starts the next item: a new line, a fresh bullet, and the same strike as the line above.
    private func startListItem(at caret: Int, in line: NSRange) {
        let source = min(max(line.location, 0), max((textStorage?.length ?? 1) - 1, 0))
        let attributes = textStorage?.attributes(at: source, effectiveRange: nil) ?? typingAttributes
        let insertion = NSMutableAttributedString(string: "\n" + NoteList.bullet, attributes: attributes)
        insertion.addAttribute(.paragraphStyle, value: GlyphMatrix.paragraphStyle(list: true),
                               range: NSRange(location: 0, length: insertion.length))
        substitute(insertion, in: NSRange(location: caret, length: 0))
    }

    /// Ends the list on an empty item: the bullet goes, the line stays where it is, and the caret
    /// does not move down — the same thing Return does on an empty item in Notes.
    private func endList(line: NSRange, caret: Int, contentStart: Int) {
        guard let textStorage else { return }
        let text = textStorage.string as NSString
        var end = min(max(caret, contentStart), line.location + line.length)
        if end > line.location, text.character(at: end - 1) == 0x0A { end -= 1 }

        substitute(NSAttributedString(string: ""),
                   in: NSRange(location: line.location, length: end - line.location))
        if textStorage.length > 0 { restyleLine(at: line.location) }
    }

    /// Backspace at the very start of an item takes the bullet away and leaves the list, rather
    /// than dragging the line above into this one.
    override func deleteBackward(_ sender: Any?) {
        if isEditable, selectedRange().length == 0,
           let textStorage, let line = caretLine() {
            let prefix = NoteList.bulletPrefix(in: textStorage.string as NSString, at: line.location)
            if prefix > 0, selectedRange().location == line.location + prefix {
                substitute(NSAttributedString(string: ""),
                           in: NSRange(location: line.location, length: prefix))
                restyleLine(at: line.location)
                        return
            }
        }
        super.deleteBackward(sender)
    }

    /// One edit, through the undo machinery, with the caret left after what was written.
    private func substitute(_ attributed: NSAttributedString, in range: NSRange) {
        guard let textStorage,
              shouldChangeText(in: range, replacementString: attributed.string) else { return }
        textStorage.replaceCharacters(in: range, with: attributed)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + attributed.length, length: 0))
        invalidate(charactersIn: NSRange(location: range.location,
                                         length: max(range.length, attributed.length)))
        refreshCaretCell()
    }

    /// Repaints just the cells a character range occupies.
    private func invalidate(charactersIn range: NSRange) {
        guard let layoutManager, let textContainer, range.length > 0 else { return }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        setNeedsDisplay(rect.insetBy(dx: -metrics.dotPitch, dy: -metrics.dotPitch))
    }

}

// MARK: - Scroll container

/// A scroll view that keeps the matrix's column count in step with its own width.
///
/// Doing this here (rather than in `updateNSView`) means a window resize is handled by AppKit's
/// own layout pass, so the editor and a replay can never disagree about how wide a row is.
final class GlyphMatrixScrollView: NSScrollView {

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        guard widthChanged, let textView = documentView as? GlyphMatrixTextView else { return }
        textView.fit(width: contentSize.width, height: contentSize.height)
    }

    /// Puts a matrix text view inside, configured either for writing or for playback.
    static func wrapping(_ textView: GlyphMatrixTextView) -> GlyphMatrixScrollView {
        let scrollView = GlyphMatrixScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        // Overlay scrollers never steal width from the text, so the column count (and therefore
        // the wrapping) is identical in the editor and in a replay.
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return scrollView
    }
}
