import Foundation

/// A 5×8 dot-matrix face: the shape of every character FewNote draws.
///
/// Each glyph is eight rows of five markers, top row first, `#` meaning a lit dot. The bottom row
/// is the descender row, so `g`, `j`, `p`, `q`, `y`, the comma and the brackets have somewhere to
/// go. The shapes are the familiar 5×7 matrix forms you find on dot-matrix printers and LED
/// displays — nothing here leans on a system font, which is what makes the surface read as a
/// matrix rather than as small text.
public enum GlyphFont {

    /// The shape is five dots wide and eight dots tall (seven for the character, one spare for
    /// descenders).
    public static let columns = 5
    public static let rows = 8

    /// Lit dot coordinates for a character, in the glyph's own dot grid.
    public struct Dot: Equatable {
        public let column: Int
        public let row: Int
    }

    /// How a character is struck.
    ///
    /// Bold is a double strike, the way a typewriter makes one: every lit dot is repeated one dot
    /// to its right, and the ink is laid down heavier, so the two strokes merge into one solid
    /// line. Italic leans the glyph by up to a dot and a fifth across its height, which is as far
    /// as it can go before it reaches into the next cell.
    public enum Style: String, CaseIterable {
        case regular
        case bold
        case italic
        case boldItalic

        public var isBold: Bool { self == .bold || self == .boldItalic }
        public var isItalic: Bool { self == .italic || self == .boldItalic }

        public init(bold: Bool, italic: Bool) {
            switch (bold, italic) {
            case (true, true): self = .boldItalic
            case (true, false): self = .bold
            case (false, true): self = .italic
            case (false, false): self = .regular
            }
        }
    }

    /// A dot placed on the grid. Columns are fractional only so italic can lean a glyph.
    public struct Placed: Equatable {
        public let column: Double
        public let row: Int
    }

    /// How far the top of an italic glyph leans, in dots. Below one and a half columns, which
    /// keeps the lean inside the cell's inter-character gap.
    static let italicLean = 1.2 / Double(rows - 1)

    /// How much fatter a bold dot is struck, as a multiple of an ordinary one.
    ///
    /// The double strike is what carries the weight; this is what stops it reading as two rows of
    /// separate dots. It is kept below the point where the ink would close the small counters in
    /// letters like "e" and "s", which is what "clean" means in a five-dot-wide face.
    public static let boldInk = 1.2


    /// The missing-glyph box, drawn for anything the face has no shape for.
    static let box = "#####/#...#/#...#/#...#/#...#/#...#/#####/....."

