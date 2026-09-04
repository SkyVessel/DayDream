# Markdown and Nested Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent nested Markdown library and Notion-style block editing to the existing native macOS DayDream editor.

**Architecture:** Keep `NSTextView` and TextKit 1 as the editing surface, with paragraph-level `MarkdownBlockKind` attributes and a pure codec for Markdown persistence. A SwiftUI `WorkspaceView` owns a filesystem-backed `WorkspaceStore`, renders the recursive sidebar, and bridges the selected note into `DayDreamTextView` without storing visible Markdown markers.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit/TextKit 1, Foundation, XCTest, macOS 14+

**Spec:** `docs/superpowers/specs/2026-09-04-markdown-sidebar-design.md`

## Global Constraints

- Preserve the existing smooth caret, light/dark themes, responsive page insets, and Cmd `+`/`-` zoom.
- Keep the deployment target at macOS 14 and add no JavaScript runtime or third-party package dependency.
- Store notes as UTF-8 `.md` files under `Application Support/DayDream/Library`.
- Never reveal consumed Markdown trigger characters when the caret returns to a formatted block.
- Do not intercept Space, Enter, or arrow keys while `NSTextInputClient.hasMarkedText()` is true.
- Preserve all pre-existing uncommitted work. Do not stage or commit an existing dirty hunk; implementation checkpoints remain uncommitted where changes overlap those files.

---

### Task 1: Markdown block model and disk codec

**Files:**
- Create: `Sources/DayDream/MarkdownDocument.swift`
- Create: `Tests/DayDreamTests/MarkdownDocumentTests.swift`

**Interfaces:**
- Produces: `enum MarkdownBlockKind: Equatable, Sendable`
- Produces: `struct MarkdownBlock: Equatable, Sendable { var kind: MarkdownBlockKind; var text: String }`
- Produces: `struct MarkdownDocument: Equatable, Sendable { var blocks: [MarkdownBlock] }`
- Produces: `enum MarkdownDocumentCodec { static func parse(_ source: String) -> MarkdownDocument; static func serialize(_ document: MarkdownDocument) -> String }`

- [ ] **Step 1: Write failing parsing tests**

```swift
func testParsesSupportedBlockPrefixesWithoutKeepingMarkers() {
    let source = "# One\n## Two\n### Three\n#### Four\n- Bullet\n1. Number\n- [ ] Open\n- [x] Done\nBody"
    XCTAssertEqual(MarkdownDocumentCodec.parse(source).blocks, [
        .init(kind: .heading(level: 1), text: "One"),
        .init(kind: .heading(level: 2), text: "Two"),
        .init(kind: .heading(level: 3), text: "Three"),
        .init(kind: .heading(level: 4), text: "Four"),
        .init(kind: .bullet, text: "Bullet"),
        .init(kind: .numbered, text: "Number"),
        .init(kind: .todo(checked: false), text: "Open"),
        .init(kind: .todo(checked: true), text: "Done"),
        .init(kind: .body, text: "Body"),
    ])
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter MarkdownDocumentTests`

Expected: compilation fails because `MarkdownDocumentCodec` and the block types do not exist.

- [ ] **Step 3: Implement the model and parser**

Implement line-based parsing with anchored prefixes only. Preserve blank lines as `.body` blocks and clamp headings to levels 1–4.

```swift
enum MarkdownBlockKind: Equatable, Sendable {
    case body
    case heading(level: Int)
    case bullet
    case numbered
    case todo(checked: Bool)
}
```

- [ ] **Step 4: Add failing serialization and round-trip tests**

```swift
func testSerializesBlocksAsPortableMarkdown() {
    let document = MarkdownDocument(blocks: [
        .init(kind: .heading(level: 2), text: "Title"),
        .init(kind: .todo(checked: true), text: "Ship"),
        .init(kind: .numbered, text: "First"),
    ])
    XCTAssertEqual(MarkdownDocumentCodec.serialize(document), "## Title\n- [x] Ship\n1. First")
}
```

- [ ] **Step 5: Implement serialization and verify GREEN**

Run: `swift test --filter MarkdownDocumentTests`

Expected: all codec tests pass, including empty input, blank lines, unknown Markdown, and no final-newline inflation.

