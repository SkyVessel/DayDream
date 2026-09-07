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

    func testParsesAndSerializesBlockquote() {
        let document = MarkdownDocumentCodec.parse("> Quoted text")

        XCTAssertEqual(document.blocks, [
            MarkdownBlock(kind: .quote, text: "Quoted text"),
        ])
        XCTAssertEqual(MarkdownDocumentCodec.serialize(document), "> Quoted text")
    }

    func testParsesAndSerializesFencedCodeWithoutInterpretingItsContents() {
        let source = "Before\n```swift\nlet value = *literal*\nprint(value)\n```\nAfter"
        let document = MarkdownDocumentCodec.parse(source)

        XCTAssertEqual(document.blocks, [
            .init(kind: .body, text: "Before"),
            .init(kind: .code(language: "swift"), text: "let value = *literal*"),
            .init(kind: .code(language: "swift"), text: "print(value)"),
            .init(kind: .body, text: "After"),
        ])
        XCTAssertEqual(MarkdownDocumentCodec.serialize(document), source)
    }

    func testUnclosedFenceRemainsLiteralBodyText() {
        let document = MarkdownDocumentCodec.parse("Before\n```swift\nlet value = 1")

        XCTAssertEqual(document.blocks, [
            .init(kind: .body, text: "Before"),
            .init(kind: .body, text: "```swift"),
            .init(kind: .body, text: "let value = 1"),
        ])
    }

    func testNestedListsPreserveTheirExactIndentation() {
        let source = "- Parent\n  - Child\n\t1. Tab-indented child\n    - Deep child"
        let document = MarkdownDocumentCodec.parse(source)

        XCTAssertEqual(document.blocks, [
            .init(kind: .bullet, text: "Parent"),
            .init(kind: .bullet, text: "Child", indentation: "  "),
            .init(kind: .numbered, text: "Tab-indented child", indentation: "\t"),
            .init(kind: .bullet, text: "Deep child", indentation: "    "),
        ])
        XCTAssertEqual(MarkdownDocumentCodec.serialize(document), source)
    }
}
