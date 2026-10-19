#!/bin/sh
# Builds FewNote and assembles a double-clickable FewNote.app bundle.
#
#   ./scripts/build.sh          # release build
#   ./scripts/build.sh debug    # debug build (faster to compile)
#
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${1:-release}"
# Only the app: FewNoteChecks uses `@testable import`, which a release build cannot compile.
swift build -c "$CONFIGURATION" --product FewNote
swift build -c "$CONFIGURATION" --product FewNoteIcon

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="build/FewNote.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/FewNote" "$APP_DIR/Contents/MacOS/FewNote"
strip -x "$APP_DIR/Contents/MacOS/FewNote" 2>/dev/null || true
cp scripts/Info.plist "$APP_DIR/Contents/Info.plist"

# The interface's languages. A .lproj directory is all AppKit needs to read a translation, so the
# seven of them are copied in as they are — no build step, and nothing to keep in sync. They live
# outside `Sources/` because they are shipped as they are, not compiled into anything.
for bundle in Resources/*.lproj; do
    [ -d "$bundle" ] || continue
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done

# The app icon, drawn by the app itself so it can never drift from the face it is made of.
"$BIN_DIR/FewNoteIcon" "$APP_DIR/Contents/Resources/AppIcon.icns"

# Ad-hoc signature so macOS treats it as a normal local app.
codesign --force --sign - "$APP_DIR" >/dev/null

echo "Built $APP_DIR"
echo "Run it with: open $APP_DIR"