- [ ] **Step 6: Create a safe checkpoint**

Run: `git diff --check -- Sources/DayDream/MarkdownDocument.swift Tests/DayDreamTests/MarkdownDocumentTests.swift`

Only if both paths were clean before this task, commit them with `git commit -m "feat: add markdown block codec"`; otherwise leave the verified changes unstaged.

### Task 2: Filesystem-backed nested workspace

**Files:**
- Create: `Sources/DayDream/WorkspaceStore.swift`
- Create: `Tests/DayDreamTests/WorkspaceStoreTests.swift`

**Interfaces:**
- Consumes: `MarkdownDocumentCodec`
- Produces: `enum WorkspaceNodeKind: Sendable { case folder, note }`
- Produces: `struct WorkspaceNode: Identifiable, Hashable, Sendable { let url: URL; let kind: WorkspaceNodeKind; var children: [WorkspaceNode]; var id: URL { url }; var name: String { url.deletingPathExtension().lastPathComponent } }`
- Produces: `@MainActor final class WorkspaceStore: ObservableObject`
- Required initializer: `init(rootURL: URL = WorkspaceStore.defaultRootURL(), autosaveDelay: TimeInterval = 0.35)`
- Required methods: `reload() throws`, `createNote(in parentURL: URL?) throws -> URL`, `createFolder(in parentURL: URL?) throws -> URL`, `rename(_ url: URL, to name: String) throws -> URL`, `select(_ url: URL?) throws`, `updateCurrentMarkdown(_ markdown: String)`, `flushPendingSave() throws`
- Required published state: `nodes: [WorkspaceNode]`, `selectedURL: URL?`, `currentMarkdown: String`, `errorMessage: String?`

- [ ] **Step 1: Write failing recursive scan tests**

```swift
func testReloadBuildsFolderFirstRecursiveTreeFromMarkdownFilesOnly() throws {
    let root = try makeTemporaryDirectory()
    try FileManager.default.createDirectory(at: root.appending(path: "Folder"), withIntermediateDirectories: true)
    try "# Nested".write(to: root.appending(path: "Folder/Nested.md"), atomically: true, encoding: .utf8)
    try "ignore".write(to: root.appending(path: "ignore.txt"), atomically: true, encoding: .utf8)
    let store = WorkspaceStore(rootURL: root, autosaveDelay: 0)
    try store.reload()
    XCTAssertEqual(store.nodes.map(\.name), ["Folder"])
    XCTAssertEqual(store.nodes[0].children.map(\.name), ["Nested"])
}
```

Define the test helper in `WorkspaceStoreTests.swift` so no production utility is introduced:

```swift
private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter WorkspaceStoreTests`

Expected: compilation fails because `WorkspaceStore` does not exist.

- [ ] **Step 3: Implement scanning and stable node identity**

Use standardized file URLs as IDs. Filter hidden entries and non-`.md` files. Sort folders before notes, then use localized case-insensitive name order.

- [ ] **Step 4: Add failing create-location and collision tests**

```swift
func testNewNoteUsesSelectedFoldersAndUniqueNames() throws {
    let folder = try store.createFolder(in: nil)
    let first = try store.createNote(in: folder)
    let second = try store.createNote(in: folder)
    XCTAssertEqual(first.deletingLastPathComponent(), folder)
    XCTAssertNotEqual(first.lastPathComponent, second.lastPathComponent)
}
```

- [ ] **Step 5: Implement create, sanitized rename, selection, and atomic save**

Use `Data.write(to:options: .atomic)` for saves. `select(_:)` flushes the old note before reading the new one. `updateCurrentMarkdown(_:)` schedules a cancellable main-queue work item; `flushPendingSave()` writes immediately.

- [ ] **Step 6: Verify persistence GREEN**

Run: `swift test --filter WorkspaceStoreTests`

Expected: recursive scan, selection, create target, unique naming, rename filtering, switching-save, and explicit flush tests pass.

- [ ] **Step 7: Create a safe checkpoint**

Run: `git diff --check -- Sources/DayDream/WorkspaceStore.swift Tests/DayDreamTests/WorkspaceStoreTests.swift`

