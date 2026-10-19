#!/bin/sh
# FewNote installer — https://github.com/zakhefron/few-note
#
# There is no binary to download on purpose: an app moved onto a Mac by hand arrives
# quarantined, and an unsigned one is then refused by Gatekeeper ("Apple could not verify").
# An app built on the machine it lands on carries no quarantine — so this clones, builds
# here, and installs.
set -u

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31m✗ %s\033[0m\n' "$1"; exit 1; }

command -v git   >/dev/null 2>&1 || fail "git is required but not installed. Run: xcode-select --install"
command -v swift >/dev/null 2>&1 || fail "the Swift toolchain is required. Run: xcode-select --install (free, ~15 min)"

URL="https://github.com/zakhefron/few-note.git"
STAGE="$(mktemp -d)" || fail "could not create a temporary directory"
DIR="$STAGE/few-note"

step "Cloning FewNote…"
git clone --quiet --depth 1 "$URL" "$DIR" \
  || fail "the clone failed.
  If it says 'Could not resolve host: github.com', this Mac has no DNS servers.
  Fix it once with:  sudo networksetup -setdnsservers Wi-Fi 1.1.1.1 8.8.8.8"

step "Building (a minute or two the first time)…"
if ! (cd "$DIR" && ./scripts/build.sh >"$STAGE/build.log" 2>&1); then
    printf -- '--- last 25 lines of the build log ---\n'
    tail -25 "$STAGE/build.log"
    printf -- '-------------------------------------\n'
    fail "the build failed. The log is kept at $STAGE/build.log"
fi

step "Installing to /Applications…"
rm -rf /Applications/FewNote.app \
  || fail "could not remove the old app — quit FewNote if it is running, then rerun the installer"
cp -R "$DIR/build/FewNote.app" /Applications/ \
  || fail "could not copy the app to /Applications — try rerunning with: sudo sh"

step "Cleaning up…"
rm -rf "$STAGE"

step "Done. Launching FewNote…"
open /Applications/FewNote.app \
  || echo "The app is in /Applications — open it from Launchpad or Finder."
