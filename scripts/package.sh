#!/bin/sh
# Builds a release .app and zips it for GitHub Releases (no Apple license needed).
# Run on a Mac with Xcode, then upload build/FewNote.zip to the release.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh release
cd build
rm -f FewNote.zip
ditto -c -k --keepParent FewNote.app FewNote.zip
echo "Created build/FewNote.zip"
echo "Upload it to GitHub Releases as 'FewNote.zip'."