Commit clean new paths with `git commit -m "feat: add persistent workspace store"`, or leave unstaged if their prior state was not clean.

### Task 3: Attributed document bridge and block-aware theme

**Files:**
- Create: `Sources/DayDream/MarkdownTextStorage.swift`
- Create: `Tests/DayDreamTests/MarkdownTextStorageTests.swift`
- Modify: `Sources/DayDream/Theme.swift`
- Modify: `Sources/DayDream/DayDreamTextView.swift`

**Interfaces:**
- Consumes: `MarkdownDocument`, `MarkdownBlockKind`
- Produces: `extension NSAttributedString.Key { static let dayDreamBlockKind: NSAttributedString.Key }`
- Produces: `enum MarkdownTextStorage { static func attributedString(from document: MarkdownDocument, appearance: NSAppearance, scale: CGFloat) -> NSAttributedString; static func document(from storage: NSAttributedString, fallbackKind: MarkdownBlockKind) -> MarkdownDocument }`
- Produces in theme: `static func textAttributes(for:scale:blockKind:) -> [NSAttributedString.Key: Any]`
- Produces in text view: `func load(markdown: String)`, `func exportMarkdown() -> String`, `var markdownDidChange: ((String) -> Void)?`

- [ ] **Step 1: Write failing document-to-storage tests**

```swift
func testAttributedStorageCarriesBlockKindAcrossEveryParagraph() {
    let document = MarkdownDocument(blocks: [
        .init(kind: .heading(level: 1), text: "Title"),
        .init(kind: .bullet, text: "Item"),
    ])
    let value = MarkdownTextStorage.attributedString(from: document, appearance: .init(named: .aqua)!, scale: 1)
    XCTAssertEqual(value.string, "Title\nItem")
    XCTAssertEqual(value.attribute(.dayDreamBlockKind, at: 0, effectiveRange: nil) as? MarkdownBlockKind, .heading(level: 1))
    XCTAssertEqual(value.attribute(.dayDreamBlockKind, at: 6, effectiveRange: nil) as? MarkdownBlockKind, .bullet)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter MarkdownTextStorageTests`

Expected: compilation fails because the storage bridge and block-aware theme overload do not exist.

- [ ] **Step 3: Implement storage conversion and block styles**

Use heading font sizes 34/28/23/20 at scale 1. Lists use a 28-point head indent and body font. Preserve `.dayDreamBlockKind` while reapplying font, foreground, kern, and paragraph style attributes.

- [ ] **Step 4: Add failing text-view load/export and theme-regression tests**

Assert that loading `"## Title\n- Item"` shows `"Title\nItem"`, exports the original Markdown, and still exports it after a zoom operation reapplies theme attributes.

- [ ] **Step 5: Implement load/export/callback bridge and verify GREEN**

Guard programmatic loads with `isLoadingDocument` so they do not call `markdownDidChange`. After user edits, serialize the visible attributed storage and call the closure.

Run: `swift test --filter 'MarkdownTextStorageTests|EditorViewTests'`

Expected: the new tests and all six baseline editor tests pass.

- [ ] **Step 6: Record an uncommitted checkpoint**

Run: `git diff --check -- Sources/DayDream/Theme.swift Sources/DayDream/DayDreamTextView.swift Sources/DayDream/MarkdownTextStorage.swift Tests/DayDreamTests/MarkdownTextStorageTests.swift`

Do not commit the already-dirty theme or text-view files; keep this checkpoint unstaged.

### Task 4: Markdown space triggers and Enter behavior

**Files:**
- Create: `Sources/DayDream/MarkdownEditingController.swift`
- Create: `Tests/DayDreamTests/MarkdownEditingControllerTests.swift`
- Modify: `Sources/DayDream/DayDreamTextView.swift`

**Interfaces:**
- Produces: `struct MarkdownTriggerResult: Equatable { let replacementRange: NSRange; let kind: MarkdownBlockKind }`
- Produces: `enum MarkdownEditingController { static func trigger(in:caretLocation:) -> MarkdownTriggerResult?; static func nextKind(after:currentText:) -> MarkdownBlockKind? }`
- `nextKind == nil` means an empty list exits without inserting another paragraph; headings return `.body`; non-empty list items return their continuing kind, with Todo reset to unchecked.