    /// The plain face: the ASCII characters, as `#`/`.` rows joined by `/`.
    private static let baseGlyphs: [Character: String] = [
        " ": "...../...../...../...../...../...../...../.....",
        "!": "..#../..#../..#../..#../..#../...../..#../.....",
        "\"": ".#.#./.#.#./...../...../...../...../...../.....",
        "#": ".#.#./.#.#./#####/.#.#./#####/.#.#./.#.#./.....",
        "$": "..#../.####/#.#../.###./..#.#/####./..#../.....",
        "%": "##.../##..#/...#./..#../.#.../#..##/...##/.....",
        "&": ".##../#..#./#.#../.#.../#.#.#/#..#./.##.#/.....",
        "'": "..#../..#../...../...../...../...../...../.....",
        "(": "...#./..#../.#.../.#.../.#.../..#../...#./.....",
        ")": ".#.../..#../...#./...#./...#./..#../.#.../.....",
        "*": "...../#.#.#/.###./#####/.###./#.#.#/...../.....",
        "+": "...../..#../..#../#####/..#../..#../...../.....",
        ",": "...../...../...../...../...../..##./..#../.#...",
        "-": "...../...../...../#####/...../...../...../.....",
        ".": "...../...../...../...../...../..##./..##./.....",
        "/": "....#/...#./...#./..#../.#.../.#.../#..../.....",
        "0": ".###./#...#/#..##/#.#.#/##..#/#...#/.###./.....",
        "1": "..#../.##../..#../..#../..#../..#../.###./.....",
        "2": ".###./#...#/....#/...#./..#../.#.../#####/.....",
        "3": "#####/...#./..#../...#./....#/#...#/.###./.....",
        "4": "...#./..##./.#.#./#..#./#####/...#./...#./.....",
        "5": "#####/#..../####./....#/....#/#...#/.###./.....",
        "6": "..##./.#.../#..../####./#...#/#...#/.###./.....",
        "7": "#####/....#/...#./..#../.#.../.#.../.#.../.....",
        "8": ".###./#...#/#...#/.###./#...#/#...#/.###./.....",
        "9": ".###./#...#/#...#/.####/....#/...#./.##../.....",
        ":": "...../..##./..##./...../..##./..##./...../.....",
        ";": "...../..##./..##./...../..##./..#../.#.../.....",
        "<": "...#./..#../.#.../#..../.#.../..#../...#./.....",
        "=": "...../...../#####/...../#####/...../...../.....",
        ">": ".#.../..#../...#./....#/...#./..#../.#.../.....",
        "?": ".###./#...#/....#/...#./..#../...../..#../.....",
        "@": ".###./#...#/#.###/#.#.#/#.###/#..../.###./.....",
        "A": ".###./#...#/#...#/#####/#...#/#...#/#...#/.....",
        "B": "####./#...#/#...#/####./#...#/#...#/####./.....",
        "C": ".####/#..../#..../#..../#..../#..../.####/.....",
        "D": "####./#...#/#...#/#...#/#...#/#...#/####./.....",
        "E": "#####/#..../#..../####./#..../#..../#####/.....",
        "F": "#####/#..../#..../####./#..../#..../#..../.....",
        "G": ".####/#..../#..../#..##/#...#/#...#/.###./.....",
        "H": "#...#/#...#/#...#/#####/#...#/#...#/#...#/.....",
        "I": ".###./..#../..#../..#../..#../..#../.###./.....",
        "J": "..###/...#./...#./...#./...#./#..#./.##../.....",
        "K": "#...#/#..#./#.#../##.../#.#../#..#./#...#/.....",
        "L": "#..../#..../#..../#..../#..../#..../#####/.....",
        "M": "#...#/##.##/#.#.#/#...#/#...#/#...#/#...#/.....",
        "N": "#...#/##..#/#.#.#/#..##/#...#/#...#/#...#/.....",
        "O": ".###./#...#/#...#/#...#/#...#/#...#/.###./.....",
        "P": "####./#...#/#...#/####./#..../#..../#..../.....",
        "Q": ".###./#...#/#...#/#...#/#.#.#/#..#./.##.#/.....",
        "R": "####./#...#/#...#/####./#.#../#..#./#...#/.....",
        "S": ".####/#..../#..../.###./....#/....#/####./.....",
        "T": "#####/..#../..#../..#../..#../..#../..#../.....",
        "U": "#...#/#...#/#...#/#...#/#...#/#...#/.###./.....",
        "V": "#...#/#...#/#...#/#...#/#...#/.#.#./..#../.....",
        "W": "#...#/#...#/#...#/#...#/#.#.#/##.##/#...#/.....",
        "X": "#...#/#...#/.#.#./..#../.#.#./#...#/#...#/.....",
        "Y": "#...#/#...#/.#.#./..#../..#../..#../..#../.....",
        "Z": "#####/....#/...#./..#../.#.../#..../#####/.....",
        "[": ".###./.#.../.#.../.#.../.#.../.#.../.###./.....",
        "\\": "#..../.#.../.#.../..#../...#./...#./....#/.....",
        "]": ".###./...#./...#./...#./...#./...#./.###./.....",
        "^": "..#../.#.#./#...#/...../...../...../...../.....",
        "_": "...../...../...../...../...../...../...../#####",
        "`": ".#.../..#../...../...../...../...../...../.....",
        "a": "...../...../.###./....#/.####/#...#/.####/.....",
        "b": "#..../#..../####./#...#/#...#/#...#/####./.....",
        "c": "...../...../.####/#..../#..../#..../.####/.....",
        "d": "....#/....#/.####/#...#/#...#/#...#/.####/.....",
        "e": "...../...../.###./#...#/#####/#..../.###./.....",
        "f": "..##./.#.../.#.../####./.#.../.#.../.#.../.....",
        "g": "...../...../.####/#...#/#...#/.####/....#/.###.",
        "h": "#..../#..../####./#...#/#...#/#...#/#...#/.....",
        "i": "..#../...../.##../..#../..#../..#../.###./.....",
        "j": "...#./...../..##./...#./...#./...#./#..#./.##..",
        "k": "#..../#..../#..#./#.#../##.../#.#../#..#./.....",
        "l": ".##../..#../..#../..#../..#../..#../.###./.....",
        "m": "...../...../##.#./#.#.#/#.#.#/#...#/#...#/.....",
        "n": "...../...../####./#...#/#...#/#...#/#...#/.....",
        "o": "...../...../.###./#...#/#...#/#...#/.###./.....",
        "p": "...../...../####./#...#/#...#/####./#..../#....",
        "q": "...../...../.####/#...#/#...#/.####/....#/....#",
        "r": "...../...../#.##./##..#/#..../#..../#..../.....",
        "s": "...../...../.####/#..../.###./....#/####./.....",
        "t": ".#.../.#.../####./.#.../.#.../.#..#/..##./.....",
        "u": "...../...../#...#/#...#/#...#/#...#/.####/.....",
        "v": "...../...../#...#/#...#/#...#/.#.#./..#../.....",
        "w": "...../...../#...#/#...#/#.#.#/#.#.#/.#.#./.....",
        "x": "...../...../#...#/.#.#./..#../.#.#./#...#/.....",
        "y": "...../...../#...#/#...#/#...#/.####/....#/.###.",
        "z": "...../...../#####/...#./..#../.#.../#####/.....",
        "{": "..##./.#.../.#.../##.../.#.../.#.../..##./.....",
        "|": "..#../..#../..#../..#../..#../..#../..#../.....",
        "}": ".##../...#./...#./...##/...#./...#./.##../.....",
        "~": "...../...../.##.#/#..#./...../...../...../.....",
        // A few marks of typography that arrive by paste rather than by key. Every accented letter
        // the face can draw is composed below, from these same plain shapes.
        "‘": "..#../..#../...../...../...../...../...../.....",
        "’": "..#../..#../...../...../...../...../...../.....",
        "“": ".#.#./.#.#./...../...../...../...../...../.....",
        "”": ".#.#./.#.#./...../...../...../...../...../.....",
        "–": "...../...../...../#####/...../...../...../.....",
        "—": "...../...../...../#####/...../...../...../.....",
        "…": "...../...../...../...../...../...../#.#.#/.....",
        "°": "..#../.#.#./..#../...../...../...../...../.....",
        // The list bullet, so a bulleted line is drawn by the matrix like everything else.
        "•": "...../...../...../..##./..##./...../...../....."
    ]

