# FewNote

An ultra-lightweight, native macOS notepad. Open it, type, close it. That's it.

FewNote's home on the web — with the one-line installer — is at
**[few-note-site.vercel.app](https://few-note-site.vercel.app)**.

Built with Swift and SwiftUI (plus a small amount of AppKit for the text surface). No third-party
packages, no web views, no accounts, no analytics, no network access.

## What it does

- **A real dot matrix, not a font on a grid** — every character is drawn dot by dot on a dim dot
  field, the way a Nothing-OS-style display or a split-flap board is lit. The text is never drawn:
  the dots are. The face is a 5 × 8 cell, hand-built: 104 plain shapes, 16 letters no composition
  can make (ß, ø, ł, đ…), and 117 accented letters composed from the plain face — 237 glyphs in
  all — so `café`, `über`, `Kraków` and `naïve` all light up as themselves.
- **Instant writing** — the editor is live from the first moment. A wordmark greets an empty
  library, and it is gone at the first keystroke; it never blocks the typing.
- **Nothing to learn** — no syntax, no markers, nothing to interpret. Smart quotes, dashes and text
  substitutions are off, so what you type is what is saved. A `#` is a `#`.
- **Styling that stays out of the way** — bold, italic, underline, strikethrough, bulleted lists,
  and a colour per run, from the Format menu or the status bar. Styling is stored as attributes,
  never as markup, so the note never gains characters it was not written with.
- **Notes are files** — each note is a plain `.rtf` file in a plain folder. Folders are plain
  directories, folders nest, and notes and folders can be dragged between them in the app.
- **Search** — a query searches across every note, case- and accent-insensitively, and shows the
  line it was found on.
- **The note's own date** — dead-centre in the bar: when the note was written, and a click turns
  the display over to when it was last touched, both spelled out in the popover.
- **Themes, colours and sizes** — System, Light and Dark; six ink colours for the runs; text size
  from 30 % to 150 %. Everything is a preference, held across launches, and the exported picture
  carries the same look.
- **Typewriter replay** — press ▶ and the note is retyped cell by cell, silently, at a chosen pace.
- **Save as Image** — a note can leave the app as a PNG of itself, drawn through the same matrix the
  editor draws on, so the dots, the glow, the colours and the theme are all in the picture.
- **Seven languages** — English, Spanish, French, German, Portuguese, Italian and Dutch, following
  the Mac by default.
- **Automatic saving** — edits are debounced (0.4 s) and written to disk, and flushed again on note
  switch, window close and quit. Nothing blocks typing.
- **Essential editing** — selection, copy/paste, undo/redo, the find bar `⌘F` brings up, spell
  checking, and the standard macOS shortcuts.
- **Comfortable defaults** — Reduce Motion, Reduce Transparency and VoiceOver are respected
  throughout.

## The matrix

The surface is a grid of cells; each cell holds a 5 × 8 glyph box on a dot field one dot wider and
one dot taller than the glyph. The text system still lays the note out (so wrapping, selection, the
caret and find all behave), but the ink is invisible and the dots are drawn on top of it.

- **Bold** is a rightward double strike, clamped inside the 5-column box, with slightly heavier ink —
  the way a typewriter gets weight by hitting twice.
- **Italic** is a lean: the top of the glyph leans a little more than the foot.
- **Lists** are a `•` in the margin with a hanging indent, not a special character in the text.
- **Selection** keeps each glyph's own colour over the selection bar, so selecting never changes what
  the note looks like.
- **Glow** is a bloom pass baked into a cached bitmap keyed on the dot pitch, the theme and the text
  colour, so a screenful costs no more to draw than a plain one.

## Notes and folders on disk

```
~/Library/Application Support/FewNote/notes/
├── Note-<uuid>.rtf          # a note
├── Work/                    # a folder — just a directory
│   ├── Note-<uuid>.rtf
│   └── Inner/               # folders nest
├── .trash/                  # deleted notes, kept for undo and for the Finder
└── state.json               # which note, folder and list to restore
```

Notes are Rich Text (`.rtf`). `.txt` and `.md` files are still listed and open normally, and are
upgraded to Rich Text the first time they are saved. Deleting a note moves it into `.trash` rather
than erasing it, so Undo works and so a mistake is recoverable by hand.

A note's name is its first line, so renaming a note is not an outside edit — you type the note, and
the name follows the writing. Folders are named from outside: double-click a folder heading in the
view of its contents, hover it for the pencil, or rename from its menu in the rail.

## Status bar

Three clusters pinned to the edges, with the note's own date between them:

| | |
| --- | --- |
| **Left** | Note list (`⌥⌘S`) · New note (`⌘N` — which refuses while the draft is still empty) |
| **Centre** | The note's date: click it to turn created over to last-touched, both spelled out |
| **Right** | Bold · Italic · Underline (`⌘U`) · Strikethrough · Bulleted list · six ink swatches · size chip (`30–150%`) · typewriter chip · Full View (`⇧⌘F`) · Appearance |

The sidebar is a tree: a "Notes" root with as many folders and subfolders as you like, and the
notes that live inside them — every row an icon and a name, folders with the folder's mark, notes
with the file's. Hovering a folder row shows a "+", a folder+ and a ⋯; the chevron folds and
unfolds. Dragging a note or a folder files it where it lands, and a right-click does the same as
the ⋯ button.

Clicking a folder opens the folder view: its subfolders first, as cards, then its notes — a card is
a kind, a name, a preview and a date, the way Apple Notes shows them. Cards open, drag to file,
carry a colour, and are trashed from their hover; a new note or a new folder is a button at the top
of the view.

A new note is a draft until something is typed in it: it lives in the rail greyed, and only
entering words makes it a file. An abandoned draft leaves nothing behind, so the library cannot
fill with empty notes.

## Typewriter replay

Press ▶ (or `⌘R`) and the note is retyped, character by character, with the caret advancing and the
source untouched underneath, so stopping half-way is always safe (`Esc` stops). The replay is drawn
through the very view the editor uses, so it looks exactly like writing — and it is quiet: the
mechanism plays no sounds.

The pace is a person's, not a metronome's: the gap between two keys wanders a little, and it opens
up at a full stop, at a comma and at the end of a line. The speed slider scales it all — 0.1× to
1× — is read on every tick, so moving it changes a replay already running, and the round play
button beside it starts and stops the mechanism.

## Save as Image

`File ▸ Save as Image…` (`⇧⌘E`) writes a PNG of the note. It is not a screenshot: the note is drawn
again, through the same matrix the editor draws on, so the picture carries the dot field, the bloom,
each run's own colour, the text size and the theme. What is left out is everything that is not the
note — no window, no toolbar, no caret.

The picture is a card: a rounded panel with a margin, a hairline, and the note's own background. It
is drawn at 2×, and it hugs the writing — a longer line makes a wider picture, up to the point where
a note reads better wrapped.

## Languages

The interface ships in English, Spanish, French, German, Portuguese, Italian and Dutch, and follows
the Mac by default. `View ▸ Language` picks one; a language is listed in its own language.

AppKit reads a language once, when the app starts, so a change arrives with the next launch — the
menu offers to restart for you. Your notes are never touched either way: the language changes what
the app is called, not what is written on the matrix.

Translations are plain `.lproj/Localizable.strings` files in `Resources/`, copied into the app as
they are. `scripts/strings.py` lists every user-facing literal in the sources, which is how the
catalogue is kept complete.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘N` | New note |
| `⇧⌘E` | Save the note as an image |
| `⌘R` | Replay the note |
| `Esc` | Stop a replay |
| `⌥⌘S` | Show or hide the note list |
| `⌥⌘F` | Search the notes |
| `⇧⌘F` | Full View |
| `⌘B` / `⌘I` | Bold / italic |
| `⌘U` | Underline |
| `⇧⌘L` | Bulleted list |
| `⌘Z` / `⇧⌘Z` | Undo / redo |
| `⌘A`, `⌘C`, `⌘V`, `⌘X` | Select all, copy, paste, cut |
| `⌘F` | Find |

## Install

One line — it clones, builds on this Mac, and puts the app in `/Applications`:

```sh
curl -fsSL https://raw.githubusercontent.com/zakhefron/few-note/main/install.sh | sh
```

There is no binary download on purpose: an app moved onto a Mac by hand arrives quarantined, and
an unsigned one is then refused by Gatekeeper ("Apple could not verify"). An app built on the
machine it lands on carries no quarantine, so it opens as itself.

## Build and run

Requires macOS 13+ and the Swift toolchain (Xcode or Command Line Tools).

```sh
git clone https://github.com/zakhefron/few-note.git
cd few-note
./scripts/build.sh          # release build -> build/FewNote.app
open build/FewNote.app      # run it
```

`./scripts/build.sh debug` produces a faster debug build. The app is ad-hoc signed, so it runs as a
normal local app without a developer certificate.

## Checks

Logic checks run without XCTest, so they work with Command Line Tools alone:

```sh
swift build --product FewNoteChecks
script -q /dev/null ./.build/debug/FewNoteChecks
```

(The `script` wrapper gives the runner a terminal, which is how the sample images it prints are
kept readable. `swift run FewNoteChecks` works too.)

883 checks, all measured rather than eyeballed. They cover grapheme-aware character and word
counting, title derivation, an autosave/relaunch round trip on a temporary directory, the Rich Text
round trip, folders (creation, nesting, renaming, moving, deleting to `.trash`) and search; the face
itself — every accented letter fits the five-dot box and places its mark on the right row, and none
of them quietly falls back to the missing-glyph box — and the matrix, rendered offscreen and
measured, where a bold glyph must strike more dots than a regular one and an italic must lean more
at the top than at the foot; the replay's pacing; the localisation files, key
by key, against the English base; and the exported picture, which must be a real PNG, wider for a
longer line, in the note's own colour and in the note's own theme. Exits non-zero on failure, so it
can be wired into CI.

The runner also writes sample images — a sheet of the face's styled text, a sheet of accents, and
an exported note — into the temporary directory, for looking at.

## Preferences

Held in `UserDefaults` under `com.fewnote.FewNote`:

`FewNoteTheme`, `FewNoteGlyphTint`, `FewNoteTextSize`, `FewNoteTypingSpeed`,
`FewNoteLanguage`, `FewNoteUserName`.

## Project layout

```
Sources/
├── FewNoteKit/                 # all app logic and views (library)
│   ├── AppModel.swift          # notes, folders, selection, counts, autosave, restore
│   ├── NoteLibrary.swift       # scanning notes and folders, search, drag payloads
│   ├── NoteDocument.swift      # the Rich Text round trip and the canvas attributes
│   ├── NoteText.swift          # character/word counting, note titles
│   ├── NoteImage.swift         # a note drawn as a PNG
│   ├── GlyphFont.swift         # the 5 × 8 face, and the accented letters composed from it
│   ├── GlyphMatrix.swift       # the dot-matrix surface: layout, dots, bloom, caret, typing
│   ├── GlyphTint.swift         # the ink colours, and the preference
│   ├── MatrixSize.swift        # text size, 30–150 %
│   ├── Theme.swift             # System/Light/Dark + appearance switching
│   ├── EditorState.swift       # bold/italic/underline/strike/list/colour, through the responder chain
│   ├── SourceEditor.swift      # the NSTextView-backed editor
│   ├── Sidebar.swift           # the folder list, notes, search, drag and drop, menus
│   ├── StatusBarView.swift     # the note's chips, its date, and the writing controls
│   ├── ReplayEngine.swift      # typewriter replay, live speed
│   ├── Language.swift          # the shipped languages and the preference
│   ├── Profile.swift           # the name the app calls you, for the greeting
│   ├── WelcomeView.swift       # the wordmark, drawn from the face itself
│   └── ContentView.swift       # window layout
├── FewNote/                    # the shipping app (@main + menu commands)
└── FewNoteChecks/              # dependency-free test runner
Resources/                      # the interface's .lproj translations
scripts/
├── build.sh                    # builds and assembles FewNote.app
├── strings.py                  # lists every user-facing string, for translating
└── Info.plist
```
