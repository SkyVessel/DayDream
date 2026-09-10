# DayDream

DayDream is a native macOS Markdown editor focused on a calm writing experience.

## v1.1.0

- Markdown headings, lists, task lists, quotes, code blocks, and dividers; `/` opens the style palette.
- Configurable keyboard toolbars: fonts, colors, highlights, and paragraph styles, applied to the selection or to subsequent typing.
- Elastic reveal and Falling Text typing effects, toggleable and adjustable.
- Image and video cards with drag layout and proportional scaling; web links appear as inline links with site icons.
- Focus, Ultra Focus, and Retype writing modes, including synchronized split-pane focus.
- Markdown / Word import and export, PDF reading, note and folder management, word count, and importable fonts.
- Spotlight-style library search, wiki links, backlinks, and `/page` / `/link page` note creation.
- Style undo and redo; spell correction is off by default.

Requires macOS 14 or later. The initial release build targets Apple Silicon (arm64).

## Install

Download the ZIP, unzip it, and move DayDream to Applications. The GitHub build is signed with a Developer ID certificate. A notarized release will carry an Apple notarization ticket after submission to the Apple notary service.

## Keyboard Shortcuts

- `⌘1` / `⌘2`: hold ⌘ and tap the number to preview tools; release ⌘ to apply.
- `⌘3`: reset to the default typing style. Existing custom shortcuts are preserved.
- `⌥⌘↑` / `⌥⌘↓`: enter / exit Ultra Focus.
- `⌃⌥R`: start / exit Retype.
- `⌥Space`: search the current library; `⌥Return` opens the selected result in the reference pane.
- `⌃⌥←` / `⌃⌥→`: move through note history.

Tools and shortcuts can be adjusted in Settings. Existing user preferences are never overwritten by new defaults.

## Document Format

Notes are saved as UTF-8 Markdown. Fonts, colors, highlights, and media use HTML fallbacks; support for CSS and video varies across Markdown readers. Media assets live in a `.daydream-assets` folder next to the note — keep it alongside the note when moving or backing up.

## Build & Package Locally

```bash
swift run
swift test --filter PageSearchRegressionTests
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" HARDENED_RUNTIME=1 ./Scripts/package-app.sh --no-launch
```

`package-app.sh` launches the app after packaging; `--no-launch` only builds the bundle. Without `SIGNING_IDENTITY`, it uses a local ad-hoc signature.