    // MARK: - Accented letters

    /// A mark that sits above a letter.
    ///
    /// Each is two rows tall, because a lowercase letter leaves the two rows above its x-height
    /// free — which is exactly the room a mark needs. A capital has no such room, so it gives up
    /// the row it stands on and takes the mark's upper row: an accented capital in this face
    /// stands one dot lower than the rest, the way an unspaced accent does on a typewriter.
    enum Accent {
        case acute, grave, circumflex, caron, diaeresis, tilde, ring, macron, breve, dot, doubleAcute

        /// The mark's two rows, upper first.
        var rows: (upper: String, lower: String) {
            switch self {
            case .acute:       return ("...#.", "..#..")
            case .grave:       return (".#...", "..#..")
            case .circumflex:  return ("..#..", ".#.#.")
            case .caron:       return (".#.#.", "..#..")
            case .diaeresis:   return (".#.#.", ".....")
            case .tilde:       return (".##..", "..##.")
            case .ring:        return ("..#..", ".....")
            case .macron:      return ("#####", ".....")
            case .breve:       return ("#...#", ".###.")
            case .dot:         return (".....", "..#..")
            case .doubleAcute: return ("#...#", ".#.#.")
            }
        }
    }

    /// A mark that hangs below a letter, in the row the descenders use.
    enum Tail {
        case cedilla, commaBelow, ogonek

        var row: String {
            switch self {
            case .cedilla:    return "..##."
            case .commaBelow: return "..#.."
            case .ogonek:     return "...#."
            }
        }
    }

