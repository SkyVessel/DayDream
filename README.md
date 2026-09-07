# DayDream

DayDream is a native macOS Markdown editor focused on a calm writing experience.

## v1.0.0

- Markdown headings, lists, task lists, quotes, code blocks, and dividers; `/` opens the style palette.
- Configurable keyboard toolbars: fonts, colors, highlights, and paragraph styles, applied to the selection or to subsequent typing.
- Elastic reveal and Falling Text typing effects, toggleable and adjustable.
- Image and video cards with drag layout and proportional scaling; web links appear as inline links with site icons.
- Focus, Ultra Focus, and Retype writing modes.
- Markdown / Word import and export, note and folder management, word count, and importable fonts.
- Style undo and redo; spell correction is off by default.

Requires macOS 14 or later. The initial release build targets Apple Silicon (arm64).

## Install

Download the DMG and drag DayDream to Applications, or unzip the ZIP and move the app.
The current release is signed with a local ad-hoc signature — it is not signed with a Developer ID or notarized by Apple. macOS may ask you to confirm in System Settings → Privacy & Security before opening; only do so after verifying the download source and checksums.

## Keyboard Shortcuts

- `⌘1` / `⌘2`: hold ⌘ and tap the number to preview tools; release ⌘ to apply.
- `⌘3`: reset to the default typing style. Existing custom shortcuts are preserved.
- `⌥⌘↑` / `⌥⌘↓`: enter / exit Ultra Focus.
- `⌃⌥R`: start / exit Retype.

Tools and shortcuts can be adjusted in Settings. Existing user preferences are never overwritten by new defaults.

## Document Format

Notes are saved as UTF-8 Markdown. Fonts, colors, highlights, and media use HTML fallbacks; support for CSS and video varies across Markdown readers. Media assets live in a `.daydream-assets` folder next to the note — keep it alongside the note when moving or backing up.

## Build & Package Locally

```bash
swift run
swift test --filter ToolbarPolishTests
./Scripts/package-app.sh --no-launch
```

`package-app.sh` launches the app after packaging; `--no-launch` only builds the bundle.
