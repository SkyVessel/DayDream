import AppKit
import XCTest
@testable import DayDream

@MainActor
final class InlineMarkdownTests: XCTestCase {

    private let appearance = NSAppearance(named: .aqua)!

    // MARK: - 解析

    func testParsePlainTextHasNoRuns() {
        let result = InlineMarkdown.parse("hello world")
        XCTAssertEqual(result.plain, "hello world")
        XCTAssertTrue(result.runs.isEmpty)
    }

    func testParseBold() {
        let result = InlineMarkdown.parse("a **bold** c")
        XCTAssertEqual(result.plain, "a bold c")
        XCTAssertEqual(result.runs, [InlineRun(range: NSRange(location: 2, length: 4),
                                               style: InlineStyle(bold: true))])
    }

    func testParseItalic() {
        let result = InlineMarkdown.parse("a *italic* c")
        XCTAssertEqual(result.plain, "a italic c")
        XCTAssertEqual(result.runs, [InlineRun(range: NSRange(location: 2, length: 6),
                                               style: InlineStyle(italic: true))])
    }

    func testParseBoldItalic() {
        let result = InlineMarkdown.parse("***both***")
        XCTAssertEqual(result.plain, "both")
        XCTAssertEqual(result.runs.first?.style, InlineStyle(bold: true, italic: true))
    }

    func testParseSpanColors() {
        let result = InlineMarkdown.parse("<span style=\"color:yellow;background-color:pink\">hi</span>")
        XCTAssertEqual(result.plain, "hi")
        XCTAssertEqual(result.runs.first?.style,
                       InlineStyle(textColor: "yellow", highlight: "pink"))
    }

    func testParseNestedSpanAndBold() {
        let result = InlineMarkdown.parse("<span style=\"color:yellow\">a **b** c</span>")
        XCTAssertEqual(result.plain, "a b c")
        XCTAssertEqual(result.runs.count, 3)
        XCTAssertEqual(result.runs[0].style, InlineStyle(textColor: "yellow"))
        XCTAssertEqual(result.runs[1].style, InlineStyle(bold: true, textColor: "yellow"))
        XCTAssertEqual(result.runs[2].style, InlineStyle(textColor: "yellow"))
    }

    func testUnclosedMarkerStaysLiteral() {
        let result = InlineMarkdown.parse("a **bold")
        XCTAssertEqual(result.plain, "a **bold")
        XCTAssertTrue(result.runs.isEmpty)
    }

    // MARK: - 往返（解析 → 建存储 → 序列化）

    func testRoundTripPreservesInlineMarkdown() {
        let samples = [
            "plain text",
            "a **bold** c",
            "a *italic* c",
            "***both*** end",
            "<span style=\"color:yellow\">colored</span>",
            "<span style=\"background-color:caret\">highlighted</span>",
            "<span style=\"color:yellow;background-color:pink\">both</span>",
            "<span style=\"color:yellow\">a **b** c</span>",
        ]
        for sample in samples {
            let document = MarkdownDocument(blocks: [MarkdownBlock(kind: .body, text: sample)])
            let storage = MarkdownTextStorage.attributedString(
                from: document, appearance: appearance, scale: 1
            )
            let exported = MarkdownTextStorage.document(from: storage, fallbackKind: .body)
            XCTAssertEqual(exported.blocks.map(\.text), [sample], "往返失败: \(sample)")
        }
    }

    func testRoundTripThroughCodecKeepsBlockMarkersAndInline() throws {
        let markdown = "# Title **bold**\n- [ ] task *note*\n1. item <span style=\"color:green\">green</span>"
        let document = MarkdownDocumentCodec.parse(markdown)
        let storage = MarkdownTextStorage.attributedString(
            from: document, appearance: appearance, scale: 1
        )
        let exported = MarkdownTextStorage.document(from: storage, fallbackKind: .body)
        XCTAssertEqual(MarkdownDocumentCodec.serialize(exported), markdown)
    }
}
