import AppKit
import XCTest
@testable import DayDream

@MainActor
final class SeptemberUpdateTests: XCTestCase {
    func editor(_ source: String = "") -> DayDreamTextView {
        let storage = NSTextStorage(), manager = TypingLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 600, height: 10000))
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        let view = DayDreamTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 800), textContainer: container)
        view.load(markdown: source)
        return view
    }
    func testDividerRoundTripTriggerAndDecoration() {
        let view = editor("before\n---\nafter")
        XCTAssertEqual(MarkdownDocumentCodec.parse(view.exportMarkdown()).blocks[1].kind, .divider)
        XCTAssertEqual(BlockDecorationLayout.decorations(in: view, textContainerOrigin: view.textContainerOrigin, scale: 1).filter { $0.kind == .divider }.count, 1)
        XCTAssertEqual(MarkdownEditingController.trigger(in: "---", caretLocation: 3)?.kind, .divider)
        XCTAssertEqual(MarkdownEditingController.nextKind(after: .divider, currentText: ""), .body)
    }
    func testDividerInsertionNeverDropsExistingOrFollowingText() {
        let view = editor("beforeafter")
        view.setSelectedRange(NSRange(location: 6, length: 0))
        view.insertDivider()
        XCTAssertEqual(view.exportMarkdown(), "before\n---\nafter")
        let empty = editor("---")
        empty.insertText("following", replacementRange: empty.selectedRange())
        XCTAssertEqual(empty.exportMarkdown(), "---\nfollowing")
    }

    func testMediaPreviewPreservesImageAspectRatio() {
        let rect = MediaCardView.fittedRect(imageSize: NSSize(width: 100, height: 300), in: NSRect(x: 0, y: 0, width: 300, height: 200))
        XCTAssertEqual(rect.width / rect.height, 1 / 3, accuracy: 0.001)
        XCTAssertEqual(rect.midX, 150, accuracy: 0.001)
    }
    func testSecondCardKeepsDragPositionDuringRefresh() throws {
        let first = MediaCard(kind: .image, source: "file:///missing-a.png", title: "a")
        let second = MediaCard(kind: .image, source: "file:///missing-b.png", title: "b")
        let view = editor(first.markdown + "\n" + second.markdown)
        view.refreshMediaCards()
        let card = try XCTUnwrap(view.mediaViews[second.id])
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: card.frame.midX, y: card.frame.midY), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        card.mouseDown(with: down)
        card.onMove?(NSPoint(x: 45, y: 480), false)
        let dragged = card.frame
        view.refreshMediaCards()
        XCTAssertEqual(card.frame, dragged)
        XCTAssertTrue(card.isInteracting)
        card.mouseUp(with: down)
    }
    func testMediaResizeKeepsRatioAndPersistsWidth() throws {
        let media = MediaCard(kind: .image, source: "file:///missing.png", title: "image")
        let view = editor(media.markdown)
        let card = try XCTUnwrap(view.mediaViews[media.id])
        card.onResize?(400, true)
        XCTAssertEqual(card.frame.width, 400, accuracy: 0.01)
        XCTAssertEqual(card.frame.width / card.frame.height, card.aspectRatio, accuracy: 0.01)
        let saved = try XCTUnwrap(MediaCard.parse(view.exportMarkdown()))
        XCTAssertEqual(saved.width, 400)
    }
    func testURLInsertionIsInlineMarkdownWithIconAndNoCard() throws {
        let view = editor()
        try view.insertMedia(url: URL(string: "https://example.invalid/path")!)
        XCTAssertTrue(view.mediaViews.isEmpty)
        XCTAssertNotNil(view.textStorage!.attribute(.dayDreamLinkIcon, at: 0, effectiveRange: nil))
        XCTAssertEqual(view.textStorage!.attribute(.underlineStyle, at: 1, effectiveRange: nil) as? Int, 0)
        XCTAssertEqual(view.exportMarkdown(), "[https://example.invalid/path](https://example.invalid/path)")
        let reopened = editor(view.exportMarkdown())
        XCTAssertNotNil(reopened.textStorage!.attribute(.dayDreamLinkIcon, at: 0, effectiveRange: nil))
    }
    func testHighlightPersistsForFutureTypingAndResetClearsIt() {
        let view = editor()
        view.pendingWritingTool = .highlight
        view.commitWritingBarSelection()
        view.insertText("highlight", replacementRange: view.selectedRange())
        XCTAssertEqual(view.textStorage!.attribute(.dayDreamHighlight, at: 0, effectiveRange: nil) as? String, EditorSettings.shared.highlightPreset)
        view.resetWritingStyle()
        view.insertText("plain", replacementRange: view.selectedRange())
        XCTAssertNil(view.textStorage!.attribute(.dayDreamHighlight, at: 9, effectiveRange: nil))
    }
    func testSelectedStyleUndoRedoPreservesDifferentParagraphKinds() throws {
        let view = editor("# Title\nbody")
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.contentView = nil; window.close() }
        let undo = try XCTUnwrap(view.undoManager)
        undo.removeAllActions()
        view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
        undo.beginUndoGrouping()
        view.applyWritingToolToSelection(.highlight)
        undo.endUndoGrouping()
        XCTAssertEqual(view.currentBlockKind(at: 0), .heading(level: 1))
        XCTAssertEqual(view.currentBlockKind(at: 6), .body)
        XCTAssertFalse(view.isFormatPanelVisible)
        undo.undo()
        XCTAssertNil(view.textStorage!.attribute(.dayDreamHighlight, at: 0, effectiveRange: nil))
        undo.redo()
        XCTAssertEqual(view.textStorage!.attribute(.dayDreamHighlight, at: 0, effectiveRange: nil) as? String, EditorSettings.shared.highlightPreset)
    }
    func testDynamicFontToolRoundTripsLegacySettings() throws {
        let decoded = try JSONDecoder().decode([WritingTool].self, from: Data("[\"bold\",\"georgia\",\"font:Helvetica\",\"highlight:green\"]".utf8))
        XCTAssertEqual(decoded[1], .georgia)
        XCTAssertEqual(decoded[2].fontName, "Helvetica")
        XCTAssertEqual(decoded[3].highlightColor, EditorSettings.shared.highlightPreset)
        XCTAssertTrue(WritingTool.allCases.contains(.font("Helvetica")))
        for choice in EditorSettings.fontChoices { XCTAssertTrue(WritingTool.allCases.contains(.font(choice.id))) }
        for imported in FontLibrary.shared.fonts { XCTAssertTrue(WritingTool.allCases.contains(.font(imported.postScriptName))) }
        XCTAssertTrue(WritingTool.allCases.contains { $0.blockKind == .divider })
        let view = editor("selected")
        view.setSelectedRange(NSRange(location: 0, length: 8))
        view.applyWritingToolToSelection(decoded[2])
        XCTAssertEqual(view.textStorage!.attribute(.dayDreamFontFamily, at: 0, effectiveRange: nil) as? String, "Helvetica")
    }
    func testFallingCopiesLeaveOriginalTextAndLaunchUpwardBeforeFading() {
        let settings = EditorSettings.shared
        let oldStyle = settings.typingAnimationStyle, enabled = settings.typingAnimationEnabled
        defer { settings.typingAnimationStyle = oldStyle; settings.typingAnimationEnabled = enabled }
        settings.typingAnimationEnabled = true; settings.typingAnimationStyle = "falling"
        let view = editor()
        view.insertText("a", replacementRange: view.selectedRange())
        XCTAssertEqual(view.exportMarkdown(), "a")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            XCTAssertEqual((view.layoutManager as? TypingLayoutManager)?.fallingCopyCount, 1)
        }
        XCTAssertLessThan(FallingTextMotion.sample(age: 0.1, lifetime: 0.9, strength: 1, horizontalVelocity: 60).offset.y, 0)
        XCTAssertGreaterThan(FallingTextMotion.sample(age: 0.8, lifetime: 0.9, strength: 1, horizontalVelocity: 60).offset.y, 0)
        XCTAssertEqual(FallingTextMotion.sample(age: 0.9, lifetime: 0.9, strength: 1, horizontalVelocity: 60).opacity, 0)
    }
    func testFreshDefaultsKeepOriginalAnimationAndDisableSpelling() {
        let name = "DayDreamTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = EditorSettings(defaults: defaults)
        XCTAssertFalse(settings.automaticSpellingCorrectionEnabled)
        XCTAssertEqual(settings.typingAnimationStyle, "elastic")
    }
    func testEmphasisWithSpacesIsAcceptedByExternalMarkdownParser() throws {
        let line = NSAttributedString(string: " bold ", attributes: [.dayDreamBold: true])
        let output = InlineMarkdown.serialize(line)
        XCTAssertEqual(output, " **bold** ")
        let parsed = try AttributedString(markdown: output, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        XCTAssertTrue(parsed.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }
}