- [ ] **Step 1: Write failing trigger-table tests**

```swift
func testRecognizesOnlyCompleteMarkersAtParagraphStart() {
    let cases: [(String, MarkdownBlockKind)] = [
        ("#", .heading(level: 1)), ("####", .heading(level: 4)),
        ("-", .bullet), ("*", .bullet), ("1.", .numbered),
        ("[ ]", .todo(checked: false)), ("[]", .todo(checked: false)),
        ("[x]", .todo(checked: true)),
    ]
    for (source, kind) in cases {
        XCTAssertEqual(MarkdownEditingController.trigger(in: source, caretLocation: source.utf16.count)?.kind, kind)
    }
    XCTAssertNil(MarkdownEditingController.trigger(in: "text -", caretLocation: 6))
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter MarkdownEditingControllerTests`

Expected: compilation fails because the controller does not exist.

- [ ] **Step 3: Implement pure trigger and continuation rules**

Keep UTF-16 `NSRange` calculations inside the controller so AppKit indices remain correct for mixed Chinese and emoji text.

- [ ] **Step 4: Add failing integration tests against `DayDreamTextView`**

Insert marker characters followed by a space through `insertText`; assert the marker is removed and the paragraph carries the expected block kind. Invoke `insertNewline` on non-empty and empty list paragraphs and assert continuation/exit behavior.

- [ ] **Step 5: Override input commands minimally**

In `insertText(_:replacementRange:)`, allow `super` to handle normal text; consume a space trigger only when `hasMarkedText() == false`. In `doCommand(by:)`, handle `insertNewline:` only for supported blocks and otherwise call `super`.

- [ ] **Step 6: Verify GREEN and undo behavior**

Run: `swift test --filter 'MarkdownEditingControllerTests|EditorViewTests'`

Expected: triggers, Enter rules, Unicode offsets, one-step undo for conversion, and baseline typing/zoom tests pass.

- [ ] **Step 7: Record an uncommitted checkpoint**

Run: `git diff --check -- Sources/DayDream/MarkdownEditingController.swift Sources/DayDream/DayDreamTextView.swift Tests/DayDreamTests/MarkdownEditingControllerTests.swift`

Keep overlapping `DayDreamTextView.swift` changes unstaged.

### Task 5: List markers, interactive Todo, and empty-heading placeholders

**Files:**
- Create: `Sources/DayDream/BlockDecorationLayout.swift`
- Create: `Tests/DayDreamTests/BlockDecorationLayoutTests.swift`
- Modify: `Sources/DayDream/DayDreamTextView.swift`
- Modify: `Sources/DayDream/Theme.swift`

**Interfaces:**
- Produces: `struct BlockDecoration { let kind: MarkdownBlockKind; let characterRange: NSRange; let markerRect: NSRect; let label: String? }`
- Produces: `enum BlockDecorationLayout { static func numberedOrdinal(in storage: NSAttributedString, paragraphLocation: Int) -> Int; static func decorations(in textView: NSTextView, textContainerOrigin: NSPoint, scale: CGFloat) -> [BlockDecoration] }`

- [ ] **Step 1: Write failing consecutive-number and geometry tests**

