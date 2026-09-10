import AppKit
import PDFKit
import XCTest
@testable import DayDream

@MainActor
final class SeptemberEnhancementTests: XCTestCase {
    private func editor(_ source: String) -> DayDreamTextView {
        let storage = NSTextStorage(), manager = TypingLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 600, height: 100000))
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        let view = DayDreamTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 700), textContainer: container)
        view.load(markdown: source)
        return view
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testEnglishDefaultPreservesExplicitLanguageAndShortcutDefaults() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(EditorSettings(defaults: defaults).language, .en)
        // Saved choices are verified through the public setting, not a hardcoded key.
        let settings = EditorSettings(defaults: defaults)
        settings.language = .zh
        XCTAssertEqual(EditorSettings(defaults: defaults).language, .zh)
        let shortcuts = ShortcutPreferences(defaults: defaults)
        XCTAssertEqual(shortcuts.shortcut(for: .underline).displayName, "⌘U")
        XCTAssertEqual(shortcuts.shortcut(for: .strikethrough).displayName, "⇧⌘X")
        XCTAssertEqual(shortcuts.shortcut(for: .toggleFocus).displayName, "⌃⌥F")
        XCTAssertEqual(shortcuts.shortcut(for: .resetWritingStyle).displayName, "⌘3")
    }

    func testTabAcceptsCompletionBeforeAllListHandlers() {
        for source in ["1. wor", "- wor", "- [ ] wor", "  1. wor"] {
            let view = editor(source)
            view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
            let kind = view.currentBlockKind(at: 0)
            view.completionSuffix = "d"
            view.doCommand(by: #selector(NSResponder.insertTab(_:)))
            XCTAssertEqual(view.string, "word", source)
            XCTAssertEqual(view.currentBlockKind(at: 0), kind)
        }
        let view = editor("1. item")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(view.currentListIndentation(at: 0), "  ")
    }

    func testDecorationsPersistAndResetSelectedTextWithoutChangingNeighbors() {
        let view = editor("left middle right")
        let range = NSRange(location: 5, length: 6)
        for (tool, key, visual) in [(WritingTool.underline, NSAttributedString.Key.dayDreamUnderline, NSAttributedString.Key.underlineStyle), (.strikethrough, .dayDreamStrikethrough, .strikethroughStyle)] {
            view.setSelectedRange(range)
            view.applyWritingToolToSelection(tool)
            XCTAssertEqual(view.textStorage!.attribute(visual, at: 5, effectiveRange: nil) as? Int, 1)
            let saved = view.exportMarkdown()
            let reopened = editor(saved)
            XCTAssertEqual(reopened.textStorage!.attribute(key, at: 5, effectiveRange: nil) as? Bool, true)
            view.applyWritingToolToSelection(tool)
            XCTAssertNil(view.textStorage!.attribute(key, at: 5, effectiveRange: nil))
            view.applyWritingToolToSelection(tool)
            view.applyWritingToolToSelection(.pink)
            view.resetSelectedAndTypingStyle()
            XCTAssertEqual(view.string, "left middle right")
            XCTAssertNil(view.textStorage!.attribute(key, at: 5, effectiveRange: nil))
            XCTAssertNil(view.textStorage!.attribute(.dayDreamTextColor, at: 5, effectiveRange: nil))
            XCTAssertEqual(view.textStorage!.attribute(visual, at: 5, effectiveRange: nil) as? Int ?? 0, 0)
            XCTAssertEqual(view.exportMarkdown(), "left middle right")
        }
    }

    func testDecorationShortcutsStyleSubsequentTypingAndResetShortcutClearsSelection() {
        let view = editor("")
        let preferences = ShortcutPreferences.shared
        func event(_ command: ShortcutCommand) -> NSEvent {
            let shortcut = preferences.shortcut(for: command)
            return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shortcut.modifiers, timestamp: 0, windowNumber: 0, context: nil, characters: shortcut.key, charactersIgnoringModifiers: shortcut.key, isARepeat: false, keyCode: 0)!
        }
        XCTAssertTrue(view.handleEditorShortcut(event(.underline)))
        view.insertText("word", replacementRange: view.selectedRange())
        XCTAssertEqual(view.textStorage!.attribute(.dayDreamUnderline, at: 0, effectiveRange: nil) as? Bool, true)
        view.setSelectedRange(NSRange(location: 0, length: 4))
        XCTAssertTrue(view.handleEditorShortcut(event(.resetWritingStyle)))
        XCTAssertEqual(view.exportMarkdown(), "word")
    }

    func testCombinedDecorationsRoundTrip() {
        let view = editor("<u>~~**combined**~~</u>")
        XCTAssertEqual(view.string, "combined")
        XCTAssertEqual(view.exportMarkdown(), "<u>~~**combined**~~</u>")
        view.rebuildAttributes(in: NSRange(location: 0, length: 8))
        XCTAssertEqual(view.textStorage!.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int, 1)
        XCTAssertEqual(view.textStorage!.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int, 1)
    }

    func testPDFExportPaginatesAndImportRemainsBinary() throws {
        let sourceDirectory = try directory(), library = try directory()
        let source = sourceDirectory.appendingPathComponent("Reading.pdf")
        let text = "# First heading\n\n" + (1...200).map { "Paragraph \($0): A readable sentence for PDF pagination." }.joined(separator: "\n\n") + "\n\nLast sentinel"
        let service = DocumentTransferService()
        try service.exportPDF(text, to: source)
        let pdf = try XCTUnwrap(PDFDocument(url: source))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        XCTAssertTrue(pdf.string?.contains("First heading") == true)
        XCTAssertTrue(pdf.string?.contains("Last sentinel") == true)
        let bytes = try Data(contentsOf: source)
        let store = WorkspaceStore(rootURL: library)
        let imported = try store.importDocument(from: source)
        XCTAssertEqual(imported.pathExtension, "pdf")
        XCTAssertEqual(try Data(contentsOf: imported), bytes)
        XCTAssertTrue(store.nodes.contains { $0.url == imported })
        let document = DocumentController()
        document.open(imported)
        XCTAssertTrue(document.isPDF)
        document.updateMarkdown("must never overwrite a PDF")
        XCTAssertTrue(document.flush())
        document.overwriteExternalChanges()
        XCTAssertEqual(try Data(contentsOf: imported), bytes)
        let duplicate = try store.duplicate(imported)
        XCTAssertEqual(duplicate.pathExtension, "pdf")
        let renamed = try store.rename(duplicate, to: "Renamed")
        XCTAssertEqual(renamed.lastPathComponent, "Renamed.pdf")
        XCTAssertEqual(try Data(contentsOf: renamed), bytes)
    }

    func testInvalidPDFDoesNotCreateLibraryFileAndDropTargetIsRespected() throws {
        let sourceDirectory = try directory(), library = try directory()
        let invalid = sourceDirectory.appendingPathComponent("Invalid.pdf")
        try Data("not PDF".utf8).write(to: invalid)
        let store = WorkspaceStore(rootURL: library)
        XCTAssertThrowsError(try store.importDocument(from: invalid))
        XCTAssertTrue(store.nodes.isEmpty)
        let folder = library.appendingPathComponent("Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = sourceDirectory.appendingPathComponent("External.md")
        try Data("original".utf8).write(to: source)
        let imported = try store.importDocument(from: source, into: folder)
        XCTAssertEqual(imported.deletingLastPathComponent().path, folder.path)
        XCTAssertEqual(try String(contentsOf: source), "original")
    }

    func testUltraViewportFollowingMovesCaretWithoutPullingScrollBack() {
        let view = editor((1...70).map { "Sentence \($0)." }.joined(separator: "\n"))
        let scroll = EditorScrollView(frame: NSRect(x: 0, y: 0, width: 700, height: 600))
        view.isVerticallyResizable = true
        view.maxSize = NSSize(width: 100000, height: 100000)
        scroll.documentView = view
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.setUltraFocus(true)
        view.ultraScrollTimer?.invalidate(); view.ultraScrollTimer = nil
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 500))
        let offset = scroll.contentView.bounds.minY
        view.followUltraFocusViewport()
        XCTAssertGreaterThan(view.selectedRange().location, 0)
        XCTAssertNil(view.ultraScrollTimer)
        XCTAssertEqual(scroll.contentView.bounds.minY, offset)
        let manager = view.layoutManager!
        let glyph = manager.glyphIndexForCharacter(at: view.selectedRange().location)
        let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        XCTAssertEqual(line.midY + view.textContainerOrigin.y, scroll.contentView.bounds.midY, accuracy: line.height)
        view.setUltraFocus(false)
    }

    func testIndependentFinderWindowTitlesAndSavesOriginalFile() throws {
        let folder = try directory()
        let source = folder.appendingPathComponent("Temporary note.md")
        try Data("original".utf8).write(to: source)
        let controller = try XCTUnwrap(ExternalDocumentWindow(url: source))
        XCTAssertEqual(controller.window?.title, "Temporary note.md")
        XCTAssertEqual(controller.window?.titleVisibility, .visible)
        XCTAssertEqual(controller.fileDocument.currentURL, source)
        controller.fileDocument.updateMarkdown("edited original")
        XCTAssertTrue(controller.save())
        XCTAssertEqual(try String(contentsOf: source), "edited original")
        controller.window?.delegate = nil
        controller.window?.close()
    }

    func testFinderRegistrationIncludesMarkdownEditorAndPDFViewer() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent("Scripts/Info.plist")), format: nil) as? [String: Any])
        let types = try XCTUnwrap(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        XCTAssertTrue(types.contains { ($0["CFBundleTypeRole"] as? String) == "Editor" && ($0["CFBundleTypeExtensions"] as? [String])?.contains("md") == true })
        XCTAssertTrue(types.contains { ($0["CFBundleTypeRole"] as? String) == "Viewer" && ($0["CFBundleTypeExtensions"] as? [String])?.contains("pdf") == true })
    }
}
