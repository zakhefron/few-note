import SwiftUI

/// The FewNote wordmark: the app's own name, set in the app's own face.
///
/// Drawn straight from `GlyphFont`, dot by dot, so the mark on the way in is unmistakably the
/// same matrix the writing happens on — not a logo of a typeface next to a typeface of dots.
struct Wordmark: View {

    var text: String = "FewNote"
    var dot: CGFloat = 2.6
    var spacing: CGFloat = 4.0
    var colour: Color = .primary

    private var width: CGFloat { CGFloat(text.count) * CGFloat(GlyphFont.columns + 1) * spacing - spacing }
    private var height: CGFloat { CGFloat(GlyphFont.rows) * spacing - spacing }

    var body: some View {
        Canvas { context, _ in
            var pen: CGFloat = 0
            for character in text {
                for lit in GlyphFont.litDots(for: character) {
                    let rect = CGRect(x: pen + CGFloat(lit.column) * spacing,
                                      y: CGFloat(lit.row) * spacing,
                                      width: dot,
                                      height: dot)
                    context.fill(Path(ellipseIn: rect), with: .color(colour))
                }
                pen += CGFloat(GlyphFont.columns + 1) * spacing
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

/// A warm hello on the way in.
///
/// It shows itself once the window is up, says what the place is, and gets out of the way — after
/// a few seconds, or the moment the user starts writing. It deliberately takes no clicks: the
/// surface underneath is already live, so a greeting can never be the thing standing between
/// someone and their first sentence.
struct WelcomeView: View {

    var onFinish: () -> Void

    @AppStorage(UserNamePreference.key) private var userName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowing = false

    var body: some View {
        VStack(spacing: 14) {
            Wordmark(colour: .primary)
                .shadow(color: .primary.opacity(0.25), radius: 6)

            VStack(spacing: 5) {
                Text(UserNamePreference.greeting(for: userName))
                    .font(.title3.weight(.semibold))
                Text("A quiet place to put things down.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("Start typing whenever you like — the dots will keep up.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.22), radius: 24, y: 8)
        .opacity(isShowing ? 1 : 0)
        .scaleEffect(isShowing || reduceMotion ? 1 : 0.96)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(UserNamePreference.greeting(for: userName)). A quiet place to put things down. Start typing whenever you like.")
        .onAppear {
            if reduceMotion {
                isShowing = true
            } else {
                withAnimation(.easeOut(duration: 0.45)) { isShowing = true }
            }
        }
        .task {
            // Long enough to read, short enough not to be in the way.
            try? await Task.sleep(nanoseconds: 5_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { onFinish() }
        }
    }
}
