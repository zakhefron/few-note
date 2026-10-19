import SwiftUI
import AppKit

/// Compact bottom bar: the note's chips on the left, the note's date dead-centre, and the writing
/// controls on the right.
struct StatusBarView: View {

    @ObservedObject var model: AppModel
    @ObservedObject private var replay = ReplayEngine.shared

    @Binding var themeRawValue: String
    @Binding var tintRawValue: String

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            // The date sits dead-centre; the clusters pin to the edges, so changing their widths
            // never drags it off-axis.
            ZStack {
                NoteDateView(note: model.selectedNote)

                HStack(spacing: 3) {
                    ChipButton(
                        systemImage: "sidebar.left",
                        label: String(localized: "Note list"),
                        help: String(localized: "Show or hide the note list (⌥⌘S)"),
                        isActive: model.showsSidebar
                    ) {
                        model.showsSidebar.toggle()
                    }

                    ChipButton(
                        systemImage: "plus",
                        label: String(localized: "New note"),
                        help: model.canCreateNote
                            ? String(localized: "New note (⌘N)")
                            : String(localized: "Type something first — an empty note is not worth keeping"),
                        isEnabled: model.canCreateNote
                    ) {
                        // A new note lands in the list, so the list has to be there to see it.
                        model.showsSidebar = true
                        model.createNote()
                    }

                    Spacer(minLength: 10)

                    // The bar's right wing: how the writing is dressed — strike, colour and
                    // size standing in the bar themselves — the mechanism's pace, the way back
                    // from full view tucked beside the look it came from, and the theme.
                    FormatControls()
                    TintPicker(rawValue: $tintRawValue)
                    SizeControl()
                    TypewriterControl(model: model)
                    ChipButton(
                        systemImage: model.isFullView
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right",
                        label: fullViewLabel,
                        help: fullViewHelp,
                        isActive: model.isFullView
                    ) {
                        model.toggleFullView()
                    }

                    ChipMenu(
                        systemImage: Theme(rawValue: themeRawValue)?.symbolName ?? Theme.system.symbolName,
                        label: String(localized: "Appearance"),
                        help: "Appearance: \(Theme(rawValue: themeRawValue)?.label ?? Theme.system.label)"
                    ) {
                        ForEach(Theme.allCases) { option in
                            markedItem(option.label, isOn: option.rawValue == themeRawValue) {
                                themeRawValue = option.rawValue
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
    }

    /// The full view chip's own words, kept out of the view so the literals stay literal — which is
    /// what lets them be found and translated.
    private var fullViewLabel: String {
        model.isFullView ? String(localized: "Leave full view") : String(localized: "Full View")
    }

    private var fullViewHelp: String {
        model.isFullView
            ? String(localized: "Leave full view (⇧⌘F)")
            : String(localized: "Full view: just the note, nothing else (⇧⌘F)")
    }
}

/// The selected note's dates, dead-centre in the bar.
///
/// The bar shows when the note was written. Clicking it turns the display over to when it was
/// written to last, and the popover spells both out in full — which between them is the whole
/// question a date in a notepad is there to answer.
struct NoteDateView: View {

    var note: Note?

    @State private var showsUpdated = false
    @State private var isShowingDates = false
    @State private var now = Date()

    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        if note == nil {
            EmptyView()
        } else {
            Button {
                showsUpdated.toggle()
                isShowingDates = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(text)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help)
            .popover(isPresented: $isShowingDates, arrowEdge: .bottom) {
                dates
            }
            .accessibilityLabel(showsUpdated
                                ? String(localized: "Updated") + " " + Self.fullText(for: note?.modified)
                                : String(localized: "Created") + " " + Self.fullText(for: note?.created))
            .onReceive(tick) { now = $0 }
        }
    }

    private var createdText: String { Self.dateText(for: note?.created, now: now) }
    private var updatedText: String { Self.dateText(for: note?.modified, now: now) }

    /// The date and nothing else: the bar has one line to give it, and whether this is the writing
    /// or the last change is the thing the click turns over — the tooltip and the popover say which.
    private var text: String {
        guard note != nil else { return "" }
        return showsUpdated ? updatedText : createdText
    }

    private var help: String {
        guard note != nil else { return "" }
        return String(localized: "Created") + " " + Self.fullText(for: note?.created)
            + " · " + String(localized: "Updated") + " " + Self.fullText(for: note?.modified)
    }

    private var dates: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Created", date: note?.created)
            row("Updated", date: note?.modified)
        }
        .padding(14)
    }

    private func row(_ label: LocalizedStringKey, date: Date?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.fullText(for: date))
                    .font(.subheadline.monospacedDigit())
                if let date, date != .distantPast {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// A date as a note's reader wants it: the day and the month, the year only when it is not
    /// this one, and never a weekday.
    static func dateText(for date: Date?, now: Date = Date()) -> String {
        guard let date, date != .distantPast else { return "—" }
        let sameYear = Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
        return sameYear
            ? date.formatted(.dateTime.day().month(.abbreviated))
            : date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// The full date and time, for the tooltip and the popover.
    static func fullText(for date: Date?) -> String {
        guard let date, date != .distantPast else { return "—" }
        return date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
    }
}

/// Bold, italic and bullets: the note's basic styling.
///
/// Each control acts on the selection, or — with nothing selected — on the next characters typed,
/// which is how the controls double as an indicator of what is being written. The actions go
/// through the responder chain to the matrix, which is where the text and the selection actually
/// live.
struct FormatControls: View {

    @ObservedObject private var state = EditorState.shared

    var body: some View {
        HStack(spacing: 4) {
            chip("bold", label: String(localized: "Bold"), help: String(localized: "Bold (⌘B)"), isOn: state.style.isBold,
                 action: #selector(GlyphMatrixTextView.toggleBold(_:)))
            chip("italic", label: String(localized: "Italic"), help: String(localized: "Italic (⌘I)"), isOn: state.style.isItalic,
                 action: #selector(GlyphMatrixTextView.toggleItalic(_:)))
            chip("underline", label: String(localized: "Underline"), help: String(localized: "Underline (⌘U)"),
                 isOn: state.decor.contains(.underline),
                 action: #selector(GlyphMatrixTextView.toggleUnderline(_:)))
            chip("strikethrough", label: String(localized: "Strikethrough"), help: String(localized: "Strikethrough"),
                 isOn: state.decor.contains(.strike),
                 action: #selector(GlyphMatrixTextView.toggleStrikethrough(_:)))
            chip("list.bullet", label: String(localized: "Bulleted list"), help: String(localized: "Bulleted list (⇧⌘L)"), isOn: state.isBulleted,
                 action: #selector(GlyphMatrixTextView.toggleList(_:)))
        }
    }

    private func chip(_ symbol: String, label: String, help: String, isOn: Bool, action: Selector) -> some View {
        ChipButton(systemImage: symbol, label: label, help: help, isActive: isOn) {
            NSApp.sendAction(action, to: nil, from: nil)
        }
    }
}

/// The text size, on a chip of its own: the rail lives in a small leaf above the bar.
///
/// The strike and the colour stand in the bar themselves; the size is the one control that wants
/// a hand's width of rail, so it keeps a leaf — a small one, nothing in it but the size.
struct SizeControl: View {

    @AppStorage(MatrixSizePreference.key) private var pitch = MatrixSize.defaultPitch
    @State private var isShowingControls = false

    private var percent: Int { MatrixSize.percent(of: pitch) }
    private var range: ClosedRange<Double> { MatrixSize.percentRange() }
    private var isDefault: Bool { percent == MatrixSize.percent(of: MatrixSize.defaultPitch) }

    var body: some View {
        ChipButton(
            systemImage: "textformat.size",
            label: String(localized: "Text size"),
            help: String(localized: "Text size: from \(Int(range.lowerBound)) to \(Int(range.upperBound)) percent"),
            isActive: isShowingControls
        ) {
            isShowingControls.toggle()
        }
        .popover(isPresented: $isShowingControls, arrowEdge: .bottom) {
            controls
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Text size")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(percent)%")
                    .font(.callout.monospacedDigit().weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }

            Divider()

            // The size, in one line: named, stepped at both ends of the rail. The steps land on
            // whole percents at the setter.
            HStack(spacing: 8) {
                sizeStepper("minus", help: String(localized: "Smaller")) { step(-5) }

                Slider(value: Binding(get: { Double(percent) },
                                      set: { pitch = MatrixSize.pitch(forPercent: $0.rounded()) }),
                       in: range)
                    .controlSize(.regular)
                    .accessibilityLabel("Text size")
                    .accessibilityValue("\(percent) percent")

                sizeStepper("plus", help: String(localized: "Larger")) { step(5) }
            }

            HStack {
                Button {
                    pitch = MatrixSize.defaultPitch
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Reset to 100%")
                    }
                    .font(.caption)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isDefault ? Color.secondary : Color.accentColor)
                .disabled(isDefault)
                .help("Back to the ordinary size")

                Spacer()

                Text("\(Int(range.lowerBound))-\(Int(range.upperBound))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    /// A step at the rail's end: the same small symbol, ring-lit under the pointer.
    private func sizeStepper(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        RailButton(systemImage: symbol, edge: 20, help: help, action: action)
    }

    private func step(_ delta: Int) {
        let next = min(range.upperBound, max(range.lowerBound, Double(percent + delta)))
        pitch = MatrixSize.pitch(forPercent: next.rounded())
    }
}

/// The typewriter: a chip that opens the mechanism's one choice.
///
/// A replay plays at the pace the slider holds, and the slider is live: the engine reads the speed
/// on every tick, so moving it mid-replay takes at once. The play button sits at the slider's
/// right hand, where the hand that changed the pace is already resting.
struct TypewriterControl: View {

    @ObservedObject var model: AppModel

    @ObservedObject private var replay = ReplayEngine.shared
    @AppStorage(ReplayPreference.speedKey) private var speedRaw = TypingSpeed.normal
    @State private var isShowingControls = false

    private var speed: Double { TypingSpeed.clamped(speedRaw) }

    var body: some View {
        ChipButton(
            systemImage: "keyboard",
            label: String(localized: "Typewriter"),
            help: String(localized: "Typewriter: set the speed and retype this note"),
            isActive: replay.isReplaying || isShowingControls
        ) {
            isShowingControls.toggle()
        }
        .popover(isPresented: $isShowingControls, arrowEdge: .bottom) {
            controls
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Typewriter")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(TypingSpeed.description(speed))
                    .font(.callout.monospacedDigit().weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }

            Divider()

            // The pace, in one line: slow at the left, quick at the right, live all the while —
            // the engine reads the speed on every tick — and the play at the rail's end, where
            // the hand that moved it already rests.
            HStack(spacing: 10) {
                Image(systemName: "tortoise")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                // Clamped on the way in and out: a stored value from another version can never
                // pin the knob somewhere the engine would not honour.
                Slider(value: Binding(get: { speed },
                                      set: { speedRaw = TypingSpeed.clamped($0) }),
                       in: TypingSpeed.slowest...TypingSpeed.fastest)
                    .accessibilityLabel("Typing speed")
                Image(systemName: "hare")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                // The play, as a small round control of its own - the shape every media player
                // uses for the one action that starts and stops the whole mechanism.
                Button {
                    if replay.isReplaying {
                        replay.stop()
                    } else {
                        replay.replay(attributed: model.currentAttributed)
                    }
                } label: {
                    Image(systemName: replay.isReplaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.accentColor))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(replay.isReplaying ? "Stop the typewriter (Esc)" : "Start the typewriter (⌘R)")
                .accessibilityLabel(replay.isReplaying ? "Stop the typewriter" : "Start the typewriter")
            }

            Text(speed < 1
                 ? "Replay Speed — slower than usual. Each key takes its time."
                 : "Replay Speed — the note types itself out at a readable pace.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(width: 260)
    }
}

/// The note's colour, as a row of the colours themselves.
///
/// The swatches show the colour that will actually be drawn — resolved for the current theme —
/// so the choice is made by eye, and a swatch that would be invisible on this surface is never
/// offered. The chosen one is ringed and glowing, matching how it reads on the matrix.
///
/// With text selected, a click colours just that text; with nothing selected it sets the note's
/// own colour, which is what new writing will be drawn in.
struct TintPicker: View {

    @Binding var rawValue: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var state = EditorState.shared
    @State private var hovering: GlyphTint?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(GlyphTint.allCases) { tint in
                Button {
                    choose(tint)
                } label: {
                    swatch(tint)
                }
                .buttonStyle(.plain)
                .help("Text colour: \(tint.label)")
                .accessibilityLabel("Text colour: \(tint.label)")
                .accessibilityAddTraits(isChosen(tint) ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 20)
        .accessibilityElement(children: .contain)
    }

    /// A click colours the selection when there is one, and otherwise becomes the note's colour.
    private func choose(_ tint: GlyphTint) {
        if state.hasSelection {
            NSApp.sendAction(#selector(GlyphMatrixTextView.applyTint(_:)),
                             to: nil,
                             from: GlyphMatrixTextView.TintAction(tint))
        } else {
            rawValue = tint.rawValue
        }
    }

    /// The chosen swatch is the note's colour, or — straight after colouring a selection — the
    /// colour that was just applied.
    private func isChosen(_ tint: GlyphTint) -> Bool {
        tint.rawValue == rawValue
    }

    private func swatch(_ tint: GlyphTint) -> some View {
        let colour = Color(nsColor: tint.colour(darkMode: colorScheme == .dark))
        let chosen = isChosen(tint)
        let hovered = hovering == tint

        return Circle()
            .fill(colour)
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .strokeBorder(colour.opacity(chosen ? 0.95 : 0), lineWidth: 1.5)
                    .padding(-3.5)
            )
            .shadow(color: colour.opacity(chosen ? 0.7 : 0), radius: 3)
            .scaleEffect(hovered && !reduceMotion ? 1.18 : 1)
            .contentShape(Circle().inset(by: -4))
            .onHover { inside in
                if reduceMotion {
                    hovering = inside ? tint : (hovering == tint ? nil : hovering)
                } else {
                    withAnimation(.easeOut(duration: 0.12)) {
                        hovering = inside ? tint : (hovering == tint ? nil : hovering)
                    }
                }
            }
    }
}

/// A small, Apple-style icon button. Quiet by default, fills under the pointer, and tints
/// when its feature is active. Honours Reduce Motion (no hover animation in that case).
struct ChipButton: View {

    let systemImage: String
    let label: String
    var help: String?
    var isActive: Bool = false
    var isEnabled: Bool = true
    var tint: Color?
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            icon
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            if reduceMotion {
                isHovering = hovering
            } else {
                withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
            }
        }
        .help(help ?? label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 26, height: 20)
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isActive ? Color.accentColor.opacity(0.35)
                                 : Color.primary.opacity(isHovering ? 0.08 : 0),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var foreground: Color {
        guard isEnabled else { return .secondary.opacity(0.35) }
        if let tint { return tint }
        return isActive ? .accentColor : .secondary
    }

    private var background: Color {
        guard isEnabled else { return .clear }
        if isActive { return Color.accentColor.opacity(0.14) }
        return isHovering ? Color.primary.opacity(0.07) : Color.clear
    }
}

/// A `ChipButton` that opens a menu, styled identically so the bar reads as one control group.
struct ChipMenu<Content: View>: View {

    let systemImage: String
    let label: String
    var help: String?
    var isActive: Bool = false
    var tint: Color?
    @ViewBuilder var menu: () -> Content

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint ?? (isActive ? Color.accentColor : Color.secondary))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 36, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.14)
                                   : (isHovering ? Color.primary.opacity(0.07) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isActive ? Color.accentColor.opacity(0.35)
                                 : Color.primary.opacity(isHovering ? 0.08 : 0),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            // The SF Symbols would otherwise donate their own names to the menu's
            // accessibility title ("moon" reads as "Do Not Disturb").
            .accessibilityHidden(true)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering in
            if reduceMotion {
                isHovering = hovering
            } else {
                withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
            }
        }
        .help(help ?? label)
        .accessibilityLabel(help ?? label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

/// A menu item with a checkmark showing the active choice.
@ViewBuilder
func markedItem(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        if isOn {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}


