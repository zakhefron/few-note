import AppKit
import SwiftUI

/// The five colours a folder's or a note's name can be written in.
///
/// A colour is a hint for the sidebar and nothing more: it never reaches the folder or the note
/// itself, which stay exactly what they were. Five is enough to sort a list at a glance and few
/// enough that the colours stay apart in both appearances, which is the whole point of having them.
public enum LabelColour: String, CaseIterable, Identifiable, Sendable {
    case blue
    case purple
    case pink
    case orange
    case green

    public var id: String { rawValue }

    /// The colour's name, for the menu that gives names their colour.
    public var label: String {
        switch self {
        case .blue: String(localized: "Blue")
        case .purple: String(localized: "Purple")
        case .pink: String(localized: "Pink")
        case .orange: String(localized: "Orange")
        case .green: String(localized: "Green")
        }
    }

    public var nsColour: NSColor {
        switch self {
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .orange: .systemOrange
        case .green: .systemGreen
        }
    }

    /// The same colour in the interface. The system colours carry their own appearance, so a name
    /// keeps its identity in Light and in Dark alike.
    public var colour: Color { Color(nsColor: nsColour) }

    /// The colour as a small filled dot, drawn rather than made from a symbol.
    ///
    /// A menu draws a symbol as a template — one colour, the menu's own — which would throw away
    /// the one thing a colour menu has to show. A picture is drawn in its own colours instead.
    public var swatch: NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            let dot = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            nsColour.setFill()
            dot.fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// The colours a name can be given, as one submenu of whatever actions the row already offers.
///
/// Each colour is a toggle showing its own dot, so the colour in the menu is the colour on the
/// name. In use, it carries the tick.
struct LabelColourMenu: View {

    let current: LabelColour?
    let set: (LabelColour?) -> Void

    var body: some View {
        Menu {
            ForEach(LabelColour.allCases) { colour in
                Toggle(isOn: Binding(
                    get: { current == colour },
                    set: { isOn in if isOn { set(colour) } }
                )) {
                    Label {
                        Text(colour.label)
                    } icon: {
                        Image(nsImage: colour.swatch)
                    }
                }
            }

            Divider()

            Toggle(isOn: Binding(
                get: { current == nil },
                set: { isOn in if isOn { set(nil) } }
            )) {
                Label("Default", systemImage: "circle.dashed")
            }
        } label: {
            Label("Color", systemImage: "paintpalette")
        }
    }
}