    /// An accented letter, described rather than drawn: which plain letter it is, and what is on it.
    struct Letter {
        var base: Character
        /// The mark above, or none where the letter carries only a tail.
        var mark: Accent?
        var tail: Tail?
        /// True where the letter reaches the top row itself, so the mark has to sit beside it —
        /// which is how a caron sits on "ď", "ľ" and "ť" in a face this size.
        var beside: Bool

        init(base: Character, mark: Accent?, tail: Tail? = nil, beside: Bool = false) {
            self.base = base
            self.mark = mark
            self.tail = tail
            self.beside = beside
        }
    }

    private static func over(_ base: Character, _ mark: Accent?,
                             tail: Tail? = nil, beside: Bool = false) -> Letter {
        Letter(base: base, mark: mark, tail: tail, beside: beside)
    }

    /// Every accented letter, as the plain letter and the marks on it.
    ///
    /// Written this way rather than as hand-drawn shapes so that a language's accents all come out
    /// of the same alphabet: "é" is an "e" with an acute, "É" the same on a capital. It covers the
    /// Latin-1 languages (Spanish, French, German, Portuguese, Italian, Dutch, the Nordics) and the
    /// common letters of Latin Extended-A (Polish, Czech, Slovak, Hungarian, Turkish, Romanian,
    /// Croatian, Baltic, Icelandic).
    private static let accentedLetters: [Character: Letter] = [
        // Acute
        "á": over("a", .acute), "é": over("e", .acute), "í": over("i", .acute),
        "ó": over("o", .acute), "ú": over("u", .acute), "ý": over("y", .acute),
        "ć": over("c", .acute), "ń": over("n", .acute), "ś": over("s", .acute),
        "ź": over("z", .acute), "ĺ": over("l", .acute, beside: true),
        "Á": over("A", .acute), "É": over("E", .acute), "Í": over("I", .acute),
        "Ó": over("O", .acute), "Ú": over("U", .acute), "Ý": over("Y", .acute),
        "Ć": over("C", .acute), "Ń": over("N", .acute), "Ś": over("S", .acute),
        "Ź": over("Z", .acute), "Ĺ": over("L", .acute),

        // Grave
        "à": over("a", .grave), "è": over("e", .grave), "ì": over("i", .grave),
        "ò": over("o", .grave), "ù": over("u", .grave),
        "À": over("A", .grave), "È": over("E", .grave), "Ì": over("I", .grave),
        "Ò": over("O", .grave), "Ù": over("U", .grave),

        // Circumflex
        "â": over("a", .circumflex), "ê": over("e", .circumflex), "î": over("i", .circumflex),
        "ô": over("o", .circumflex), "û": over("u", .circumflex),
        "Â": over("A", .circumflex), "Ê": over("E", .circumflex), "Î": over("I", .circumflex),
        "Ô": over("O", .circumflex), "Û": over("U", .circumflex),

        // Tilde
        "ã": over("a", .tilde), "õ": over("o", .tilde), "ñ": over("n", .tilde),
        "Ã": over("A", .tilde), "Õ": over("O", .tilde), "Ñ": over("N", .tilde),

        // Diaeresis
        "ä": over("a", .diaeresis), "ë": over("e", .diaeresis), "ï": over("i", .diaeresis),
        "ö": over("o", .diaeresis), "ü": over("u", .diaeresis), "ÿ": over("y", .diaeresis),
        "Ä": over("A", .diaeresis), "Ë": over("E", .diaeresis), "Ï": over("I", .diaeresis),
        "Ö": over("O", .diaeresis), "Ü": over("U", .diaeresis), "Ÿ": over("Y", .diaeresis),

        // Ring, macron, breve, dot
        "å": over("a", .ring), "Å": over("A", .ring),
        "ā": over("a", .macron), "ē": over("e", .macron), "ī": over("i", .macron),
        "ō": over("o", .macron), "ū": over("u", .macron),
        "Ā": over("A", .macron), "Ē": over("E", .macron), "Ī": over("I", .macron),
        "Ō": over("O", .macron), "Ū": over("U", .macron),
        "ă": over("a", .breve), "ğ": over("g", .breve),
        "Ă": over("A", .breve), "Ğ": over("G", .breve),
        "ė": over("e", .dot), "ż": over("z", .dot),
        "Ė": over("E", .dot), "Ż": over("Z", .dot),
        "ő": over("o", .doubleAcute), "ű": over("u", .doubleAcute),
        "Ő": over("O", .doubleAcute), "Ű": over("U", .doubleAcute),

        // Caron
        "č": over("c", .caron), "ď": over("d", .caron, beside: true), "ě": over("e", .caron),
        "ľ": over("l", .caron, beside: true), "ň": over("n", .caron), "ř": over("r", .caron),
        "š": over("s", .caron), "ť": over("t", .caron, beside: true), "ž": over("z", .caron),
        "Č": over("C", .caron), "Ď": over("D", .caron), "Ě": over("E", .caron),
        "Ľ": over("L", .caron), "Ň": over("N", .caron), "Ř": over("R", .caron),
        "Š": over("S", .caron), "Ť": over("T", .caron), "Ž": over("Z", .caron),

        // Marks below
        "ç": over("c", nil, tail: .cedilla), "ş": over("s", nil, tail: .cedilla),
        "ţ": over("t", nil, tail: .cedilla),
        "Ç": over("C", nil, tail: .cedilla), "Ş": over("S", nil, tail: .cedilla),
        "Ţ": over("T", nil, tail: .cedilla),
        "ș": over("s", nil, tail: .commaBelow), "ț": over("t", nil, tail: .commaBelow),
        "Ș": over("S", nil, tail: .commaBelow), "Ț": over("T", nil, tail: .commaBelow),
        "ą": over("a", nil, tail: .ogonek), "ę": over("e", nil, tail: .ogonek),
        "į": over("i", nil, tail: .ogonek),
        "Ą": over("A", nil, tail: .ogonek), "Ę": over("E", nil, tail: .ogonek)
    ]

