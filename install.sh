#!/bin/sh
# FewNote installer — https://github.com/zakhefron/few-note
#
# There is no binary to download on purpose: an app moved onto a Mac by hand arrives
# quarantined, and an unsigned one is then refused by Gatekeeper ("Apple could not verify").
# An app built on the machine it lands on carries no quarantine — so this clones, builds
# here, and installs.
#
# The sources and the build cache live in ~/Library/Caches/FewNote, so the first install
# compiles once — about a minute — and later installs rebuild only what changed, in seconds.
# The build is release, the same binary building from source produces; set FEWNOTE_DEBUG=1
# for a quicker rebuild after changing sources.
set -u

step() { printf '\033[1m▸ %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31m✗ %s\033[0m\n' "$1"; exit 1; }
elapsed() { printf '  (%ss)\n' "$(( $(date +%s) - $1 ))"; }

command -v git   >/dev/null 2>&1 || fail "git is required but not installed. Run: xcode-select --install"
command -v swift >/dev/null 2>&1 || fail "the Swift toolchain is required. Run: xcode-select --install (free)"

CACHE="$HOME/Library/Caches/FewNote"
URL="https://github.com/zakhefron/few-note.git"
CONFIG="release"
[ "${FEWNOTE_DEBUG:-}" = "1" ] && CONFIG="debug"

step "Fetching the sources into ~/Library/Caches/FewNote…"
if [ -d "$CACHE/.git" ]; then
    if git -C "$CACHE" fetch --quiet --depth 1 origin main &&
       git -C "$CACHE" reset --hard --quiet origin/main; then
        :
    else
        step "that cached copy is unusable; cloning afresh…"
        rm -rf "$CACHE"
    fi
fi
if [ ! -d "$CACHE/.git" ]; then
    git clone --quiet --depth 1 "$URL" "$CACHE" \
      || fail "the clone failed.
  If it says 'Could not resolve host: github.com', this Mac has no DNS servers.
  Fix it once with:  sudo networksetup -setdnsservers Wi-Fi 1.1.1.1 8.8.8.8"
fi

step "Building ($CONFIG — a minute or two the first time, seconds afterwards)…"
START=$(date +%s)
(cd "$CACHE" && ./scripts/build.sh "$CONFIG" >"$CACHE/build.log" 2>&1) || {
    printf -- '--- last 25 lines of the build log ---\n'
    tail -25 "$CACHE/build.log"
    printf -- '-------------------------------------\n'
    fail "the build failed. The full log is kept at $CACHE/build.log"
}
CONFIGURATION="$CONFIG" elapsed "$START"

step "Installing to /Applications…"
rm -rf /Applications/FewNote.app \
  || fail "could not remove the old app — quit FewNote if it is running, then rerun the installer"
cp -R "$CACHE/build/FewNote.app" /Applications/ \
  || fail "could not copy the app to /Applications — try rerunning with: sudo sh"

step "Done. Launching FewNote…"
open /Applications/FewNote.app \
  || echo "The app is in /Applications — open it from Launchpad or Finder."
