import SwiftUI
import AppKit

/// Root view: optional note list + the writing surface + status bar.
///
/// The editor stays in the view tree at all times and the replay is layered on top of it. That
/// keeps the `NSTextView` (and its undo history, caret and scroll position) alive across replays.
public struct ContentView: View {

    @EnvironmentObject private var model: AppModel
    @ObservedObject private var replay = ReplayEngine.shared
    /// The window's undo stack, handed to the model so a deletion joins the typing's history.
    @Environment(\.undoManager) private var undoManager

    @AppStorage(ThemePreference.key) private var themeRawValue = Theme.system.rawValue
    @AppStorage(GlyphTintPreference.key) private var tintRawValue = GlyphTint.chalk.rawValue
    @AppStorage(MatrixSizePreference.key) private var pitch = MatrixSize.defaultPitch
    @AppStorage(UserNamePreference.key) private var userName = ""

    @State private var isWelcoming = true

    private var tint: GlyphTint { GlyphTintPreference.resolve(tintRawValue) }

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            if model.showsSidebar {
                SidebarView(model: model)
                    .frame(width: 230)
            }

            VStack(spacing: 0) {
                ZStack {
                    SourceEditor(model: model,
                                 isEditable: !replay.isReplaying && model.browsingFolder == nil,
                                 tint: tint)

                    if replay.isReplaying {
                        ReplayOverlay(engine: replay, tint: tint)
                    }

                    if isWelcoming, model.characterCount == 0, model.browsingFolder == nil {
                        WelcomeView { dismissWelcome() }
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }

                    if let browsing = model.browsingFolder {
                        FolderContentsView(path: browsing)
                            .transition(.opacity)
                    }

                    // Full view has no bar to hold a way out, so the way out floats over the
                    // note until it is wanted and then gets on with doing nothing.
                    if model.isFullView {
                        VStack {
                            HStack {
                                Spacer(minLength: 0)
                                FullViewExit { model.toggleFullView() }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !model.isFullView {
                    StatusBarView(
                        model: model,
                        themeRawValue: $themeRawValue,
                        tintRawValue: $tintRawValue
                    )
                }
            }
        }
        .frame(minWidth: 720, minHeight: 380)
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle(model.selectedNote?.title ?? "FewNote")
        .onAppear {
            ThemeApplier.apply(rawValue: themeRawValue)
            GlyphMatrix.Metrics.pitch = MatrixSize.snapped(pitch)
            model.undoManager = undoManager
        }
        .onChange(of: themeRawValue) { newValue in
            ThemeApplier.apply(rawValue: newValue)
        }
        .onChange(of: pitch) { newValue in
            GlyphMatrix.Metrics.pitch = MatrixSize.snapped(newValue)
        }
        // The greeting gets out of the way as soon as there is something to read.
        .onChange(of: model.characterCount) { count in
            if count > 0 { dismissWelcome() }
        }
        .alert("What should we call you?", isPresented: $model.wantsNameEditor) {
            TextField("Name", text: $userName)
                .onSubmit { saveName() }
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveName() }
        } message: {
            Text("A name — or a pet name — for the greeting on the way in. It is kept on this Mac and nowhere else.")
        }
        .alert("Restart to change the language?", isPresented: $model.wantsRelaunch) {
            Button("Later", role: .cancel) {}
            Button("Restart Now") { LanguagePreference.relaunch() }
        } message: {
            Text("The interface is read when FewNote starts, so the new language arrives with the next launch. Your notes are not touched either way.")
        }
    }

    private func saveName() {
        userName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dismissWelcome() {
        guard isWelcoming else { return }
        withAnimation(.easeInOut(duration: 0.35)) { isWelcoming = false }
    }
}

/// The way out of full view, tucked into the corner of the note until it is reached for.
///
/// It stays faint so that it does not sit on the writing like a button, and comes up to full
/// strength on hover so that it is unmistakable the moment it is wanted. The gesture is only half
/// of it: the View menu and ⇧⌘F do the same thing without the mouse.
struct FullViewExit: View {

    let leave: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovering = false

    var body: some View {
        Button(action: leave) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 22)
                .background(background, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovering ? Color.primary : Color.secondary)
        .opacity(isHovering ? 1 : 0.45)
        .onHover { isHovering = $0 }
        .help("Leave full view (⇧⌘F)")
        .accessibilityLabel("Leave full view")
    }

    /// The material goes when transparency does, which is what the setting is for.
    private var background: AnyShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
            : AnyShapeStyle(.ultraThinMaterial)
    }
}
