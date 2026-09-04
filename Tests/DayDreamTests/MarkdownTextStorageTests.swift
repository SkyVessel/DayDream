import AppKit
import XCTest
@testable import DayDream

@MainActor
final class MarkdownTextStorageTests: XCTestCase {
    func testAttributedStorageCarriesBlockKindAcrossEveryParagraph() throws {
        let document = MarkdownDocument(blocks: [
            .init(kind: .heading(level: 1), text: "Title"),
            .init(kind: .bullet, text: "Item"),
        ])

        let value = MarkdownTextStorage.attributedString(
            from: document,
            appearance: try XCTUnwrap(NSAppearance(named: .aqua)),
            scale: 1
        )

        XCTAssertEqual(value.string, "Title\nItem")
        XCTAssertEqual(
            value.attribute(.dayDreamBlockKind, at: 0, effectiveRange: nil) as? MarkdownBlockKind,
            .heading(level: 1)
        )
        XCTAssertEqual(
            value.attribute(.dayDreamBlockKind, at: 6, effectiveRange: nil) as? MarkdownBlockKind,
            .bullet
        )
    }

    func testStorageRoundTripsAnEmptyFinalHeading() throws {
        let source = MarkdownDocument(blocks: [
            .init(kind: .body, text: "Body"),
            .init(kind: .heading(level: 3), text: ""),
        ])
        let value = MarkdownTextStorage.attributedString(
            from: source,
            appearance: try XCTUnwrap(NSAppearance(named: .aqua)),
            scale: 1
        )

        XCTAssertEqual(
            MarkdownTextStorage.document(from: value, fallbackKind: .heading(level: 3)),
            source
        )
    }

    func testTextViewLoadsVisibleTextAndExportsMarkdown() throws {
        let textView = makeTextView()
        var callbacks: [String] = []
        textView.markdownDidChange = { callbacks.append($0) }

        textView.load(markdown: "## Title\n- Item")

        XCTAssertEqual(textView.string, "Title\nItem")
        XCTAssertEqual(textView.exportMarkdown(), "## Title\n- Item")
        XCTAssertTrue(callbacks.isEmpty)
    }

    func testHeadingUsesLargerFontThanBody() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let heading = DayDreamTheme.textAttributes(for: appearance, blockKind: .heading(level: 1))
        let body = DayDreamTheme.textAttributes(for: appearance, blockKind: .body)

        let headingFont = try XCTUnwrap(heading[.font] as? NSFont)
        let bodyFont = try XCTUnwrap(body[.font] as? NSFont)
        XCTAssertGreaterThan(headingFont.pointSize, bodyFont.pointSize)
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
