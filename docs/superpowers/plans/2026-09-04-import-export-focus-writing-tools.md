# DayDream Import Export Focus and Writing Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add native Markdown and Word transfer, compact editor controls, sentence focus, synchronized color choices, ghost word completion, and spelling correction to DayDream.

**Architecture:** Keep conversion in a pure `DocumentTransferService`, persistent switches in `EditorSettings`, top-level panel coordination in `WorkspaceView`, and visual-only writing assistance in focused helpers consumed by `DayDreamTextView`. Reuse the existing Markdown codec and temporary layout attributes so focus and suggestions never alter saved Markdown.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, NaturalLanguage, UniformTypeIdentifiers, XCTest, native Office Open XML attributed-string support.

**Spec:** `docs/superpowers/specs/2026-09-04-import-export-focus-writing-tools-design.md`

## Global Constraints

- Target macOS 14 or newer and use system frameworks only.
- Imported sources are never modified; imported notes are written atomically under collision-free names.
- Markdown remains the source of truth; Focus Mode and completion previews must not mutate it.
- Completion must not run during IME marked-text composition or inside code blocks.
- Preserve all pre-existing dirty-worktree changes; do not stage or commit unrelated files.
- Word v1 preserves readable paragraphs, headings 1–4, lists, bold, italic, links, and code where AppKit exposes them; unsupported page-layout constructs flatten to readable text.

---

### Task 1: Persistent writing-tool settings and pure range logic

**Files:**
- Create: `Sources/DayDream/WritingTools.swift`
- Modify: `Sources/DayDream/EditorSettings.swift`
- Test: `Tests/DayDreamTests/WritingToolsTests.swift`
- Test: `Tests/DayDreamTests/EditorSettingsTests.swift`

**Interfaces:**
- Produces: `FocusSentenceResolver.range(in:caretLocation:) -> NSRange?`
- Produces: `WordCompletionResolver.suffix(partialWord:candidates:) -> String?`
- Produces: persisted `focusModeEnabled`, `wordCompletionEnabled`, and `automaticSpellingCorrectionEnabled` properties on `EditorSettings`.

- [ ] **Step 1: Write failing resolver and persistence tests**

```swift
func testFocusResolverReturnsSentenceContainingCaret() {
    XCTAssertEqual(
        FocusSentenceResolver.range(in: "First sentence. Second sentence!", caretLocation: 20),
        NSRange(location: 16, length: 16)
    )
}

func testCompletionReturnsOnlyUntypedSuffix() {
    XCTAssertEqual(
        WordCompletionResolver.suffix(partialWord: "hel", candidates: ["hello", "help"]),
        "lo"
    )
}
```

- [ ] **Step 2: Run focused tests and verify missing-type failures**

Run: `swift test --filter 'WritingToolsTests|EditorSettingsTests'`
Expected: FAIL because the resolver types and settings do not exist.

- [ ] **Step 3: Implement deterministic helpers and settings**

```swift
enum FocusSentenceResolver {
    static func range(in text: String, caretLocation: Int) -> NSRange? {
        // Use NLTokenizer(unit: .sentence), then fall back to the UTF-16 paragraph range.
    }
}

enum WordCompletionResolver {
    static func suffix(partialWord: String, candidates: [String]) -> String? {
        candidates.first { $0.count > partialWord.count &&
            $0.lowercased().hasPrefix(partialWord.lowercased())
        }.map { String($0.dropFirst(partialWord.count)) }
    }
}
```

Add three `UserDefaults` keys and `@Published` Boolean properties. Defaults: Focus Mode off, Word Completion on, Automatic Spelling Correction on. Each setter calls the existing `persist` helper.

- [ ] **Step 4: Run focused tests**

Run: `swift test --filter 'WritingToolsTests|EditorSettingsTests'`
Expected: PASS.

### Task 2: Native Markdown and Word conversion service

**Files:**
- Create: `Sources/DayDream/DocumentTransferService.swift`
- Create: `Tests/DayDreamTests/DocumentTransferServiceTests.swift`
- Modify: `Sources/DayDream/WorkspaceStore.swift`

