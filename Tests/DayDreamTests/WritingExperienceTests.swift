import AppKit
import XCTest
@testable import DayDream

@MainActor
final class WritingExperienceTests: XCTestCase {
    private func editor(_ source: String = "") -> DayDreamTextView {
        let storage = NSTextStorage()
        let manager = TypingLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        let view = DayDreamTextView(frame: NSRect(x: 0, y: 0, width: 720, height: 800), textContainer: container)
        view.load(markdown: source)
        return view
    }

    func testArbitraryNumberTriggerAndContinuationPreserveStart() {
        for start in [0, 7, 42, 1024] {
            let view = editor()
            view.insertText("\(start).", replacementRange: view.selectedRange())
            view.insertText(" ", replacementRange: view.selectedRange())
            XCTAssertEqual(view.currentBlockKind(at: 0), .numbered)
            XCTAssertEqual(view.exportMarkdown(), "\(start). ")
            view.insertText("first", replacementRange: view.selectedRange())
            view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            view.insertText("second", replacementRange: view.selectedRange())
            XCTAssertEqual(view.exportMarkdown(), "\(start). first\n\(start + 1). second")
        }
        for text in ["x2.", "1.2.", "-2.", "999999999999999999999999999."] {
            XCTAssertNil(MarkdownEditingController.trigger(in: text, caretLocation: text.utf16.count))
        }
    }

    func testIndentedNumberedListUsesLettersAndRestoresNumbers() {
        let view = editor("7. parent\n8. child")
        view.setSelectedRange(NSRange(location: 7, length: 0))
        view.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(view.currentListIndentation(at: view.selectedRange().location), "  ")
        var labels = BlockDecorationLayout.decorations(in: view, textContainerOrigin: view.textContainerOrigin, scale: 1).compactMap(\.label)
        XCTAssertEqual(labels, ["7.", "a."])
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        view.insertText("next", replacementRange: view.selectedRange())
        labels = BlockDecorationLayout.decorations(in: view, textContainerOrigin: view.textContainerOrigin, scale: 1).compactMap(\.label)
        XCTAssertEqual(labels, ["7.", "a.", "b."])
        let saved = view.exportMarkdown()
        let reopened = editor(saved)
        XCTAssertEqual(BlockDecorationLayout.decorations(in: reopened, textContainerOrigin: reopened.textContainerOrigin, scale: 1).compactMap(\.label), labels)
        reopened.setSelectedRange((reopened.string as NSString).paragraphRange(for: reopened.selectedRange()))
        reopened.setSelectedRange(NSRange(location: reopened.selectedRange().location, length: 0))
        reopened.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        XCTAssertEqual(reopened.currentListIndentation(at: reopened.selectedRange().location), "")
        XCTAssertEqual(OrderedListMarker.label(ordinal: 27, indentation: "  "), "aa.")
        XCTAssertEqual(OrderedListMarker.label(ordinal: 2, indentation: "    "), "2.")
    }

    func testToolSelectionOnlyAffectsFutureTextAndReplacesStyle() {
        let settings = EditorSettings.shared
        let previous = settings.writingBars
        settings.writingBars = WritingTool.defaultBars
        defer { settings.writingBars = previous }
        let view = editor("existing ")
        view.cycleWritingBar(0)
        view.commitWritingBarSelection()
        view.insertText("bold", replacementRange: view.selectedRange())
        XCTAssertEqual(view.exportMarkdown(), "existing **bold**")
        view.cycleWritingBar(0)
        view.commitWritingBarSelection()
        view.insertText("italic", replacementRange: view.selectedRange())
        let storage = view.textStorage!
        XCTAssertNil(storage.attribute(.dayDreamBold, at: 13, effectiveRange: nil))
        XCTAssertEqual(storage.attribute(.dayDreamItalic, at: 13, effectiveRange: nil) as? Bool, true)
        view.cycleWritingBar(1)
        view.commitWritingBarSelection()
        view.insertText("pink", replacementRange: view.selectedRange())
        XCTAssertEqual(storage.attribute(.dayDreamTextColor, at: 19, effectiveRange: nil) as? String, "pink")
        view.resetWritingStyle()
        view.insertText("plain", replacementRange: view.selectedRange())
        XCTAssertNil(storage.attribute(.dayDreamItalic, at: storage.length - 1, effectiveRange: nil))
        XCTAssertNil(storage.attribute(.dayDreamTextColor, at: storage.length - 1, effectiveRange: nil))
        XCTAssertEqual(storage.string, "existing bolditalicpinkplain")
    }

