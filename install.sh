#!/bin/sh
# FewNote installer — https://github.com/zakhefron/few-note
#
# There is no binary to download on purpose: an app moved onto a Mac by hand arrives
# quarantined, and an unsigned one is then refused by Gatekeeper ("Apple could not verify").
# An app built on the machine it lands on carries no quarantine — so this clones, builds
# here, and installs.
set -e

URL="https://github.com/zakhefron/few-note.git"
STAGE="$(mktemp -d)"
DIR="$STAGE/few-note"

echo "Cloning FewNote…"
git clone --quiet --depth 1 "$URL" "$DIR"

echo "Building (a minute or two the first time)…"
cd "$DIR"
./scripts/build.sh

echo "Installing to /Applications…"
rm -rf /Applications/FewNote.app
cp -R "$DIR/build/FewNote.app" /Applications/

echo "Cleaning up…"
rm -rf "$STAGE"

echo "Done. Launching FewNote…"
open /Applications/FewNote.app ||
  echo "The app is in /Applications — open it from Launchpad or Finder."
