#!/usr/bin/env python3
"""Collects the user-facing string literals from FewNote's sources.

FewNote is localised with .lproj/Localizable.strings. SwiftUI's `Text("...")` and its friends
already use the literal as the key, so this exists to make sure nothing is missed when the
translations are written rather than to be run as part of a build: it is a workbench for the
translator, and the files it prints are pasted into `Resources/<lang>.lproj/`.

Usage:  python3 scripts/strings.py            # every literal
        python3 scripts/strings.py --count    # just how many
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# The SwiftUI and AppKit calls whose first string literal is shown to the user.
LEADING = [
    "Text", "Button", "Label", "Toggle", "Menu", "TextField", "navigationTitle",
    "alert", "help", "accessibilityLabel", "accessibilityHint", "prompt",
    "String(localized:", "LocalizedStringKey", "LabeledContent", "Link",
]
# Argument labels whose following literal is shown to the user.
LABELLED = ["label:", "help:", "title:", "message:", "systemImage:"]

PATTERNS = [
    re.compile(r'\b' + re.escape(call) + r'\s*\(?\s*"((?:[^"\\]|\\.)*)"') for call in LEADING
] + [
    re.compile(r'\b' + re.escape(label) + r'\s*"((?:[^"\\]|\\.)*)"') for label in LABELLED
    if label not in ("systemImage:",)
]

# Things that look like strings but are not shown: symbols, keys, identifiers, formats.
SKIP = re.compile(r'^[a-z0-9_.]+$|^FewNote|^com\.fewnote')


def literals_in(path: Path):
    text = path.read_text(encoding="utf-8")
    # Comments are not shown to anyone.
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    found = set()
    for pattern in PATTERNS:
        for match in pattern.finditer(text):
            value = match.group(1)
            if not value or SKIP.match(value):
                continue
            found.add(value)
    return found


def main():
    files = sorted(ROOT.glob("Sources/**/*.swift"))
    everything = set()
    for path in files:
        everything |= literals_in(path)
    ordered = sorted(everything)
    if "--count" in sys.argv:
        print(len(ordered))
        return
    for value in ordered:
        print(f'"{value}" = "{value}";')


if __name__ == "__main__":
    main()
