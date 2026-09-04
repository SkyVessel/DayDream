import XCTest
@testable import DayDream

final class MarkdownDocumentTests: XCTestCase {
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

    func testSerializesBlocksAsPortableMarkdown() {
        let document = MarkdownDocument(blocks: [
            .init(kind: .heading(level: 2), text: "Title"),
            .init(kind: .todo(checked: true), text: "Ship"),
            .init(kind: .numbered, text: "First"),
        ])

        XCTAssertEqual(
            MarkdownDocumentCodec.serialize(document),
            "## Title\n- [x] Ship\n1. First"
        )
    }

    func testSerializesConsecutiveOrderedItemsWithVisibleNumbersAndRestarts() {
        let document = MarkdownDocument(blocks: [
            .init(kind: .numbered, text: "First"),
            .init(kind: .numbered, text: "Second"),
            .init(kind: .body, text: "Break"),
            .init(kind: .numbered, text: "Again"),
        ])

        XCTAssertEqual(
            MarkdownDocumentCodec.serialize(document),
            "1. First\n2. Second\nBreak\n1. Again"
        )
    }

    func testPreservesBlankLinesAndUnknownMarkdownAsBody() {
        let document = MarkdownDocumentCodec.parse("Body\n\n##### Not supported")

        XCTAssertEqual(document.blocks, [
            .init(kind: .body, text: "Body"),
            .init(kind: .body, text: ""),
            .init(kind: .body, text: "##### Not supported"),
        ])
        XCTAssertEqual(
            MarkdownDocumentCodec.serialize(document),
            "Body\n\n##### Not supported"
        )
    }

    func testEmptySourceProducesOneEditableBodyBlock() {
        XCTAssertEqual(
            MarkdownDocumentCodec.parse("").blocks,
            [.init(kind: .body, text: "")]
        )
    }
}
