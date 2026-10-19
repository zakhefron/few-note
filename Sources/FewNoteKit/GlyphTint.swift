import AppKit

/// The colour a note is written in — and the colour it glows.
///
/// The surface is a dot matrix, so a text colour has to work as *light*: vivid and bright on the
/// dark surface, deep and saturated on the light one, where the same hue would otherwise wash out
/// against near-white. Each choice therefore carries two colours, and the swatches show the one
/// actually in use, so the theme decides what the palette looks like and picking is done by eye.
public enum GlyphTint: String, CaseIterable, Identifiable {
    case chalk
    case ember
    case ice
    case lime
    case violet
    case rose

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .chalk: return String(localized: "Chalk")
        case .ember: return String(localized: "Ember")
        case .ice: return String(localized: "Ice")
        case .lime: return String(localized: "Lime")
        case .violet: return String(localized: "Violet")
        case .rose: return String(localized: "Rose")
        }
    }

    /// The colour the lit dots take, for the surface they are drawn on.
    ///
    /// On the dark surface these are light sources, so they are pale and bright; on the light
    /// surface they are ink, so they are the deep end of the same hue.
    public func colour(darkMode: Bool) -> NSColor {
        darkMode ? onDark : onLight
    }

    private var onDark: NSColor {
        switch self {
        case .chalk: return NSColor(srgbRed: 0.95, green: 0.96, blue: 0.97, alpha: 1)
        case .ember: return NSColor(srgbRed: 1.00, green: 0.50, blue: 0.18, alpha: 1)
        case .ice: return NSColor(srgbRed: 0.33, green: 0.79, blue: 0.95, alpha: 1)
        case .lime: return NSColor(srgbRed: 0.66, green: 0.89, blue: 0.20, alpha: 1)
        case .violet: return NSColor(srgbRed: 0.68, green: 0.56, blue: 1.00, alpha: 1)
        case .rose: return NSColor(srgbRed: 1.00, green: 0.44, blue: 0.55, alpha: 1)
        }
    }

    private var onLight: NSColor {
        switch self {
        case .chalk: return NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        case .ember: return NSColor(srgbRed: 0.72, green: 0.26, blue: 0.03, alpha: 1)
        case .ice: return NSColor(srgbRed: 0.04, green: 0.42, blue: 0.55, alpha: 1)
        case .lime: return NSColor(srgbRed: 0.28, green: 0.47, blue: 0.05, alpha: 1)
        case .violet: return NSColor(srgbRed: 0.42, green: 0.16, blue: 0.83, alpha: 1)
        case .rose: return NSColor(srgbRed: 0.73, green: 0.06, blue: 0.24, alpha: 1)
        }
    }

    /// Which palette colour a concrete colour came from, if any.
    ///
    /// A note on disk holds plain colours, but the surface draws with the palette, so a colour
    /// read back out of a file is matched to the tint it was written from. Anything that is not
    /// one of the palette's own colours — the black RTF leaves on unstyled text, or a colour
    /// pasted in from somewhere else — matches nothing and is drawn in the note's own colour.
    public static func matching(_ colour: NSColor, tolerance: CGFloat = 0.02) -> GlyphTint? {
        guard let source = colour.usingColorSpace(.deviceRGB) else { return nil }
        for tint in allCases {
            for darkMode in [true, false] {
                guard let candidate = tint.colour(darkMode: darkMode).usingColorSpace(.deviceRGB) else { continue }
                if abs(candidate.redComponent - source.redComponent) <= tolerance,
                   abs(candidate.greenComponent - source.greenComponent) <= tolerance,
                   abs(candidate.blueComponent - source.blueComponent) <= tolerance {
                    return tint
                }
            }
        }
        return nil
    }
}

public enum GlyphTintPreference {
    /// Shared `UserDefaults`/`@AppStorage` key.
    public static let key = "FewNoteGlyphTint"

    public static func resolve(_ rawValue: String) -> GlyphTint {
        GlyphTint(rawValue: rawValue) ?? .chalk
    }

    /// The chosen colour, for code that is not a view and cannot use `@AppStorage` — saving the
    /// note as a picture, for one.
    public static func stored(in defaults: UserDefaults = .standard) -> GlyphTint {
        resolve(defaults.string(forKey: key) ?? GlyphTint.chalk.rawValue)
    }
}
