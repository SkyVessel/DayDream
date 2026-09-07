import AppKit
import XCTest
@testable import DayDream

@MainActor
final class EditorRefreshRegressionTests: XCTestCase {
    private func editor(_ markdown: String) -> DayDreamTextView {
        let storage = NSTextStorage()
        let manager = TypingLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 700, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        let view = DayDreamTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 700), textContainer: container)
        view.load(markdown: markdown)
        return view
    }

    func testSelectingListBeforeFinalBlankLineDoesNotCreateExtraListOrChangeMarkdown() {
        for marker in ["1.", "-", "- [ ]"] {
            let source = "\(marker) item\n"
            let view = editor(source)
            view.setSelectedRange(NSRange(location: 1, length: 0))
            let decorations = BlockDecorationLayout.decorations(in: view, textContainerOrigin: view.textContainerOrigin, scale: 1)
            XCTAssertEqual(decorations.count, 1, "\(marker) should have exactly one list marker")
            XCTAssertEqual(view.currentBlockKind(at: view.string.utf16.count), .body)
            XCTAssertEqual(view.exportMarkdown(), source)
        }
    }

    func testFormattingFirstBlankLineDoesNotStyleDocumentTrailingBlankLine() {
        for marker in ["1.", "-", "[]"] {
            let view = editor("\n")
            view.setSelectedRange(NSRange(location: 0, length: 0))
            view.insertText(marker, replacementRange: view.selectedRange())
            view.insertText(" ", replacementRange: view.selectedRange())
            XCTAssertEqual(BlockDecorationLayout.decorations(in: view, textContainerOrigin: view.textContainerOrigin, scale: 1).count, 1)
            XCTAssertEqual(view.currentBlockKind(at: view.string.utf16.count), .body)
        }
    }

    func testRealTrailingListRetainsItsOwnKindWhenCaretMovesElsewhere() {
        let view = editor("Body\n7. item")
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        view.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertEqual(view.currentBlockKind(at: view.string.utf16.count), .numbered)
        XCTAssertEqual(view.exportMarkdown(), "Body\n7. item\n8. ")
    }

    func testNestedMarkerMovesBySameTabDistanceAsText() {
        let view = editor("1. Parent\n2. Child")
        let original = BlockDecorationLayout.decorations(in: view, textContainerOrigin: view.textContainerOrigin, scale: 1).last!
        view.setSelectedRange(NSRange(location: 7, length: 0))
        let originalParagraph = view.textStorage!.attribute(.paragraphStyle, at: 7, effectiveRange: nil) as! NSParagraphStyle
        view.doCommand(by: #selector(NSResponder.insertTab(_:)))
        let nested = BlockDecorationLayout.decorations(in: view, textContainerOrigin: view.textContainerOrigin, scale: 1).last!
        let nestedParagraph = view.textStorage!.attribute(.paragraphStyle, at: 7, effectiveRange: nil) as! NSParagraphStyle
        XCTAssertEqual(nested.label, "a.")
        XCTAssertGreaterThan(nested.markerRect.minX, original.markerRect.minX)
        XCTAssertEqual(nested.markerRect.minX - original.markerRect.minX, nestedParagraph.headIndent - originalParagraph.headIndent, accuracy: 0.01)
    }

    func testEmptyNumberedParagraphDrawsExactlyOneMarkerWithoutStorageCharacters() {
        let view = editor("")
        view.insertText("7.", replacementRange: view.selectedRange())
        view.insertText(" ", replacementRange: view.selectedRange())
        let decorations = BlockDecorationLayout.decorations(in: view, textContainerOrigin: view.textContainerOrigin, scale: 1)
        XCTAssertEqual(decorations.compactMap(\.label), ["7."])
        view.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(BlockDecorationLayout.decorations(in: view, textContainerOrigin: view.textContainerOrigin, scale: 1).compactMap(\.label), ["a."])
    }

    func testToolBarHidesOnKeyReleaseAndBeforeTypingWithoutDelay() {
        let view = editor("Text ")
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 700, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        defer { view.dismissWritingBar(); window.orderOut(nil); window.contentView = nil; window.close() }
        view.cycleWritingBar(0)
        XCTAssertTrue(view.writingBarPanel?.isVisible == true)
        let release = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "1", charactersIgnoringModifiers: "1", isARepeat: false, keyCode: 55)!
        view.handleWritingBarRelease(release)
        XCTAssertFalse(view.writingBarPanel?.isVisible == true)
        view.cycleWritingBar(1)
        XCTAssertTrue(view.writingBarPanel?.isVisible == true)
        view.commitWritingBarSelection()
        view.insertText("pink", replacementRange: view.selectedRange())
        XCTAssertFalse(view.writingBarPanel?.isVisible == true)
        XCTAssertNotNil(view.activeWritingColor)
        view.resetWritingStyle()
        view.insertText("plain", replacementRange: view.selectedRange())
        let last = view.string.utf16.count - 1
        XCTAssertNil(view.textStorage?.attribute(.dayDreamTextColor, at: last, effectiveRange: nil))
        XCTAssertNil(view.textStorage?.attribute(.dayDreamBold, at: last, effectiveRange: nil))
        XCTAssertNil(view.textStorage?.attribute(.dayDreamFontFamily, at: last, effectiveRange: nil))
    }

    func testDisplayCommitsWhileIdleWithoutAnotherInputEvent() {
        let view = editor("Text")
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 700, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        view.applyBlockKind(.numbered, at: 0)
        XCTAssertTrue(view.isDisplayCommitScheduled)
        // Run the display cycle only: no keyboard or mouse event is delivered.
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        XCTAssertFalse(view.isDisplayCommitScheduled)
        XCTAssertFalse(view.needsDisplay)
        XCTAssertEqual(BlockDecorationLayout.decorations(in: view, textContainerOrigin: view.textContainerOrigin, scale: 1).count, 1)
    }

    func testChineseGraveShortcutAliasMatchesPhysicalKeyAndStoredBinding() {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil, characters: "·", charactersIgnoringModifiers: "·", isARepeat: false, keyCode: 50)!
        XCTAssertTrue(AppShortcut(key: "`", modifiers: .command).matches(event))
        XCTAssertTrue(AppShortcut(key: "·", modifiers: .command).matches(event))
    }
}
