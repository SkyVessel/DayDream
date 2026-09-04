import AppKit
import XCTest
@testable import DayDream

@MainActor
final class MarkdownEditingControllerTests: XCTestCase {
    func testRecognizesOnlyCompleteMarkersAtParagraphStart() {
        let cases: [(String, MarkdownBlockKind)] = [
            ("#", .heading(level: 1)),
            ("####", .heading(level: 4)),
            ("-", .bullet),
            ("*", .bullet),
            ("1.", .numbered),
            ("[ ]", .todo(checked: false)),
            ("[]", .todo(checked: false)),
            ("[x]", .todo(checked: true)),
        ]

        for (source, kind) in cases {
            XCTAssertEqual(
                MarkdownEditingController.trigger(in: source, caretLocation: (source as NSString).length)?.kind,
                kind
            )
        }
        XCTAssertNil(MarkdownEditingController.trigger(in: "text -", caretLocation: 6))
        XCTAssertNil(MarkdownEditingController.trigger(in: "#####", caretLocation: 5))
    }

    func testTriggerRangeUsesUTF16ParagraphOffsets() {
        let source = "😀正文\n##"
        XCTAssertEqual(
            MarkdownEditingController.trigger(in: source, caretLocation: (source as NSString).length)?.replacementRange,
            NSRange(location: 5, length: 2)
        )
    }

    func testContinuationRules() {
        XCTAssertEqual(
            MarkdownEditingController.nextKind(after: .heading(level: 2), currentText: "Title"),
            .body
        )
        XCTAssertEqual(
            MarkdownEditingController.nextKind(after: .todo(checked: true), currentText: "Done"),
            .todo(checked: false)
        )
        XCTAssertNil(MarkdownEditingController.nextKind(after: .bullet, currentText: ""))
        XCTAssertEqual(
            MarkdownEditingController.nextKind(after: .body, currentText: "Body"),
            .body
        )
    }

    func testSpaceConvertsHeadingMarkerIntoEmptyHeading() {
        let textView = makeTextView()
        textView.insertText("#", replacementRange: NSRange(location: 0, length: 0))

        textView.insertText(" ", replacementRange: textView.selectedRange())

        XCTAssertEqual(textView.string, "")
        XCTAssertEqual(textView.currentBlockKind(at: 0), .heading(level: 1))
        XCTAssertEqual(textView.exportMarkdown(), "# ")
    }

    func testEnterContinuesNonEmptyListAndEmptyListExits() {
        let textView = makeTextView()
        textView.load(markdown: "- Item")

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(textView.string, "Item\n")
        XCTAssertEqual(textView.currentBlockKind(at: textView.selectedRange().location), .bullet)

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(textView.string, "Item\n")
        XCTAssertEqual(textView.currentBlockKind(at: textView.selectedRange().location), .body)
    }

    func testEnterAfterHeadingStartsBody() {
        let textView = makeTextView()
        textView.load(markdown: "## Title")

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(textView.string, "Title\n")
        XCTAssertEqual(textView.currentBlockKind(at: textView.selectedRange().location), .body)
        XCTAssertEqual(textView.exportMarkdown(), "## Title\n")
    }

    func testBackspaceRemovesAppliedBlockStyleAtParagraphStart() {
        let cases: [(String, MarkdownBlockKind)] = [
            ("# ", .heading(level: 1)),
            ("- ", .bullet),
            ("1. ", .numbered),
            ("- [ ] ", .todo(checked: false)),
        ]

        for (markdown, kind) in cases {
            let textView = makeTextView()
            textView.load(markdown: markdown)
            XCTAssertEqual(textView.currentBlockKind(at: 0), kind)

            textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

            XCTAssertEqual(textView.currentBlockKind(at: 0), .body)
            XCTAssertEqual(textView.exportMarkdown(), "")
        }
    }

    func testBackspaceAtStartOfFilledHeadingKeepsTextAndRemovesStyle() {
        let textView = makeTextView()
        textView.load(markdown: "## Title")
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertEqual(textView.string, "Title")
        XCTAssertEqual(textView.currentBlockKind(at: 0), .body)
        XCTAssertEqual(textView.exportMarkdown(), "Title")
    }

    private func makeTextView() -> DayDreamTextView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 700, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        return DayDreamTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 800), textContainer: container)
    }
}