Assert that numbered blocks separated by body text restart at 1, wrapped lines receive one marker only, and checkbox rectangles sit inside the list gutter rather than overlapping body text.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter BlockDecorationLayoutTests`

Expected: compilation fails because `BlockDecorationLayout` does not exist.

- [ ] **Step 3: Implement decoration layout and draw it**

Enumerate paragraph starts from attributed storage. Draw `•`, calculated ordinals, and rounded checkbox strokes in `DayDreamTextView.draw(_:)` using theme colors. Draw the heading placeholder only when the active paragraph is empty and has a heading kind.

- [ ] **Step 4: Add failing Todo hit-test tests**

Given a click point inside a Todo `markerRect`, expect the block kind to toggle; a point outside must not change attributes.

- [ ] **Step 5: Override mouse handling and verify GREEN**

Check Todo decoration rectangles before calling `super.mouseDown(with:)`. Toggle the custom block attribute, register an undo operation, refresh style, notify autosave, and redraw.

Run: `swift test --filter 'BlockDecorationLayoutTests|MarkdownTextStorageTests|EditorViewTests'`

Expected: numbering, checkbox hit testing, placeholders, theme preservation, and existing caret tests pass.

- [ ] **Step 6: Record an uncommitted checkpoint**

Run `git diff --check` on the four task paths and leave overlapping dirty files unstaged.

### Task 6: Slash command panel

**Files:**
- Create: `Sources/DayDream/SlashCommandPanel.swift`
- Create: `Tests/DayDreamTests/SlashCommandTests.swift`
- Modify: `Sources/DayDream/DayDreamTextView.swift`

**Interfaces:**
- Produces: `struct SlashCommand: Identifiable, Equatable { let title: String; let kind: MarkdownBlockKind }`
- Produces: `final class SlashCommandPanel: NSPanel`
- Required methods: `show(commands: [SlashCommand], selectedIndex: Int, screenAnchor: NSRect, onChoose: @escaping (MarkdownBlockKind) -> Void)`, `updateSelection(_ index: Int)`, `closePanel()`
- Required text-view state: `private var slashPanel`, `private var selectedSlashCommandIndex`

- [ ] **Step 1: Write failing command catalog and selection tests**

Assert the catalog contains exactly H1–H4, Bullet List, Numbered List, and Todo; Down wraps from last to first, Up wraps from first to last, Enter returns the selected kind, and Escape returns no selection.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter SlashCommandTests`

Expected: compilation fails because slash command types do not exist.

- [ ] **Step 3: Implement the nonactivating panel**

Use a borderless child `NSPanel` with rounded material-style content, an `NSStackView` of eight compact rows, and `firstRect(forCharacterRange:)` for the screen anchor. The panel must not steal first responder from the text view.

- [ ] **Step 4: Wire slash opening and keyboard handling**

After inserting `/`, open only when the current paragraph consists exactly of `/`. While open and not composing marked text, intercept `moveUp:`, `moveDown:`, `insertNewline:`, and `cancelOperation:`. Applying a command removes `/`, assigns the chosen block kind, updates typing attributes, and closes the panel.

- [ ] **Step 5: Verify GREEN**

Run: `swift test --filter 'SlashCommandTests|MarkdownEditingControllerTests|EditorViewTests'`

Expected: catalog/navigation/application tests and all existing keyboard tests pass.

- [ ] **Step 6: Record an uncommitted checkpoint**

Run `git diff --check` on the task paths and leave the overlapping text-view change unstaged.

### Task 7: Native Morphicons-compatible icon paths and recursive sidebar

**Files:**
- Create: `Sources/DayDream/DayDreamIcon.swift`
- Create: `Sources/DayDream/SidebarView.swift`
- Create: `Tests/DayDreamTests/SidebarModelTests.swift`
- Modify: `Sources/DayDream/Theme.swift`

**Interfaces:**
- Consumes: `WorkspaceStore`, `WorkspaceNode`
- Produces: `enum DayDreamIconName { case sidebar, folder, fileText, chevronRight, plus }`
- Produces: `struct DayDreamIcon: View`
- Produces: `struct SidebarRow: Equatable { let node: WorkspaceNode; let depth: Int }`
- Produces: `enum SidebarTreeProjection { static func rows(from nodes: [WorkspaceNode], expandedFolders: Set<URL>) -> [SidebarRow] }`
- Produces: `struct SidebarView: View { @ObservedObject var store: WorkspaceStore }`

- [ ] **Step 1: Write failing recursive-row projection tests**

Create a three-level `WorkspaceNode` tree and assert its visible-row projection respects expanded folder IDs, depth indentation, and selection. This keeps recursion testable without pixel assertions.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter SidebarModelTests`

Expected: compilation fails because the row projection and icon names do not exist.

- [ ] **Step 3: Implement icons and sidebar tree**

Encode the Lucide-compatible 24×24 stroke paths for Sidebar, Folder, FileText, ChevronRight, and Plus as native SwiftUI paths with round caps/joins and 1.7-point strokes. Add an attribution comment containing `https://www.morphicons.com` and the Lucide ISC source.

