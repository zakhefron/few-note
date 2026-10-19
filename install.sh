#!/bin/sh
# FewNote installer — https://github.com/zakhefron/few-note
set -e

URL="https://github.com/zakhefron/few-note/releases/download/v1.0/FewNote.dmg"
DMG="/tmp/FewNote.dmg"
VOL="/Volumes/FewNote"

echo "Downloading FewNote…"
curl -L --progress-bar -o "$DMG" "$URL"

echo "Mounting…"
hdiutil attach "$DMG" -nobrowse -quiet

echo "Installing to /Applications…"
rm -rf /Applications/FewNote.app
cp -R "$VOL/FewNote.app" /Applications/

echo "Cleaning up…"
hdiutil detach "$VOL" -quiet 2>/dev/null || true
rm -f "$DMG"
xattr -cr /Applications/FewNote.app

echo "Done. Launching FewNote…"
open /Applications/FewNote.app