    /// Letters no plain letter plus a mark will make, drawn by hand.
    private static let drawnLetters: [Character: String] = [
        // The German sharp s: a long s with a z below it.
        "ß": ".###./#...#/#...#/#.##./#...#/#...#/#.##./.....",
        // The Nordic and Polish o and l, and the crossed d.
        "ø": "...../....#/.###./#..##/#.#.#/##..#/.###./.....",
        "Ø": "....#/#...#/#..##/#.#.#/##..#/#...#/.###./.....",
        "ł": ".##../..#../..#../#.##./..#../..#../.###./.....",
        "Ł": "#..../#..../#..../#.#../##.../#..../#####/.....",
        "đ": "....#/....#/#####/#...#/#...#/#...#/.####/.....",
        "Đ": "####./#...#/#...#/#####/#...#/#...#/####./.....",
        // The dotless i, which is what an accent needs to sit on.
        "ı": "...../...../.##../..#../..#../..#../.###./.....",
        // Icelandic: eth and thorn.
        "ð": "...../###../.###./#...#/#...#/#...#/.###./.....",
        "Ð": "####./#...#/#...#/#####/#...#/#...#/####./#####",
        "þ": "#..../#..../####./#...#/#...#/####./#..../#....",
        "Þ": "####./#...#/#...#/####./#..../#..../#..../.....",
        // The ligatures, which no five-dot cell can hold properly. Drawn as tightly as the cell
        // allows rather than as two letters sharing a bowl.
        "æ": "...../...../.#.#./#.#.#/#.###/#.#.#/.###./.....",
        "Æ": "....#/...#./..###/.####/#####/##..#/##..#/.....",
        "œ": "...../...../.###./#.##./#.###/#.#.#/.###./.....",
        "Œ": ".####/#.#.#/#.#.#/#.###/#.#.#/#.#.#/.####/....."
    ]