Render a 250-point sidebar with a header, disclosure animation, folder-first rows, selection tint, and a `+` menu for New Note/New Folder. New nodes enter inline rename; Return commits and Escape restores the generated name.

- [ ] **Step 4: Verify model GREEN and compile UI**

Run: `swift test --filter SidebarModelTests && swift build`

Expected: recursive projection tests pass and SwiftUI sidebar compiles without warnings.

- [ ] **Step 5: Create a safe checkpoint**

Run `git diff --check` on the task paths. Commit only previously-clean new files with `git commit -m "feat: add nested workspace sidebar"`; keep the dirty theme file unstaged.

### Task 8: Root integration, selection bridge, and autosave

**Files:**
- Create: `Sources/DayDream/WorkspaceView.swift`
- Create: `Tests/DayDreamTests/WorkspaceViewTests.swift`
- Modify: `Sources/DayDream/EditorView.swift`
- Modify: `Sources/DayDream/DayDreamApp.swift`

**Interfaces:**
- Consumes: `WorkspaceStore`, `SidebarView`, `DayDreamTextView.load(markdown:)`, `markdownDidChange`
- Produces: `struct EditorView: NSViewRepresentable { let markdown: String; let documentURL: URL?; let onMarkdownChange: (String) -> Void }`
- Produces: `struct WorkspaceView: View`

- [ ] **Step 1: Write failing editor bridge tests**

Mount `EditorView(markdown: "# Title", documentURL: noteURL, onMarkdownChange: ...)`, verify the view shows `Title`, then insert body text and verify the callback receives serialized Markdown. Change `documentURL` and verify the old content is replaced rather than appended.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter WorkspaceViewTests`

Expected: compilation fails because the new `EditorView` initializer and `WorkspaceView` do not exist.

- [ ] **Step 3: Implement the representable coordinator**

Configure AppKit objects only in `makeNSView`. In `updateNSView`, compare `documentURL` against the coordinator's loaded URL before calling `load(markdown:)`. Route `markdownDidChange` to the latest closure without creating a SwiftUI update loop.

- [ ] **Step 4: Compose the root workspace UI**

Use `@StateObject` for the store and `@State` for sidebar visibility. Keep a 40×40 top-left toggle available in both states, animate width/opacity over 160 ms, and reserve titlebar traffic-light space. When no note is selected, show a centered muted instruction to create or choose a note.

- [ ] **Step 5: Connect lifecycle flush**

Observe application termination and scene disappearance to call `flushPendingSave()`. Update `AppDelegate` focus logic so it focuses the text view only when a note is selected and does not steal focus from inline renaming.

- [ ] **Step 6: Verify GREEN and regressions**

Run: `swift test`

Expected: all codec, workspace, editor, sidebar, lifecycle, existing typing, inset, and zoom tests pass with zero failures.

- [ ] **Step 7: Record an uncommitted checkpoint**

Run `git diff --check` on all source and test paths. Do not commit the already-dirty app/editor files or any dependent new file that would leave committed HEAD uncompilable.

### Task 9: Package, launch, and requirement audit

**Files:**
- Modify only if a verified packaging defect requires it: `Scripts/package-app.sh`, `Scripts/Info.plist`

**Interfaces:**
- Consumes the completed application; produces no new application API.

- [ ] **Step 1: Run clean verification commands**

Run: `swift test`

Run: `swift build -c release`

Expected: both exit 0 with no compiler errors or test failures.

- [ ] **Step 2: Package and launch**

Run: `Scripts/package-app.sh`

Expected: the `.app` is assembled, opens, becomes active, and presents the workspace window.

- [ ] **Step 3: Perform the manual acceptance matrix**

Verify sidebar toggle; nested folder/note creation; inline rename; note switching; restart persistence; all eight slash commands; direct space triggers; heading placeholders; list continuation/exit; Todo click; Chinese IME; undo/redo; Cmd `+`/`-`; light/dark appearance.

- [ ] **Step 4: Audit the working tree**

Run: `git status --short` and `git diff --check`.

Expected: no whitespace errors, no generated `.app` or `.build` artifacts staged, and all original uncommitted debug changes still present unless their exact lines had to be integrated into the feature.
