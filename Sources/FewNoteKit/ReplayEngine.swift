import AppKit
import SwiftUI

public enum ReplayPreference {
    /// How fast a replay types.
    public static let speedKey = "FewNoteTypingSpeed"
}

/// How fast a replay types.
///
/// Everything is derived from a base delay that depends only on the length of the note, so a long
/// note is never retyped for a quarter of an hour. The speed slider then scales that delay, and
/// is read on every tick, so moving it changes the pace of a replay that is already running.
///
/// The slider is a fraction of the full pace: 1× is the way the note types itself out when it is
/// simply let go, and 0.1× takes its time over every key.
public enum TypingSpeed {

    public static let slowest = 0.1
    public static let fastest = 1.0
    public static let normal = 1.0

    /// Target duration for a whole note at 1×; the per-tick delay is derived from it.
    static let targetDuration: TimeInterval = 18
    /// A tick is never slower than this (a short note types briskly)…
    static let longestTick: UInt64 = 26_000_000
    /// …nor faster than this, so keystrokes stay visible.
    static let shortestTick: UInt64 = 2_000_000
    /// Bounds after the user's speed is applied. The slow end is capped so that even a long note
    /// stays watchable, and so that pushing the slider to the floor still leaves each key landing
    /// audibly apart.
    static let slowestScaledTick: UInt64 = 220_000_000
    static let fastestScaledTick: UInt64 = 1_000_000

    public static func clamped(_ speed: Double) -> Double {
        guard speed.isFinite else { return normal }
        return min(fastest, max(slowest, speed))
    }

    /// The delay between ticks, in nanoseconds.
    ///
    /// The count is the whole note's length, not the batch size: a long note reveals several
    /// characters per tick, which is what keeps its total duration bounded.
    public static func tickDelay(forCharacterCount count: Int, speed: Double) -> UInt64 {
        let characters = max(count, 1)
        let perCharacter = UInt64((targetDuration / Double(characters)) * 1_000_000_000)
        let base = min(longestTick, max(shortestTick, perCharacter))
        let scaled = Double(base) / clamped(speed)
        return min(slowestScaledTick, max(fastestScaledTick, UInt64(scaled)))
    }

    /// The speed the user last chose, clamped to the slider's range.
    public static func stored(in defaults: UserDefaults = .standard) -> Double {
        guard defaults.object(forKey: ReplayPreference.speedKey) != nil else { return normal }
        return clamped(defaults.double(forKey: ReplayPreference.speedKey))
    }

    // MARK: - Natural timing

    /// A typist is not a metronome. The gap between two keys wanders a little, and it opens up at
    /// the end of a sentence — which is most of what separates "a machine typing" from "someone
    /// typing". The wander is a fraction of the tick, so it stays in proportion at any speed.
    public static let jitterFraction = 0.22

    /// How much longer than a normal tick to wait after a character.
    ///
    /// The multiples are of the tick, not of a second, so a slow replay breathes slowly and a fast
    /// one does not stop dead at a full stop.
    public static func pauseFactor(after character: Character?) -> Double {
        guard let character else { return 1 }
        if character.isNewline { return 1.9 }
        switch character {
        case ".", "!", "?", "…", "。", "！", "？": return 2.2
        case ",", ";", ":", "—", "–", ")", "]": return 1.35
        default: return 1
        }
    }

    /// One tick as a person would leave it: paced, wandered, and with a beat where a person would
    /// take one.
    public static func naturalTick(_ tick: UInt64, after character: Character?) -> UInt64 {
        let paced = Double(tick) * pauseFactor(after: character)
        let wandered = paced * (1 + jitterFraction * Double.random(in: -1...1))
        return min(slowestScaledTick * 3, max(fastestScaledTick, UInt64(max(1, wandered))))
    }

    /// The speed as it reads on the control: "1×", "0.25×", "2.5×" — a multiplier, not a number.
    public static func description(_ speed: Double) -> String {
        var number = String(format: "%.2f", clamped(speed))
        while number.hasSuffix("0") { number.removeLast() }
        if number.hasSuffix(".") { number.removeLast() }
        return "\(number)×"
    }
}

/// Replays a note as a typewriter: characters appear one at a time with a short click.
///
/// The engine never touches the note's text or the file on disk — it only publishes how much of
/// it has been struck so far, which a read-only overlay renders. Because the real editor is
/// merely made non-editable underneath, undo history and the caret position survive a replay.
@MainActor
public final class ReplayEngine: ObservableObject {

    public static let shared = ReplayEngine()

    public init() {}

    /// The preferences this engine reads while it runs. Injectable so the checks can drive a
    /// scratch suite instead of the machine's own settings.
    var defaults: UserDefaults = .standard

    @Published public private(set) var isReplaying = false