    /// Additional scripts: the letters of Cyrillic and Greek, so notes in those languages light
    /// up as themselves rather than as missing-glyph boxes. Lookalikes share their Latin shape;
    /// the rest are drawn for the 5×8 cell.
    private static let scriptGlyphs: [Character: String] = [
        // Cyrillic lookalikes (same shape as a Latin letter).
        "А": baseGlyphs["A"]!, "В": baseGlyphs["B"]!, "Е": baseGlyphs["E"]!,
        "К": baseGlyphs["K"]!, "М": baseGlyphs["M"]!, "Н": baseGlyphs["H"]!,
        "О": baseGlyphs["O"]!, "Р": baseGlyphs["P"]!, "С": baseGlyphs["C"]!,
        "Т": baseGlyphs["T"]!, "Х": baseGlyphs["X"]!,
        "а": baseGlyphs["a"]!, "е": baseGlyphs["e"]!, "о": baseGlyphs["o"]!,
        "р": baseGlyphs["p"]!, "с": baseGlyphs["c"]!, "у": baseGlyphs["y"]!,
        "х": baseGlyphs["x"]!,
        // Greek lookalikes.
        "Α": baseGlyphs["A"]!, "Β": baseGlyphs["B"]!, "Ε": baseGlyphs["E"]!,
        "Ζ": baseGlyphs["Z"]!, "Η": baseGlyphs["H"]!, "Ι": baseGlyphs["I"]!,
        "Κ": baseGlyphs["K"]!, "Μ": baseGlyphs["M"]!, "Ν": baseGlyphs["N"]!,
        "Ο": baseGlyphs["O"]!, "Ρ": baseGlyphs["P"]!, "Τ": baseGlyphs["T"]!,
        "Χ": baseGlyphs["X"]!,
        "α": baseGlyphs["a"]!, "ε": baseGlyphs["e"]!, "ζ": baseGlyphs["z"]!,
        "η": baseGlyphs["n"]!, "ι": baseGlyphs["i"]!, "κ": baseGlyphs["k"]!,
        "ν": baseGlyphs["v"]!, "ο": baseGlyphs["o"]!, "ρ": baseGlyphs["p"]!,
        "τ": baseGlyphs["t"]!, "χ": baseGlyphs["x"]!, "ω": baseGlyphs["w"]!,
        "Б": ".###./.#.#./.###./.#.../.###./...../...../.....",
        "Г": ".#.../.#.../.#.../.#.../.###./...../...../.....",
        "Д": "#..../####./.#.#./.#.#./.#.#./.###./...../.....",
        "Ж": "#.##./.###./.###./.###./#.##./...../...../.....",
        "З": ".##../...#./..#../...#./.##../...../...../.....",
        "И": ".#.#./.#.#./..##./..##./...#./...../...../.....",
        "Й": ".#.#./.#.#./..##./..##./...#./...../...../.....",
        "Л": "#..#./.#.#./.#.#./.#.#./.###./...../...../.....",
        "П": "...#./...#./...#./...#./.###./...../...../.....",
        "Ф": "..#../.###./#.##./..##./..#../...../...../.....",
        "Ц": "####./#..#./#..#./#..#./#..#./...../...../.....",
        "Ч": "...#./...#./.###./...#./...#./...../...../.....",
        "Ш": ".###./..##./..##./..##./..##./...../...../.....",
        "Щ": "####./#..#./#..#./#..#./#..#./...../...../.....",
        "Ъ": ".###./.#.#./.###./.#.../.#.../...../...../.....",
        "Ы": "##.#./#.##./####./#..#./#..#./...../...../.....",
        "Ь": ".###./.#.#./.###./.#.../.#.../...../...../.....",
        "Э": ".##../...#./.###./...#./.##../...../...../.....",
        "Ю": "#.##./##.#./##.#./##.#./#.##./...../...../.....",
        "Я": ".#.#./.#.#./.###./.#.#./.###./...../...../.....",
        "б": ".##../...#./.#.#./.##../.#.../...../...../.....",
        "в": ".##../.#.#./.##../.##../...../...../...../.....",
        "г": ".#.../.#.../.#.../.##../...../...../...../.....",
        "д": ".###./.#.#./.#.#./.###./...../...../...../.....",
        "ж": "..##./.###./.###./..##./...../...../...../.....",
        "з": ".###./...#./..##./.##../...../...../...../.....",
        "и": ".#.#./.#.#./.###./...#./...../...../...../.....",
        "й": ".#.#./.#.#./.###./...#./..#../...../...../.....",
        "к": ".#.#./.##../.##../.#.#./...../...../...../.....",
        "л": "...#./.#.#./.#.#./.###./...../...../...../.....",
        "м": "#..../#.##./##.#./#..#./...../...../...../.....",
        "н": ".#.#./.#.#./.#.#./...#./...../...../...../.....",
        "п": ".#.#./.#.#./.#.#./.###./...../...../...../.....",
        "т": "..#../..#../..#../.##../...../...../...../.....",
        "ф": "..#../.###./..##./..##./.##../..#../...../.....",
        "ц": "...#./.###./...#./...#./...#./...../...../.....",
        "ч": "...#./..##./.#.#./...#./...../...../...../.....",
        "ш": ".###./..##./..##./..##./...../...../...../.....",
        "щ": "####./#..#./#..#./#..#./...../...../...../.....",
        "ъ": ".###./.#.#./.#.../.#.../...../...../...../.....",
        "ы": ".###./..##./...#./...#./...../...../...../.....",
        "ь": ".###./.#.#./.#.../...../...../...../...../.....",
        "э": ".##../...#./...#./.##../...../...../...../.....",
        "ю": "#.##./##.#./##.#./#.##./...../...../...../.....",
        "я": ".#.#./.###./.#.#./.###./...../...../...../.....",
        "Γ": "#####/....#/....#/....#/....#/....#/....#/.....",
        "Δ": "####./.#.#./.#.#./.##../..#../...../...../.....",
        "Θ": ".##../.#.#./.###./.#.#./.##../...../...../.....",
        "Λ": "#..#./.#.#./.#.#./.##../..#../...../...../.....",
        "Ξ": ".###./...../..#../...../.###./...../...../.....",
        "Π": "...#./...#./...#./...#./.###./...../...../.....",
        "Σ": ".###./.#.../..#../.#.../.###./...../...../.....",
        "Φ": "..#../.###./.###./.###./..#../...../...../.....",
        "Ψ": "..#../..#../.###./..##./..##./...../...../.....",
        "Ω": ".#.#./.#.#./.#.#./.###./...../...../...../.....",
        "γ": "..#../..#../.##../.#.#./#..#./...../...../.....",
        "δ": ".##../...#./.#.#./.##../.#.../...../...../.....",
        "θ": ".##../.#.#./.###./.#.#./.##../...../...../.....",
        "λ": "...#./.#.#./.##../..#../.#.../...../...../.....",
        "μ": ".###./.#.#./.#.#./...#./...../...../...../.....",
        "π": "...#./.#.../.#.#./...../...../...../...../.....",
        "σ": ".##../...#./.#.#./.###./...../...../...../.....",
        "φ": "..#../.###./..##./..##./.###./...../...../.....",
        "ψ": "..#../.##../..##./..##./..##./...../...../.....",
        // A few pictographs, so a warm note can sparkle. Drawn small, the way the matrix draws everything.
        "✨": "...../.#.#./..#../.#.#./...../...../...../.....",
        "💛": ".#.#./##.##/##.##/.###./..#../...../...../.....",
        "🌿": "...#./..##./.###./..##./...#./...../...../.....",
        "♥": ".#.#./##.##/##.##/.###./..#../...../...../.....",
        "★": "..#../.###./#####/.###./..#../...../...../.....",

    ]

