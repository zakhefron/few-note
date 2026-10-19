import Foundation

/// The little counts the interface reads — "3 notes", "1 folder", "5 items" — in the language the
/// interface is set to. Each count is a catalogue key, so a count is translated the same way a
/// menu title is.
enum Counts {

    static func notes(_ n: Int) -> String {
        n == 1 ? String(localized: "1 note") : String(format: String(localized: "%lld notes"), n)
    }

    static func folders(_ n: Int) -> String {
        n == 1 ? String(localized: "1 folder") : String(format: String(localized: "%lld folders"), n)
    }

    static func items(_ n: Int) -> String {
        n == 1 ? String(localized: "1 item") : String(format: String(localized: "%lld items"), n)
    }
}
