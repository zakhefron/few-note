// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FewNote",
    platforms: [.macOS(.v13)],
    targets: [
        // All app logic and views. A library target keeps the app entry point thin and makes
        // the logic importable by the check runner without any test framework dependency.
        .target(
            name: "FewNoteKit",
            path: "Sources/FewNoteKit"
        ),
        // The shipping app: just the @main entry point.
        .executableTarget(
            name: "FewNote",
            dependencies: ["FewNoteKit"],
            path: "Sources/FewNote"
        ),
        // Draws the app icon with the app's own face, at build time: `scripts/build.sh` runs it.
        // No image is checked in, so the mark can never drift away from the matrix it is made of.
        .executableTarget(
            name: "FewNoteIcon",
            dependencies: ["FewNoteKit"],
            path: "Sources/FewNoteIcon"
        ),
        // Dependency-free checks. Runs with Command Line Tools alone (no XCTest needed):
        //   swift run FewNoteChecks
        .executableTarget(
            name: "FewNoteChecks",
            dependencies: ["FewNoteKit"],
            path: "Sources/FewNoteChecks"
        )
    ]
)