    /// How much of the note has been struck so far, in UTF-16 units.
    @Published public private(set) var revealedCount = 0

    /// The note being retyped, styles and all. The overlay reveals a growing prefix of this, so
    /// a replay is drawn exactly as the note is written.
    public private(set) var source = NSAttributedString(string: "")

    private var task: Task<Void, Never>?

    

    public var visibleText: String {
        (source.string as NSString).substring(to: min(revealedCount, source.length))
    }

    public func toggle(attributed: NSAttributedString) {
        if isReplaying {
            stop()
        } else {
            replay(attributed: attributed)
        }
    }

    public func replay(text: String) {
        replay(attributed: NSAttributedString(string: text))
    }

    public func replay(attributed: NSAttributedString) {
        stop()
        guard attributed.length > 0 else { return }

        // A snapshot: the overlay reads this on every frame, and the caller may well have handed
        // over the editor's own storage, which keeps changing while the replay runs.
        source = NSAttributedString(attributedString: attributed)
        isReplaying = true
        revealedCount = 0
        let characters = Array(source.string)
        guard !characters.isEmpty else { return }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            // Respect the system setting: show the note at once rather than animating anything.
            revealedCount = attributed.length
            task = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled else { return }
                self?.finish()
            }
            return
        }

        // Long notes advance in small groups so the overlay doesn't re-render a huge string
        // thousands of times; short notes still advance one letter at a time.
        let batch = max(1, characters.count / 1200)

        task = Task { [weak self] in
            var index = 0
            while index < characters.count {
                if Task.isCancelled { return }
                let end = min(index + batch, characters.count)
                self?.reveal(upTo: Self.length(ofLast: end, in: characters, source: attributed))
                index = end
                // Re-read on every tick, so the speed slider takes effect mid-replay.
                let tick = TypingSpeed.tickDelay(forCharacterCount: characters.count,
                                                 speed: TypingSpeed.stored(in: self?.defaults ?? .standard))
                let delay = TypingSpeed.naturalTick(tick, after: characters[end - 1])
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        isReplaying = false
        revealedCount = 0
        source = NSAttributedString(string: "")
    }

    private func finish() {
        task = nil
        isReplaying = false
        revealedCount = 0
        source = NSAttributedString(string: "")
    }

    private func reveal(upTo count: Int) {
        guard count > revealedCount else { return }
        revealedCount = count
    }

    /// The UTF-16 length of a character count, which is not the same thing for anything outside
    /// the basic plane (an emoji is one character and two units).
    private static func length(ofLast count: Int, in characters: [Character],
                              source: NSAttributedString) -> Int {
        guard count < characters.count else { return source.length }
        return String(characters[0..<count]).utf16.count
    }
}

/// The typewriter stage: the same glyph matrix the note is written in, with the note struck out
/// cell by cell and a block caret at the typing point.
///
/// Because the replay renders through `GlyphMatrixTextView` — the very view the editor uses — a
/// replay looks exactly like writing: same font, same cells, same grid, same styles, same
/// wrapping. The note itself is untouched, so stopping halfway is always safe.
struct ReplayOverlay: View {

    @ObservedObject var engine: ReplayEngine
    /// The colour the note is written in, so a replay is drawn exactly like the editor.
    var tint: GlyphTint = .chalk

    var body: some View {
        ZStack(alignment: .bottom) {
            MatrixSurface(engine: engine, tint: tint)

            hint
                .padding(.bottom, 10)
        }
        .accessibilityLabel("Replaying note")
        // Escape stops the replay.
        .background(
            Button("Stop replay") { engine.stop() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }

    private var hint: some View {
        HStack(spacing: 6) {
            // The typewriter symbol is not in every system's set; a keyboard says the same thing.
            Image(systemName: "keyboard")
                .font(.system(size: 10, weight: .semibold))
            Text("Typing…")
            Text("Esc to stop").foregroundStyle(.tertiary)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(.thinMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .accessibilityHidden(true)
    }
}

/// The replay's read-only matrix. It is the editor's surface with the caret parked after the last
/// glyph typed so far.
struct MatrixSurface: NSViewRepresentable {

    @ObservedObject var engine: ReplayEngine
    var tint: GlyphTint = .chalk

    func makeNSView(context: Context) -> NSScrollView {
        let textView = GlyphMatrixTextView(width: 720, isEditable: false)
        textView.showsCaretCell = true
        textView.tint = tint
        return GlyphMatrixScrollView.wrapping(textView)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? GlyphMatrixTextView else { return }
        textView.fit(width: scrollView.contentSize.width, height: scrollView.contentSize.height)
        textView.tint = tint
        textView.reveal(engine.source, upTo: engine.revealedCount)
        // Follow the typing point the way the editor does.
        textView.scrollRangeToVisible(NSRange(location: engine.revealedCount, length: 0))
    }
}