**Interfaces:**
- Consumes: `MarkdownDocumentCodec.parse(_:)` and `MarkdownDocumentCodec.serialize(_:)`.
- Produces: `DocumentTransferService.importDocument(from:into:) throws -> URL`.
- Produces: `DocumentTransferService.exportMarkdown(_:to:) throws`.
- Produces: `DocumentTransferService.exportWord(markdown:to:) throws`.
- Produces: `WorkspaceStore.importDocument(from:) throws -> URL` to select and reload the new note.

- [ ] **Step 1: Write failing transfer tests**

```swift
func testMarkdownImportPreservesUTF8BytesAndUsesUniqueName() throws {
    let first = try service.importDocument(from: source, into: library)
    let second = try service.importDocument(from: source, into: library)
    XCTAssertEqual(try Data(contentsOf: first), try Data(contentsOf: source))
    XCTAssertEqual(second.lastPathComponent, "Source 2.md")
}

func testWordExportCanBeReadBackByAppKit() throws {
    try service.exportWord(markdown: "# Title\n\nBody **bold**", to: output)
    let value = try NSAttributedString(
        url: output,
        options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
        documentAttributes: nil
    )
    XCTAssertTrue(value.string.contains("Title"))
    XCTAssertTrue(value.string.contains("Body bold"))
}
```

Also cover DOCX-to-Markdown headings/lists/styles, invalid UTF-8 rejection, unsupported extension rejection, atomic failure cleanup, and Markdown export byte equality.

- [ ] **Step 2: Run focused tests and confirm failures**

Run: `swift test --filter DocumentTransferServiceTests`
Expected: FAIL because `DocumentTransferService` is missing.

- [ ] **Step 3: Implement transfer service**

```swift
@MainActor
final class DocumentTransferService {
    func importDocument(from source: URL, into directory: URL) throws -> URL
    func exportMarkdown(_ markdown: String, to destination: URL) throws
    func exportWord(markdown: String, to destination: URL) throws
}
```

Use `NSAttributedString(url:options:documentAttributes:)` with `.officeOpenXML` for Word input. Build export attributed strings paragraph-by-paragraph from the Markdown document, with Letter page size (`612 × 792` points), 72-point margins, black heading styles, 11.5-point body text, list indentation, and semantic inline traits. Write through `data(from:documentAttributes:)` using `.officeOpenXML` and `.atomic`.

For import, infer headings from font size/weight and paragraph outline metadata when available, infer lists from paragraph text/list markers, and serialize inline traits into standard Markdown. Strip only the terminal newline AppKit adds to the document.

- [ ] **Step 4: Integrate collision-free store import**

```swift
func importDocument(from source: URL) throws -> URL {
    beforeMutation?()
    let destinationDirectory = try validatedDirectory(parentForNewNode())
    let result = try transferService.importDocument(from: source, into: destinationDirectory)
    try reload()
    select(result)
    return result
}
```

Inject the service into `WorkspaceStore` with a production default so tests can use temporary directories.

- [ ] **Step 5: Run transfer and store tests**

Run: `swift test --filter 'DocumentTransferServiceTests|WorkspaceStoreTests'`
Expected: PASS.

### Task 3: Sidebar import and editor top controls

**Files:**
- Modify: `Sources/DayDream/DayDreamIcon.swift`
- Modify: `Sources/DayDream/SidebarView.swift`
- Modify: `Sources/DayDream/WorkspaceView.swift`
- Modify: `Sources/DayDream/WorkspaceCoordinator.swift` only if that type is split during current work; otherwise keep changes in `WorkspaceView.swift`.
- Test: `Tests/DayDreamTests/WorkspaceViewTests.swift`
- Test: `Tests/DayDreamTests/SidebarModelTests.swift`

**Interfaces:**
- Consumes: `WorkspaceStore.importDocument(from:)` and the three `DocumentTransferService` methods.
- Produces: `SidebarView.onImportDocument` action and `EditorTopControls` callbacks for Markdown export, Word export, and settings.

