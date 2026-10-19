import SwiftUI
import AppKit
import FewNoteKit

/// Saves everything on quit so nothing is lost even if the debounce has not fired yet.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        ReplayEngine.shared.stop()
        AppModel.shared.saveNow()
    }

    /// FewNote is a single-window notepad: closing the window ends the session rather than leaving
    /// an invisible, windowless app running.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Clicking the Dock icon brings the window back — otherwise the app can be left with no
    /// window and no way to get one, since the File menu has no "New Window".
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
                return true
            }
        }
        return true
    }
}

@main
struct FewNoteApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(ThemePreference.key) private var themeRawValue = Theme.system.rawValue
    @AppStorage(LanguagePreference.key) private var languageRaw = AppLanguage.system.rawValue

    init() {
        // The matrix's size is settled before anything is drawn, so a restored text size is in
        // force on the first frame rather than applied to a matrix that has already been laid out.
        MatrixSize.applyStored()
        // A chosen language is handed to the system before the interface is read for the next
        // launch. Nothing here can change the strings of this launch, which is why the menu offers
        // a restart.
        LanguagePreference.applyStored()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AppModel.shared)
                .onAppear { ThemeApplier.apply(rawValue: themeRawValue) }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
                    ReplayEngine.shared.stop()
                    AppModel.shared.saveNow()
                }
        }
        .defaultSize(width: 760, height: 540)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    AppModel.shared.createNote()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            // A note can leave the app as a picture of itself, which is the one export that keeps
            // its look: the dots, the glow, the colour and the theme are all in the PNG.
            CommandGroup(after: .saveItem) {
                Button("Save as Image…") {
                    EditorCommands.saveImage()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            // Our controls go into the system View menu rather than a second menu of the same
            // name, which is what `CommandMenu("View")` produces.
            CommandGroup(after: .toolbar) {
                Toggle("Show Note List", isOn: Binding(
                    get: { AppModel.shared.showsSidebar },
                    set: { AppModel.shared.showsSidebar = $0 }
                ))
                .keyboardShortcut("s", modifiers: [.command, .option])

                Toggle("Full View", isOn: Binding(
                    get: { AppModel.shared.isFullView },
                    set: { wants in
                        guard wants != AppModel.shared.isFullView else { return }
                        AppModel.shared.toggleFullView()
                    }
                ))
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Divider()

                Button("Replay Note") {
                    ReplayEngine.shared.toggle(attributed: AppModel.shared.currentAttributed)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Search Notes") {
                    AppModel.shared.showsSidebar = true
                    AppModel.shared.wantsSearchFocus = true
                }
                .keyboardShortcut("f", modifiers: [.command, .option])

                Divider()

                Button("Your Name…") {
                    AppModel.shared.wantsNameEditor = true
                }

                Divider()

                // Same three choices as the status bar control, reachable from the keyboard.
                Menu("Appearance") {
                    ForEach(Theme.allCases) { theme in
                        Toggle(theme.label, isOn: Binding(
                            get: { themeRawValue == theme.rawValue },
                            set: { isOn in if isOn { themeRawValue = theme.rawValue } }
                        ))
                    }
                }

                Menu("Language") {
                    ForEach(AppLanguage.allCases) { language in
                        Toggle(language.label, isOn: Binding(
                            get: { languageRaw == language.rawValue },
                            set: { isOn in
                                guard isOn else { return }
                                languageRaw = language.rawValue
                                LanguagePreference.applyStored()
                                AppModel.shared.wantsRelaunch = true
                            }
                        ))
                    }
                }
            }

            // The system's Format menu, filled in: the same commands the status bar offers, with
            // the shortcuts people already have in their fingers.
            CommandGroup(replacing: .textFormatting) {
                Button("Bold") { EditorCommands.toggleBold() }
                    .keyboardShortcut("b", modifiers: .command)

                Button("Italic") { EditorCommands.toggleItalic() }
                    .keyboardShortcut("i", modifiers: .command)

                Button("Underline") { EditorCommands.toggleUnderline() }
                    .keyboardShortcut("u", modifiers: .command)

                Button("Strikethrough") { EditorCommands.toggleStrikethrough() }

                Button("Bulleted List") { EditorCommands.toggleList() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Menu("Text Colour") {
                    ForEach(GlyphTint.allCases) { tint in
                        Button(tint.label) { EditorCommands.colourSelection(tint) }
                    }
                    Divider()
                    Button("Note Colour") { EditorCommands.clearSelectionColour() }
                }
            }

            // The Help menu has a real answer in it: what FewNote is, and what the keys do.
            CommandGroup(replacing: .help) {
                Button("FewNote Help") { HelpPanel.show() }
            }
        }
    }
}

/// A small window of help, native and off the disk: what FewNote is, and the keys a hand reaches
/// for. Kept short, because the note keeps getting typed; nothing here needs reading twice.
@MainActor
enum HelpPanel {

    static func show() {
        let alert = NSAlert()
        alert.messageText = "FewNote"
        alert.informativeText = """
            FewNote is a pad for writing: every character is drawn as a field of dots, the way an \
            old typewriter put ink down.

            ⌘N  New note
            ⌘R  Replay the note as a typewriter
            ⇧⌘F  Full View
            ⌥⌘S  Show or hide the note list
            ⌥⌘F  Search every note
            ⇧⌘L  Bulleted list · ⌘B Bold · ⌘I Italic
            ⇧⌘E  Save the note as an image

            In the note list, hover a folder for a new file, a new folder and more, double-click \
            a folder's name to rename it, and drag a note onto a folder to file it. Names are \
            their writing: the first line of a note is its name.
            """
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