    /// Builds an accented letter from the plain one and its marks.
    private static func compose(_ encoded: String, letter: Letter) -> String {
        var rows = encoded.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        while rows.count < GlyphFont.rows { rows.append(".....") }

        if let mark = letter.mark {
            let marks = mark.rows
            if letter.beside {
                // The letter reaches the top row itself, so the mark is laid beside the ascender
                // rather than over it — the only way a caron fits on a "d" in five dots.
                rows[0] = merge(rows[0], marks.upper)
                rows[1] = merge(rows[1], marks.lower)
            } else if letter.base.isUppercase {
                // A capital fills the rows a mark would need, so it steps down one dot.
                rows = ["....."] + Array(rows[0...6])
                rows[0] = marks.upper
            } else {
                rows[0] = marks.upper
                rows[1] = marks.lower
            }
        }
        if let tail = letter.tail { rows[7] = tail.row }
        return rows.joined(separator: "/")
    }

    /// Lays one row of dots over another, so a mark and an ascender can share a row.
    private static func merge(_ row: String, _ mark: String) -> String {
        let left = Array(row), right = Array(mark)
        var out = ""
        for column in 0..<GlyphFont.columns {
            let a = column < left.count ? left[column] : "."
            let b = column < right.count ? right[column] : "."
            out.append(a == "#" || b == "#" ? "#" : ".")
        }
        return out
    }