- [ ] **Step 1: Write failing UI model tests**

```swift
func testSidebarHeaderControlOrder() {
    XCTAssertEqual(SidebarHeaderControl.allCases, [.importDocument, .sidebar, .add])
}

func testEditorTopControlOrder() {
    XCTAssertEqual(EditorTopControl.allCases, [.export, .more])
}
```

Add a hosted-view test proving the top controls exist only for an open document and carry accessible labels.

- [ ] **Step 2: Run focused tests and confirm failures**

Run: `swift test --filter 'SidebarModelTests|WorkspaceViewTests'`
Expected: FAIL for missing control models and views.

- [ ] **Step 3: Add import/export/more icons and sidebar button**

Extend `DayDreamIconName` with `.importDocument`, `.exportDocument`, and `.more`. Add the import button immediately before the existing 30-point sidebar-toggle reservation so the right-side order is Import, Sidebar, Add. Use `NSOpenPanel` with `UTType.markdown` plus a DOCX type created from the filename extension.

- [ ] **Step 4: Add top-right controls and transfer panels**

Create a small `EditorTopControls` SwiftUI view in `WorkspaceView.swift`. Place it with a `ZStack(alignment: .topTrailing)` over `editorContent`, inset 14 points horizontally and 10 points vertically. Export presents Markdown and Word choices; each opens `NSSavePanel` with the current note name and appropriate extension, then calls the transfer service with `coordinator.textView?.exportMarkdown() ?? document.markdown`.

The More menu binds directly to `EditorSettings.shared` and supplies Focus Mode, Text Color, Highlight Color, Word Completion, and Automatic Spelling Correction.

- [ ] **Step 5: Run UI tests**

Run: `swift test --filter 'SidebarModelTests|WorkspaceViewTests'`
Expected: PASS.

### Task 4: Focus Mode visual behavior

**Files:**
- Modify: `Sources/DayDream/DayDreamTextView.swift`
- Modify: `Sources/DayDream/EditorView.swift`
- Test: `Tests/DayDreamTests/EditorViewTests.swift`

**Interfaces:**
- Consumes: `FocusSentenceResolver.range(in:caretLocation:)` and `EditorSettings.focusModeEnabled`.
- Produces: `DayDreamTextView.focusedSentenceRange` for test visibility and `refreshFocusMode()` for selection/text/settings changes.

- [ ] **Step 1: Write failing focus tests**

```swift
func testFocusModeDimsOutsideCurrentSentenceWithoutChangingMarkdown() {
    let view = makeTextView()
    view.load(markdown: "First sentence. Second sentence.")
    view.setSelectedRange(NSRange(location: 20, length: 0))
    view.setFocusModeEnabled(true)
    XCTAssertEqual(view.focusedSentenceRange, NSRange(location: 16, length: 16))
    XCTAssertEqual(view.exportMarkdown(), "First sentence. Second sentence.")
}
```

Also verify disabling clears the focus range, caret movement changes the active sentence, and empty paragraphs remain readable.

- [ ] **Step 2: Run focused test and confirm failure**

Run: `swift test --filter EditorViewTests/testFocusMode`
Expected: FAIL because focus APIs do not exist.

- [ ] **Step 3: Apply visual-only dimming**

Use layout-manager temporary `.foregroundColor` attributes only on the ranges before and after the active sentence, leaving the active sentence's original inline colors untouched. Track the exact ranges applied so refresh first removes only Focus Mode's temporary color. Call refresh from `didChangeText`, `setSelectedRange`, `load`, `settingsDidChange`, and appearance changes. Never add semantic attributes to `textStorage`.

- [ ] **Step 4: Run focus and Markdown preservation tests**

Run: `swift test --filter 'EditorViewTests|SourcePreservingMarkdownTests'`
Expected: PASS.

### Task 5: Ghost completion and spelling correction

**Files:**
- Modify: `Sources/DayDream/DayDreamTextView.swift`
- Test: `Tests/DayDreamTests/WritingToolsTests.swift`
- Test: `Tests/DayDreamTests/MarkdownEditingControllerTests.swift`
- Test: `Tests/DayDreamTests/EditorViewTests.swift`