    func testChosenFontSurvivesSaveReloadAndSettingsChange() {
        let view = editor()
        view.activeWritingStyle = .georgia
        view.insertText("Georgia", replacementRange: view.selectedRange())
        let markdown = view.exportMarkdown()
        XCTAssertTrue(markdown.contains("font-family:Georgia"))
        let reopened = editor(markdown)
        XCTAssertEqual(reopened.textStorage?.attribute(.dayDreamFontFamily, at: 0, effectiveRange: nil) as? String, "Georgia")
        XCTAssertTrue((reopened.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName.contains("Georgia") == true)
        let old = EditorSettings.shared.spaceWidth
        EditorSettings.shared.spaceWidth = old + 0.5
        EditorSettings.shared.spaceWidth = old
        XCTAssertTrue((reopened.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName.contains("Georgia") == true)
    }

    func testWritingSettingsPersistAndBarsStayWithinFourSlots() {
        let name = "DayDream.WritingExperience.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = EditorSettings(defaults: defaults)
        settings.typingAnimationEnabled = false
        settings.wordCountEnabled = false
        settings.setWritingTool(.menlo, bar: 1, slot: 0)
        settings.setWritingTool(.pink, bar: 1, slot: 4)
        settings.setWritingTool(nil, bar: 0, slot: 3)
        let restored = EditorSettings(defaults: defaults)
        XCTAssertFalse(restored.typingAnimationEnabled)
        XCTAssertFalse(restored.wordCountEnabled)
        XCTAssertEqual(restored.writingBars[1].first, .menlo)
        XCTAssertEqual(restored.writingBars[1].count, 4)
        XCTAssertEqual(restored.writingBars[0].count, 3)
    }

    func testWordCountCountsVisibleWordsAndUpdatesAfterEditing() {
        XCTAssertEqual(WordCounter.count("One two, three! 42 😊"), 4)
        XCTAssertEqual(WordCounter.count("... \u{FFFC}"), 0)
        let view = editor()
        var count = -1
        view.wordCountDidChange = { count = $0 }
        view.load(markdown: "# One **two**")
        XCTAssertEqual(count, 2)
        view.insertText(" three", replacementRange: view.selectedRange())
        XCTAssertEqual(count, 3)
    }

    func testRetypeSkipsPunctuationAndHandlesMistakesBackspaceAndWords() {
        var session = RetypeSession(text: "Hi, world! Next.", selection: NSRange(location: 0, length: 0))
        session.type("Hi")
        XCTAssertEqual(session.location, 4)
        session.type(" ")
        XCTAssertEqual(session.location, 4)
        session.type("x")
        XCTAssertEqual(session.results[2], false)
        session.backspace()
        XCTAssertNil(session.results[2])
        session.type("w")
        session.type(" ")
        XCTAssertEqual(session.location, 11)
        session.backspace()
        XCTAssertEqual(session.location, 5)
        session.type("orld Next")
        XCTAssertTrue(session.isComplete)
    }

    func testRetypeIMEAndEditingNeverChangeOriginalAndExitRestoresSelection() {
        let original = "# Café, 中文!\nA **second** line."
        let view = editor(original)
        let selection = view.selectedRange()
        view.toggleRetype()
        XCTAssertNotNil(view.retypeSession)
        XCTAssertEqual(view.selectedRange().location, 0)
        view.setMarkedText("中", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(view.hasMarkedText())
        XCTAssertEqual(view.exportMarkdown(), original)
        view.unmarkText()
        view.insertText("X", replacementRange: view.selectedRange())
        XCTAssertEqual(view.exportMarkdown(), original)
        view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(view.exportMarkdown(), original)
        view.stopRetype()
        XCTAssertTrue(view.isEditable)
        XCTAssertEqual(view.selectedRange(), selection)
        XCTAssertEqual(view.exportMarkdown(), original)
    }

    func testRetypeAutoExitAndFocusStackPreserveMarkdown() {
        let saved = EditorSettings.shared.focusModeEnabled
        EditorSettings.shared.focusModeEnabled = true
        defer { EditorSettings.shared.focusModeEnabled = saved }
        let view = editor("Hi, there!")
        view.toggleRetype()
        view.handleRetypeInput("Hi there")
        XCTAssertNil(view.retypeSession)
        XCTAssertEqual(view.exportMarkdown(), "Hi, there!")
        XCTAssertTrue(EditorSettings.shared.focusModeEnabled)
    }

    func testMediaMarkupIsPortableAndMetadataRoundTrips() {
        for kind in [MediaCard.Kind.image, .video, .link] {
            let card = MediaCard(kind: kind, source: ".daydream-assets/a.png", title: "A < B & C", x: 0.4, y: 90)
            XCTAssertEqual(MediaCard.parse(card.markdown), card)
            XCTAssertTrue(card.markdown.contains("&lt;"))
            let view = editor("Before\n" + card.markdown + "\nAfter")
            XCTAssertEqual(view.string, "Before\n\u{FFFC}\nAfter")
            XCTAssertEqual(view.exportMarkdown(), "Before\n" + card.markdown + "\nAfter")
            XCTAssertEqual(view.textContainer?.exclusionPaths.count, 1)
        }
    }

    func testLocalMediaIsCopiedAndMoveSurvivesReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("fixture.png")
        let image = NSImage(size: NSSize(width: 80, height: 50))
        image.lockFocus(); NSColor.systemPink.setFill(); NSRect(x: 0, y: 0, width: 80, height: 50).fill(); image.unlockFocus()
        try NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: imageURL)
        let view = editor("Words flow around this card. " + String(repeating: "A line of writing. ", count: 30))
        view.documentURL = root.appendingPathComponent("Note.md")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        try view.insertMedia(url: imageURL)
        var card = try XCTUnwrap(view.mediaViews.values.first?.card)
        let copied = try XCTUnwrap(card.resolvedURL(documentURL: view.documentURL))
        XCTAssertNotEqual(copied, imageURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path))
        card.x = 0; card.y = 55
        view.commitMediaPosition(card)
        let markdown = view.exportMarkdown()
        let reopened = editor(markdown)
        XCTAssertEqual(reopened.mediaViews.values.first?.card.x, 0)
        XCTAssertEqual(reopened.mediaViews.values.first?.card.y, 55)
        XCTAssertEqual(reopened.exportMarkdown(), markdown)
        let manager = view.layoutManager!
        manager.ensureLayout(for: view.textContainer!)
        let exclusion = view.textContainer!.exclusionPaths[0].bounds
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { line, used, container, glyphs, _ in
            let ink = manager.boundingRect(forGlyphRange: glyphs, in: container)
            XCTAssertFalse(ink.insetBy(dx: 1, dy: 1).intersects(exclusion), "Text overlaps media: line \(line) used \(used) ink \(ink) / \(exclusion)")
        }
    }

