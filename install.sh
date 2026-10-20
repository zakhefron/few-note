#!/bin/sh
# FewNote installer — https://github.com/zakhefron/few-note
#
# There is no binary to download on purpose: an app moved onto a Mac by hand arrives
# quarantined, and an unsigned one is then refused by Gatekeeper ("Apple could not verify").
# An app built on the machine it lands on carries no quarantine — so this fetches the
# sources, builds here, and installs.
#
# The sources and the build cache live in ~/Library/Caches/FewNote: the first install
# compiles once (about a minute), and later installs rebuild only what changed, in
# seconds. The build is release, the same binary building from source produces; set
# FEWNOTE_DEBUG=1 for a quicker rebuild while changing sources.
set -u

CACHE="$HOME/Library/Caches/FewNote"
URL="https://github.com/zakhefron/few-note.git"
CONFIG="release"
[ "${FEWNOTE_DEBUG:-}" = "1" ] && CONFIG="debug"
SPIN=0
LAST=''

# Colour only when the runner is interactive; the brand amber is FewNote's own.
# The escapes are baked into the variables as real bytes, so they survive any printf %s.
AMBER='' GREEN='' RED='' DIM='' BOLD='' RESET=''
if [ -t 1 ]; then
    AMBER=$(printf '\033[38;5;208m') GREEN=$(printf '\033[32m') RED=$(printf '\033[1;31m')
    DIM=$(printf '\033[2m') BOLD=$(printf '\033[1m') RESET=$(printf '\033[0m')
fi

begin() { LAST="$1"; printf '  %s⋅%s %-34s' "$AMBER" "$RESET" "$1"; }

finish() { # $1 label, $2 seconds, $3 note — replaces the pending line
    [ -t 1 ] && printf '\r\033[K'
    printf '  %s✓%s %-34s' "$GREEN" "$RESET" "$1"
    [ -n "${2:-}" ] && printf '  %ss%s' "$2" "$RESET"
    [ -n "${3:-}" ] && printf '  · %s%s%s' "$DIM" "$3" "$RESET"
    printf '\n'
}

fail() { printf '\n  ✗ %s\n' "$1"; exit 1; }

spin() { # $1 = pid; animated progress bar + elapsed time
    local width=24 i=0 t0
    t0=$(date +%s)
    while kill -0 "$1" 2>/dev/null; do
        i=$(( (i + 1) % (width + 4) ))
        # Build a sliding block inside the bar
        bar=""
        j=0
        while [ $j -lt $width ]; do
            pos=$(( j - i + 4 ))
            if [ $pos -ge 0 ] && [ $pos -lt 4 ]; then
                bar="${bar}█"
            else
                bar="${bar}░"
            fi
            j=$((j + 1))
        done
        now=$(date +%s)
        elapsed=$(( now - t0 ))
        printf '\r\033[K  %s⋅%s %-34s%s[%s]%s  %ss' "$AMBER" "$RESET" "$LAST" "$AMBER" "$bar" "$RESET" "$elapsed"
        sleep 0.06
    done
}

printf '\n'
printf '  %s●%s %sFewNote%s %sinstaller%s\n' "$AMBER" "$RESET" "$BOLD" "$RESET" "$DIM" "$RESET"
printf '  %sthe dot-matrix notepad for macOS · builds from source · MIT%s\n\n' "$DIM" "$RESET"

# ---- toolchain ----------------------------------------------------------
begin "Toolchain"
if xcodebuild -version >/dev/null 2>&1; then
    SWIFT=$(swift --version 2>/dev/null | head -1 | sed 's/^Swift version //;s/^Apple Swift version /Swift /;s/ (swiftlang.*//')
    [ -n "$SWIFT" ] || fail "the Swift toolchain is not installed."
    XCV=$(xcodebuild -version 2>/dev/null | head -1)
    printf '%s  %s%s\n' "$XCV" "$SWIFT" "$RESET"
    BUILD_FROM_SOURCE=1
else
    printf 'Command Line Tools only - will download a prebuilt build%s\n' "$RESET"
    BUILD_FROM_SOURCE=0
fi

if [ "${BUILD_FROM_SOURCE:-0}" = "1" ]; then
# ---- sources ------------------------------------------------------------
begin "Fetching sources…"
START=$(date +%s)
NOTE=''
if [ -d "$CACHE/.git" ]; then
    OLD=$(git -C "$CACHE" rev-parse HEAD 2>/dev/null)
    if git -C "$CACHE" fetch --quiet --depth 1 origin main 2>/dev/null &&
       git -C "$CACHE" reset --hard --quiet origin/main 2>/dev/null; then
        NEW=$(git -C "$CACHE" rev-parse HEAD)
        [ "$OLD" = "$NEW" ] && NOTE='already current' || NOTE='updated'
    else
        # Offline or fetch failed: keep the cached sources and build those.
        NOTE='offline - using cached sources'
    fi