**Interfaces:**
- Consumes: `WordCompletionResolver`, `NSSpellChecker`, and the three persisted settings.
- Produces: `DayDreamTextView.pendingCompletionSuffix`, `refreshWordCompletion()`, and `acceptPendingCompletion()`.

- [ ] **Step 1: Write failing completion behavior tests**

```swift
func testTabAcceptsPendingCompletionBeforeListIndentation() {
    let view = makeTextView()
    view.load(markdown: "hel")
    view.setPendingCompletionForTesting("lo")
    view.doCommand(by: #selector(NSResponder.insertTab(_:)))
    XCTAssertEqual(view.string, "hello")
    XCTAssertNil(view.pendingCompletionSuffix)
}

func testCodeBlockAndMarkedTextDoNotOfferCompletion() {
    let view = makeTextView()
    view.load(markdown: "```\nhel\n```")
    XCTAssertNil(view.completionRequest(at: 3))
}
```

Also test Escape/deletion/navigation clearing, case-insensitive prefix validation, no empty suffix, and existing list indentation when no completion is present.

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `swift test --filter 'WritingToolsTests|MarkdownEditingControllerTests|EditorViewTests'`
Expected: FAIL for missing completion APIs.

- [ ] **Step 3: Query AppKit and draw the ghost suffix**

Use `NSSpellChecker.shared.completions(forPartialWordRange:in:language:inSpellDocumentWithTag:)`. Derive the UTF-16 partial-word range with `rangeOfWord(at:)`, reject non-letter words and code blocks, then store only the suffix. In `draw(_:)`, draw the suffix immediately after the insertion point with the active font and `DayDreamTheme.text(...).withAlphaComponent(0.24)`.

- [ ] **Step 4: Wire command priority and correction settings**

At the start of `doCommand(by:)`, accept a pending suffix for Tab. If none exists, fall through to existing list indentation. Clear suggestions for Escape, cursor movement, selection, mouse interaction, delete, document load, focus loss, and marked text. Map the settings notification to `isContinuousSpellCheckingEnabled` and `isAutomaticSpellingCorrectionEnabled`; set both false while the caret is in a code block and restore them outside code.

- [ ] **Step 5: Run writing behavior tests**

Run: `swift test --filter 'WritingToolsTests|MarkdownEditingControllerTests|EditorViewTests'`
Expected: PASS.

### Task 6: Full verification, Word render QA, package, and restart

**Files:**
- Modify only if verification finds defects in files already listed above.
- QA artifact: a temporary representative `.docx` outside the repository.

**Interfaces:**
- Consumes all completed features.
- Produces a release-built and running `DayDream.app`.

- [ ] **Step 1: Run all automated checks**

Run: `git diff --check && swift test`
Expected: no whitespace errors and all tests pass.

- [ ] **Step 2: Generate and render a representative Word export**

Load the bundled workspace document dependencies. Immediately before generating the QA DOCX, run the document skill's `mark_artifact_operation_started.mjs` command exactly once with `--operation-kind create --expected-output-count 1 --output-format docx`. Generate a DOCX containing a title, four heading levels, bold/italic text, link, bullet list, numbered list, todo, quote, and code block through `DocumentTransferService.exportWord`.

Render it with the bundled `render_docx.py` into a temporary output directory, open every `page-*.png` at original detail, and verify no clipping, overlap, missing glyphs, broken lists, or incorrect page margins. Fix and repeat if any defect appears.

- [ ] **Step 3: Build, package, and restart**

Run: `osascript -e 'tell application "DayDream" to quit'` followed by `./Scripts/package-app.sh`.
Expected: release build succeeds and `open DayDream.app` launches the rebuilt binary.

- [ ] **Step 4: Audit every acceptance criterion**

Inspect source, focused tests, the rendered DOCX, the packaged binary timestamp, and the running process. Confirm each spec acceptance criterion has direct evidence before marking the goal complete.