    func testMediaCardsResolveCollisionsAndRejectUnknownMetadata() {
        let one = MediaCard(kind: .image, source: "file:///nonexistent/image.png", title: "One", x: 1, y: 20)
        let two = MediaCard(kind: .video, source: "invalid:video", title: "Two", x: 1, y: 20)
        let view = editor(one.markdown + "\n" + two.markdown)
        let frames = Array(view.mediaViews.values.map(\.frame))
        XCTAssertEqual(frames.count, 2)
        XCTAssertFalse(frames[0].intersects(frames[1]))
        XCTAssertNil(MediaCard.parse("<figure data-daydream=\"invalid\">unknown</figure>"))
        XCTAssertNil(two.resolvedURL(documentURL: nil))
        XCTAssertEqual(MediaCard.kind(for: URL(string: "https://example.com/movie.mp4")!), .video)
        XCTAssertEqual(MediaCard.kind(for: URL(string: "https://www.youtube.com/watch?v=1")!), .video)
    }

    func testMediaMixedWithTextStillReopensAsACard() {
        let card = MediaCard(kind: .image, source: "file:///missing.png", title: "Image")
        let source = "before " + card.markdown + " after"
        let view = editor(source)
        XCTAssertEqual(view.string, "before \u{FFFC} after")
        XCTAssertEqual(view.mediaViews.count, 1)
        XCTAssertEqual(view.exportMarkdown(), source)
    }

    func testMediaResourcesFollowExportAndMoveWithoutChangingSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: first.appendingPathComponent(".daydream-assets"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let relative = ".daydream-assets/picture.png"
        let data = Data([1, 2, 3, 4])
        try data.write(to: first.appendingPathComponent(relative))
        let card = MediaCard(kind: .image, source: relative, title: "Picture")
        let source = first.appendingPathComponent("note.md")
        try card.markdown.write(to: source, atomically: true, encoding: .utf8)
        let destination = second.appendingPathComponent("note.md")
        try DocumentTransferService().exportMarkdown(card.markdown, to: destination, sourceURL: source)
        XCTAssertEqual(try Data(contentsOf: second.appendingPathComponent(relative)), data)
        XCTAssertEqual(try Data(contentsOf: first.appendingPathComponent(relative)), data)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), card.markdown)
    }

    func testUltraFocusCentersFirstAndLastLineAndStacksWithRetype() {
        let view = editor("First line.\n" + String(repeating: "Middle line.\n", count: 40) + "Last line.")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 720, height: 600))
        view.isVerticallyResizable = true
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = view
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.setUltraFocus(true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.65))
        XCTAssertFalse(scroll.hasVerticalScroller)
        func assertCentered(file: StaticString = #filePath, line: UInt = #line) {
            let manager = view.layoutManager!
            let glyph = manager.glyphIndexForCharacter(at: min(view.selectedRange().location, view.string.utf16.count - 1))
            let rect = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            XCTAssertEqual(rect.midY + view.textContainerOrigin.y - scroll.contentView.bounds.minY, scroll.contentSize.height / 2, accuracy: 5, file: file, line: line)
        }
        assertCentered()
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        assertCentered()
        view.toggleRetype()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        assertCentered()
        XCTAssertNotNil(view.retypeSession)
        view.stopRetype()
        view.setUltraFocus(false)
        XCTAssertTrue(scroll.hasVerticalScroller)
        XCTAssertLessThan(view.textContainerInset.height, 100)
    }

    func testNewShortcutDefaultsAreDistinctAndConfigurable() {
        let values = ShortcutCommand.allCases.map(\.defaultShortcut)
        XCTAssertEqual(Set(values).count, values.count)
        XCTAssertEqual(ShortcutCommand.enterUltraFocus.defaultShortcut.displayName, "⌥⌘↑")
        XCTAssertEqual(ShortcutCommand.exitUltraFocus.defaultShortcut.displayName, "⌥⌘↓")
        XCTAssertEqual(ShortcutCommand.retype.defaultShortcut.displayName, "⌃⌥R")
    }
}