fi
if [ ! -d "$CACHE/.git" ]; then
    if git clone --quiet --depth 1 "$URL" "$CACHE" 2>/dev/null; then
        NOTE='fresh clone'
    else
        fail "the clone failed.
  If it says 'Could not resolve host: github.com', this Mac has no DNS servers.
  Fix it once with:  sudo networksetup -setdnsservers Wi-Fi 1.1.1.1 8.8.8.8
  Or download the zip manually from https://github.com/zakhefron/few-note"
    fi
fi
T=$(( $(date +%s) - START ))
finish "Sources" "$T" "$NOTE"

# ---- build --------------------------------------------------------------
begin "Building ($CONFIG)…"
START=$(date +%s)
(cd "$CACHE" && ./scripts/build.sh "$CONFIG" >"$CACHE/build.log" 2>&1) &
BPID=$!
spin "$BPID" &
SPINPID=$!
if ! wait "$BPID"; then
    kill "$SPINPID" 2>/dev/null
    wait "$SPINPID" 2>/dev/null
    printf '\r\033[K\n'
    printf '%s\n' '--- last 25 lines of the build log ---'
    tail -25 "$CACHE/build.log"
    printf '%s\n' '-------------------------------------'
    fail "the build failed. The full log is kept at $CACHE/build.log"
fi
kill "$SPINPID" 2>/dev/null
wait "$SPINPID" 2>/dev/null
printf '\r\033[K'
T=$(( $(date +%s) - START ))
finish "Build ($CONFIG) — the only slow step" "$T" \
    'first install builds once; afterwards this is seconds'


else
# ---- download prebuilt (no Xcode) --------------------------------------
RELEASE_URL="https://github.com/zakhefron/few-note/releases/latest/download/FewNote.zip"
begin "Downloading prebuilt build…"
START=$(date +%s)
TMPZIP="$CACHE/FewNote.zip"
rm -f "$TMPZIP"
curl -fsSL "$RELEASE_URL" -o "$TMPZIP" &
DLBPID=$!
spin "$DLBPID" &
SPINPID=$!
if ! wait "$DLBPID"; then
    kill "$SPINPID" 2>/dev/null
    wait "$SPINPID" 2>/dev/null
    printf '\r\033[K'
    fail "could not download the prebuilt build (404 = no release published yet).
  Either install Xcode to build from source, or ask the maintainer to run
  ./scripts/package.sh and upload build/FewNote.zip to GitHub Releases."
fi
kill "$SPINPID" 2>/dev/null
wait "$SPINPID" 2>/dev/null
    printf '\r\033[K'
rm -rf "$CACHE/FewNote.app"
unzip -q "$TMPZIP" -d "$CACHE" || fail "could not extract the build."
rm -f "$TMPZIP"
T=$(( $(date +%s) - START ))
finish "Downloaded prebuilt build" "$T" "no Xcode needed"
fi

# ---- install ------------------------------------------------------------
begin "Installing…"
START=$(date +%s)
rm -rf /Applications/FewNote.app \
  || fail "could not remove the old app — quit FewNote if it is running, then rerun the installer"
if [ "${BUILD_FROM_SOURCE:-0}" = "1" ]; then
    cp -R "$CACHE/build/FewNote.app" /Applications/ \
      || fail "could not copy the app to /Applications — try rerunning with: sudo sh"
else
    cp -R "$CACHE/FewNote.app" /Applications/ \
      || fail "could not copy the app to /Applications — try rerunning with: sudo sh"
    xattr -dr com.apple.quarantine /Applications/FewNote.app 2>/dev/null || true
fi
T=$(( $(date +%s) - START ))
finish "Installed → /Applications" "$T"

# ---- launch -------------------------------------------------------------
begin "Launching…"
if open /Applications/FewNote.app 2>/dev/null; then
    finish "Launched"
else
    finish "Ready in /Applications — open it from Launchpad"
fi

# ---- summary ------------------------------------------------------------
VER=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' \
      /Applications/FewNote.app/Contents/Info.plist 2>/dev/null || echo '?')
KB=$(du -sk /Applications/FewNote.app 2>/dev/null | cut -f1)
SIZE=$(awk "BEGIN{printf \"%.1f\", $KB/1024}" 2>/dev/null)
printf '\n'
printf '  %s✓ FewNote %s — %s MB on disk%s\n' "$GREEN" "$VER" "$SIZE" "$RESET"
printf '  %sOpen it, type, close it. That'"'"'s it.%s\n\n' "$DIM" "$RESET"