    /// The composed accented letters.
    private static let composedGlyphs: [Character: String] = accentedLetters.compactMapValues { letter in
        baseGlyphs[letter.base].map { compose($0, letter: letter) }
    }

    /// Every character the matrix can draw: the plain face, the accented letters composed from it,
    /// and the handful of letters no composition can make.
    public static let glyphs: [Character: String] = {
        var table = baseGlyphs
        for (character, shape) in composedGlyphs { table[character] = shape }
        for (character, shape) in drawnLetters { table[character] = shape }
        for (character, shape) in scriptGlyphs { table[character] = shape }
        return table
    }()

    /// The lit dots of a character, ready to draw. Parsed once from the face above.
    static let dots: [Character: [Dot]] = glyphs.mapValues { parse($0) }

    /// Dots used for anything the face has no shape for.
    public static let boxDots: [Dot] = parse(box)

    /// The lit dots to draw for a character. Unknown characters, and every non-ASCII character,
    /// get the missing-glyph box — the honest thing for a fixed face to do.
    /// Resolves a character to one the face can draw: itself when it has a shape, otherwise the
    /// base letter of its canonical decomposition (so an accented letter without its own glyph
    /// still lights up as the letter it is), or nil when nothing matches.
    public static func resolvedCharacter(for character: Character) -> Character? {
        if glyphs[character] != nil { return character }
        let decomposed = String(character).decomposedStringWithCanonicalMapping
        if let first = decomposed.first, glyphs[first] != nil { return first }
        if let lower = String(character).lowercased().first, glyphs[lower] != nil { return lower }
        return nil
    }

    /// Whether a character is an emoji — and therefore wants the real colour glyph rather than dots.
    public static func isEmoji(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.properties.isEmoji }
            && !character.unicodeScalars.allSatisfy { $0.value < 0x20 }
            && !character.isASCII
    }

    public static func litDots(for character: Character) -> [Dot] {
        if let resolved = resolvedCharacter(for: character), let d = dots[resolved] { return d }
        return boxDots
    }

    /// The dots to draw for a character in a style, with bold thickening and italic lean applied.
    ///
    /// Worked out once per character and style rather than every time it is drawn: a surface asks
    /// for these thousands of times in a single pass, and a note is redrawn on every keystroke.
    public static func placedDots(for character: Character, style: Style) -> [Placed] {
        if let resolved = resolvedCharacter(for: character), let p = placed[style]?[resolved] { return p }
        return placedBox[style] ?? []
    }

    private static let placed: [Style: [Character: [Placed]]] = {
        var table: [Style: [Character: [Placed]]] = [:]
        for style in Style.allCases {
            table[style] = dots.mapValues { place($0, style: style) }
        }
        return table
    }()

    private static let placedBox: [Style: [Placed]] = {
        var table: [Style: [Placed]] = [:]
        for style in Style.allCases { table[style] = place(boxDots, style: style) }
        return table
    }()

    /// Applies a strike to a shape: bold spreads the stroke sideways, italic leans the top of it.
    private static func place(_ base: [Dot], style: Style) -> [Placed] {
        guard style != .regular else {
            return base.map { Placed(column: Double($0.column), row: $0.row) }
        }

        var placed: [Placed] = []
        placed.reserveCapacity(base.count * (style.isBold ? 2 : 1))
        for dot in base {
            let lean = style.isItalic ? italicLean * Double(rows - 1 - dot.row) : 0
            placed.append(Placed(column: Double(dot.column) + lean, row: dot.row))
            // A heavier strike spreads sideways. The last column has nowhere to spread to.
            if style.isBold, dot.column + 1 < columns {
                placed.append(Placed(column: Double(dot.column + 1) + lean, row: dot.row))
            }
        }
        return placed
    }

    private static func parse(_ encoded: String) -> [Dot] {
        var result: [Dot] = []
        for (row, line) in encoded.split(separator: "/", omittingEmptySubsequences: false).enumerated() {
            for (column, marker) in line.enumerated() where marker == "#" {
                result.append(Dot(column: column, row: row))
            }
        }
        return result
    }
}
