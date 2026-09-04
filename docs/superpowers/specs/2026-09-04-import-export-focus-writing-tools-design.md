# DayDream Import Export Focus and Writing Tools Design

## Objective

Add native document transfer and writing assistance without changing DayDream's Markdown source-of-truth model. Users can import Markdown or Word documents, export the current note as Markdown or Word, enter a sentence-focused writing mode, change inline color defaults from a compact menu, accept unobtrusive word completions with Tab, and use macOS spelling correction.

## Product Decisions

- Use AppKit and system frameworks only. Do not bundle Pandoc or a background service.
- Imported files become new `.md` notes inside the currently selected destination in the active library. The source file is never modified.
- Markdown import preserves source bytes when valid UTF-8 and copies the note into the library under a collision-free name.
- Word import converts readable document structure into portable Markdown. Version one supports paragraphs, headings 1–4, bulleted and numbered lists, bold, italic, links, and inline code where AppKit exposes the formatting. Unsupported Word layout such as floating text boxes, tracked-change metadata, and complex page geometry is flattened to readable text rather than represented as fake Markdown.
- Export never changes the current note or its library path. Markdown export writes the editor's current lossless Markdown. Word export produces an editable `.docx` with Letter portrait pages, black headings, readable body typography, and portable list formatting.
- Completion text is visual-only until accepted. It must never enter Markdown, undo history, autosave, selection, or accessibility text before Tab is pressed.
- Focus Mode and completion previews use temporary layout decoration, never persistent attributed-string semantics.

## Interface

### Sidebar Import

The sidebar header keeps Library on the left. On the right, Import, the existing sidebar toggle reservation, and Add are aligned to the same 30-point button grid. Import uses a simple downward-arrow/tray icon and opens a native file picker accepting `.md` and `.docx` files.

Successful import creates and selects the new note, refreshes the tree, opens it in the editor, and starts no rename operation. Errors appear through the existing sidebar error alert.

### Editor Top Controls

When a note is open, a compact overlay sits in the top-right safe area:

- Export opens a menu with Markdown and Word choices.
- A three-dot button to its right opens the writing-tools menu.

The controls use the existing muted palette, plain buttons, 32-point targets, and material background. They remain above editor content without reducing the text width.

### Writing Tools Menu

The menu contains:

- Focus Mode toggle.
- Text Color submenu using the same presets and setting as Settings.
- Highlight Color submenu using the same presets and setting as Settings.
- Word Completion toggle.
- Automatic Spelling Correction toggle.

All toggles and color selections persist in `EditorSettings`. Changing either color affects subsequent toolbar color actions exactly as the Settings page does.

## Components

### DocumentTransferService

A focused service owns import and export conversion:

- `importDocument(from:into:)` validates the extension, reads the source, converts when needed, creates a unique Markdown destination, and writes atomically.
- `exportMarkdown(_:to:)` writes UTF-8 atomically.
- `exportWord(markdown:to:)` builds an attributed document from `MarkdownDocumentCodec` and writes Office Open XML through `NSAttributedString.DocumentType.officeOpenXML`.
- Word import reads Office Open XML through AppKit, enumerates paragraphs and semantic attributes, and emits Markdown through the existing document and inline codecs.

Conversion logic remains independent from panels and SwiftUI so it can be unit tested with temporary files.

### FocusModeController

`DayDreamTextView` tracks a persisted `focusModeEnabled` setting. On selection or text changes it locates the sentence containing the caret using `NLTokenizer` sentence boundaries, with the current paragraph as a fallback for empty or unfinished sentences. It dims all other text using layout-manager temporary foreground attributes and restores the active sentence's normal themed colors. Disabling Focus Mode removes only its own temporary attributes.

### WordCompletionController

The text view queries `NSSpellChecker` after ordinary character edits when there is no marked text, selection, slash menu, or code block. It accepts only a completion beginning with the current partial word and stores the untyped suffix.

The suffix is drawn after the caret in a low-alpha foreground color. Tab inserts the suffix as one undoable edit. Completion has priority over list indentation; when no completion is visible, existing Tab and Shift-Tab list behavior remains unchanged. Escape, navigation, deletion, selection changes, document changes, and IME marked text clear the suggestion.

### Spelling Correction

The text view maps the persisted setting to AppKit's continuous spell checking and automatic spelling-correction properties. It remains disabled inside code blocks through the existing block-kind awareness where possible. The default is enabled for new installations.

## Data Flow

1. Import panel returns a URL.
2. `DocumentTransferService` creates a Markdown file in the library.
3. `WorkspaceStore` reloads and selects it; `DocumentController` opens it.
4. Export obtains `DayDreamTextView.exportMarkdown()` after flushing current editor state, then writes the chosen format to a save-panel URL.
5. Settings changes post the existing settings notification; the active text view reapplies focus, completion, and spelling behavior without reload.

## Error Handling and Safety

- Cancelled panels perform no work and show no error.
- Import rejects unsupported, unreadable, invalid UTF-8 Markdown, and invalid Word files without creating a partial note.
- Destination naming is collision-free and never overwrites an existing library note.
- Export confirms overwrite through `NSSavePanel` and uses atomic writes.
- Word conversion failure leaves both the source document and current note untouched.
- External-edit conflict protection remains authoritative for the current note.

## Verification

- Unit tests cover Markdown import byte preservation, Word-to-Markdown structure, unique import naming, Markdown export, Word export readability, and failure cleanup.
- UI/model tests cover header button alignment, export/menu availability, persisted settings, sentence-range selection, temporary focus attributes, completion generation and clearing, Tab priority, IME exclusion, and list Tab fallback.
- Generate a representative Word export containing headings, inline styles, lists, quote, and code; render it to PNG using the document verification workflow and inspect every page.
- Run the complete Swift test suite, release build, package the `.app`, gracefully restart DayDream, and verify the launched process uses the rebuilt binary.

## Acceptance Criteria

- Import is visible and aligned in the sidebar and successfully creates `.md` notes from `.md` and `.docx` sources.
- Export and three-dot controls are visible at the editor's upper right; export produces usable `.md` and `.docx` files.
- Focus Mode dims every sentence except the caret's current sentence without changing exported Markdown.
- Text and highlight color defaults can be changed from the three-dot menu and remain synchronized with Settings.
- A pale completion suffix appears for eligible partial words, Tab accepts it, and existing nested-list Tab behavior still works when no suggestion exists.
- Automatic spell correction is active when enabled and both writing-assistance settings persist.
- All automated and rendered-document checks pass, and the rebuilt application is running.
