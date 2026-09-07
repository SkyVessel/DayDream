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

    func testParseInlineCodeWithoutParsingMarkdownInsideIt() {
        let result = InlineMarkdown.parse("a `**literal**` c")

        XCTAssertEqual(result.plain, "a **literal** c")
        XCTAssertEqual(
            result.runs,
            [InlineRun(
                range: NSRange(location: 2, length: 11),
                style: InlineStyle(code: true)
            )]
        )
    }

    func testInlineCodeUsesLongerDelimiterWhenContentContainsBackticks() {
        let parsed = InlineMarkdown.parse("``use `code` here``")
        XCTAssertEqual(parsed.plain, "use `code` here")
        XCTAssertEqual(parsed.runs.first?.style, InlineStyle(code: true))

        let attributed = NSAttributedString(
            string: "use `code` here",
            attributes: [.dayDreamInlineCode: true]
        )
        XCTAssertEqual(InlineMarkdown.serialize(attributed), "``use `code` here``")
    }

    func testInlineCodeRemovesCanonicalPaddingAroundEdgeBackticks() {
        let result = InlineMarkdown.parse("`` `edge` ``")

        XCTAssertEqual(result.plain, "`edge`")
        XCTAssertEqual(result.runs.first?.style, InlineStyle(code: true))
    }

    func testParseSpanColors() {
        let result = InlineMarkdown.parse("<span style=\"color:yellow;background-color:pink\">hi</span>")
        XCTAssertEqual(result.plain, "hi")
        XCTAssertEqual(result.runs.first?.style,
                       InlineStyle(textColor: "yellow", highlight: "pink"))
    }

    func testParsePortableCSSColorsBackIntoDayDreamPresets() {
        let result = InlineMarkdown.parse(
            "<span style=\"color:#C48E9C;background-color:#E8C0C8\">hi</span>"
        )

        XCTAssertEqual(result.plain, "hi")
        XCTAssertEqual(
            result.runs.first?.style,
            InlineStyle(textColor: "caret", highlight: "caret")
        )
    }

    func testParseNestedSpanAndBold() {
        let result = InlineMarkdown.parse("<span style=\"color:yellow\">a **b** c</span>")
        XCTAssertEqual(result.plain, "a b c")
        XCTAssertEqual(result.runs.count, 3)
        XCTAssertEqual(result.runs[0].style, InlineStyle(textColor: "yellow"))
        XCTAssertEqual(result.runs[1].style, InlineStyle(bold: true, textColor: "yellow"))
        XCTAssertEqual(result.runs[2].style, InlineStyle(textColor: "yellow"))
    }

    func testParseStandardLinkAndNestedBoldLabel() {
        let result = InlineMarkdown.parse(
            "Read [the **docs**](https://example.com/docs) now"
        )

        XCTAssertEqual(result.plain, "Read the docs now")
        XCTAssertEqual(result.runs, [
            InlineRun(
                range: NSRange(location: 5, length: 4),
                style: InlineStyle(linkDestination: "https://example.com/docs")
            ),
            InlineRun(
                range: NSRange(location: 9, length: 4),
                style: InlineStyle(
                    bold: true,
                    linkDestination: "https://example.com/docs"
                )
            ),
        ])
    }

    func testSerializeStandardLinkWithStyledLabel() {
        let value = NSMutableAttributedString(string: "the docs")
        value.addAttribute(
            .dayDreamLink,
            value: "https://example.com/docs",
            range: NSRange(location: 0, length: value.length)
        )
        value.addAttribute(
            .dayDreamBold,
            value: true,
            range: NSRange(location: 4, length: 4)
        )

        XCTAssertEqual(
            InlineMarkdown.serialize(value),
            "[the **docs**](https://example.com/docs)"
        )
    }

    func testParseAndSerializePortableImageReference() {
        let parsed = InlineMarkdown.parse("See ![diagram](assets/diagram.png) here")

        XCTAssertEqual(parsed.plain, "See diagram here")
        XCTAssertEqual(parsed.runs, [
            InlineRun(
                range: NSRange(location: 4, length: 7),
                style: InlineStyle(imageDestination: "assets/diagram.png")
            ),
        ])

        let value = NSMutableAttributedString(string: "diagram")
        value.addAttribute(
            .dayDreamImage,
            value: "assets/diagram.png",
            range: NSRange(location: 0, length: value.length)
        )
        XCTAssertEqual(InlineMarkdown.serialize(value), "![diagram](assets/diagram.png)")
    }

    func testUnclosedMarkerStaysLiteral() {
        let result = InlineMarkdown.parse("a **bold")
        XCTAssertEqual(result.plain, "a **bold")
        XCTAssertTrue(result.runs.isEmpty)
    }

    // MARK: - 往返（解析 → 建存储 → 序列化）

    func testRoundTripPreservesInlineMarkdown() {
        let samples = [
            ("plain text", "plain text"),
            ("a **bold** c", "a **bold** c"),
            ("a *italic* c", "a *italic* c"),
            ("***both*** end", "***both*** end"),
            ("a `code` span", "a `code` span"),
            ("<span style=\"color:yellow\">colored</span>", "<span style=\"color:#8A7A48\">colored</span>"),
            ("<span style=\"background-color:caret\">highlighted</span>", "<span style=\"background-color:#E8C0C8\">highlighted</span>"),
            ("<span style=\"color:yellow;background-color:pink\">both</span>", "<span style=\"color:#8A7A48;background-color:#D8B0B8\">both</span>"),
            ("<span style=\"color:yellow\">a **b** c</span>", "<span style=\"color:#8A7A48\">a **b** c</span>"),
        ]
        for (sample, expected) in samples {
            let document = MarkdownDocument(blocks: [MarkdownBlock(kind: .body, text: sample)])
            let storage = MarkdownTextStorage.attributedString(
                from: document, appearance: appearance, scale: 1
            )
            let exported = MarkdownTextStorage.document(from: storage, fallbackKind: .body)
            XCTAssertEqual(exported.blocks.map(\.text), [expected], "往返失败: \(sample)")
        }
    }

    func testRoundTripThroughCodecKeepsBlockMarkersAndInline() throws {
        let markdown = "# Title **bold**\n- [ ] task *note*\n1. item <span style=\"color:green\">green</span>"
        let document = MarkdownDocumentCodec.parse(markdown)
        let storage = MarkdownTextStorage.attributedString(
            from: document, appearance: appearance, scale: 1
        )
        let exported = MarkdownTextStorage.document(from: storage, fallbackKind: .body)
        XCTAssertEqual(
            MarkdownDocumentCodec.serialize(exported),
            "# Title **bold**\n- [ ] task *note*\n1. item <span style=\"color:#5F7F68\">green</span>"
        )
    }
}
