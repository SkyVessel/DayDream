import AppKit
import XCTest
@testable import DayDream

@MainActor
final class PerformanceDiagnosticsTests: XCTestCase {
    func testDecorationLayoutLimitsWorkToVisibleParagraphs() {
        _ = NSApplication.shared
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        let view = DayDreamTextView(frame: NSRect(x: 0, y: 0, width: 720, height: 800), textContainer: container)
        let markdown = (1...2_000).map { "- item number \($0) with enough text to be realistic" }.joined(separator: "\n")
        view.load(markdown: markdown)

        let decorations = BlockDecorationLayout.decorations(
            in: view,
            textContainerOrigin: view.textContainerOrigin,
            scale: 1
        )

        XCTAssertGreaterThan(decorations.count, 0)
        XCTAssertLessThan(decorations.count, 100)
    }

    func testHighlightLayoutLimitsWorkToVisibleParagraphs() {
        _ = NSApplication.shared
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        let view = DayDreamTextView(frame: NSRect(x: 0, y: 0, width: 720, height: 800), textContainer: container)
        let markdown = (1...2_000).map {
            "<span style=\"background-color:yellow\">highlighted item \($0)</span>"
        }.joined(separator: "\n")
        view.load(markdown: markdown)

        let fragments = view.inlineHighlightFragments()

        XCTAssertGreaterThan(fragments.count, 0)
        XCTAssertLessThan(fragments.count, 100)
    }

    func testFocusSentenceResolutionIgnoresUnrelatedParagraphs() {
        let text = String(repeating: "Unrelated sentence.\n", count: 30_000)
            + "Target sentence."
        let caret = text.utf16.count
        let start = CFAbsoluteTimeGetCurrent()

        for _ in 0..<5 {
            XCTAssertEqual(
                FocusSentenceResolver.range(in: text, caretLocation: caret),
                NSRange(location: caret - 16, length: 16)
            )
        }

        XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - start, 0.015)
    }

    func testMovingCaretWithinFocusedSentenceDoesNotReprocessWholeDocument() {
        let previous = EditorSettings.shared.focusModeEnabled
        EditorSettings.shared.focusModeEnabled = true
        defer { EditorSettings.shared.focusModeEnabled = previous }
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        let view = DayDreamTextView(frame: NSRect(x: 0, y: 0, width: 720, height: 800), textContainer: container)
        let markdown = String(repeating: "Earlier paragraph.\n", count: 10_000)
            + "Current sentence."
        view.load(markdown: markdown)
        let end = view.string.utf16.count
        let start = CFAbsoluteTimeGetCurrent()

        for index in 0..<100 {
            view.setSelectedRange(NSRange(location: end - 1 - (index % 4), length: 0))
        }

        XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - start, 0.03)
    }

    func testEditingLongParagraphOnlyReappliesSpacingNearEdit() {
        let previousWidth = EditorSettings.shared.spaceWidth
        EditorSettings.shared.spaceWidth = 3
        defer { EditorSettings.shared.spaceWidth = previousWidth }
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        let view = DayDreamTextView(frame: NSRect(x: 0, y: 0, width: 720, height: 800), textContainer: container)
        view.load(markdown: String(repeating: "word ", count: 20_000))
        let start = CFAbsoluteTimeGetCurrent()

        for _ in 0..<50 {
            storage.replaceCharacters(
                in: NSRange(location: storage.length, length: 0),
                with: "x"
            )
        }

        XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - start, 0.10)
    }
}
