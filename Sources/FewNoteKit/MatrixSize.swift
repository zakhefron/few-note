import Foundation

/// How large the matrix is drawn.
///
/// Everything about the surface is a multiple of one number — the dot spacing — so "text size" is
/// simply a pitch. The size is chosen as a percentage: 30% at the smallest, 150% at the largest,
/// which is about a 4 × 6 point cell at one end and a 21 × 32 point cell at the other.
///
/// A whole percent is the step, so the slider's caption, the stored preference and the pitch all
/// agree: the pitch is the percentage, and nothing is rounded away in between.
public enum MatrixSize {

    /// The size FewNote has always drawn at: a 14 × 21 point cell, which the slides call 100%.
    public static let defaultPitch: Double = 7.0 / 3.0
    public static let minimumPercent: Double = 30
    public static let maximumPercent: Double = 150

    public static let minimumPitch: Double = defaultPitch * minimumPercent / 100
    public static let maximumPitch: Double = defaultPitch * maximumPercent / 100

    public static func clamped(_ pitch: Double) -> Double {
        guard pitch.isFinite else { return defaultPitch }
        return min(maximumPitch, max(minimumPitch, pitch))
    }

    /// The size as a whole percentage, which is the step the slider works in.
    public static func percent(of pitch: Double) -> Int {
        Int((clamped(pitch) / defaultPitch * 100).rounded())
    }

    /// Snaps to a whole percentage, so a size read back, written down and read again is the same.
    public static func snapped(_ pitch: Double) -> Double {
        Self.pitch(forPercent: Double(percent(of: pitch)))
    }

    public static func percentRange() -> ClosedRange<Double> {
        minimumPercent...maximumPercent
    }

    public static func pitch(forPercent percent: Double) -> Double {
        defaultPitch * min(maximumPercent, max(minimumPercent, percent)) / 100
    }

    /// The size the user last chose, snapped and clamped.
    public static func stored(in defaults: UserDefaults = .standard) -> Double {
        guard defaults.object(forKey: MatrixSizePreference.key) != nil else { return defaultPitch }
        return snapped(defaults.double(forKey: MatrixSizePreference.key))
    }

    /// Puts the stored size in force before anything is drawn.
    ///
    /// Called at launch so a restored text size is there from the first frame, rather than applied
    /// to a matrix that has already been laid out at another size.
    public static func applyStored(in defaults: UserDefaults = .standard) {
        GlyphMatrix.Metrics.pitch = CGFloat(stored(in: defaults))
    }
}

public enum MatrixSizePreference {
    public static let key = "FewNoteTextSize"
}
