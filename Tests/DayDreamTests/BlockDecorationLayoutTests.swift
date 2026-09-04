import AppKit
import XCTest
@testable import DayDream

@MainActor
final class BlockDecorationLayoutTests: XCTestCase {
    func testNumberedOrdinalRestartsAfterNonNumberedParagraph() throws {
        let storage = try attributedStorage(for: "1. One\n1. Two\nBody\n1. Again")

        XCTAssertEqual(BlockDecorationLayout.numberedOrdinal(in: storage, paragraphLocation: 0), 1)
        XCTAssertEqual(BlockDecorationLayout.numberedOrdinal(in: storage, paragraphLocation: 4), 2)
        XCTAssertEqual(BlockDecorationLayout.numberedOrdinal(in: storage, paragraphLocation: 13), 1)
    }

    func testTrailingEmptyNumberedParagraphUsesNextOrdinal() {
        let textView = makeTextView()
        textView.load(markdown: "1. First")

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        let decorations = BlockDecorationLayout.decorations(
            in: textView,
            textContainerOrigin: textView.textContainerOrigin,
            scale: 1
        )
        XCTAssertEqual(decorations.compactMap(\.label), ["1.", "2."])
    }

    func testWrappedListParagraphProducesOneDecoration() {
        let textView = makeTextView(width: 170)
        textView.load(markdown: "- This is a long list item that wraps over several visual lines")
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)

        let decorations = BlockDecorationLayout.decorations(
            in: textView,
            textContainerOrigin: textView.textContainerOrigin,
            scale: 1
        )

        XCTAssertEqual(decorations.count, 1)
        XCTAssertEqual(decorations.first?.kind, .bullet)
    }

    func testTodoHitTestingTogglesOnlyInsideCheckbox() throws {
        let textView = makeTextView()
        textView.load(markdown: "- [ ] Ship")
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let decoration = try XCTUnwrap(BlockDecorationLayout.decorations(
            in: textView,
            textContainerOrigin: textView.textContainerOrigin,
            scale: 1
        ).first)

        XCTAssertTrue(textView.toggleTodo(at: NSPoint(x: decoration.markerRect.midX, y: decoration.markerRect.midY)))
        XCTAssertEqual(textView.exportMarkdown(), "- [x] Ship")
        XCTAssertFalse(textView.toggleTodo(at: NSPoint(x: decoration.markerRect.maxX + 80, y: decoration.markerRect.midY)))
    }

    func testClickingMiddleTodoTogglesOnlyThatParagraph() throws {
        let textView = makeTextView()
        textView.load(markdown: "- [ ] First\n- [ ] Second\n- [ ] Third")
        let decorations = BlockDecorationLayout.decorations(
            in: textView,
            textContainerOrigin: textView.textContainerOrigin,
            scale: 1
        )

        let middle = try XCTUnwrap(decorations.dropFirst().first)
        XCTAssertTrue(textView.toggleTodo(at: NSPoint(x: middle.markerRect.midX, y: middle.markerRect.midY)))

        XCTAssertEqual(textView.exportMarkdown(), "- [ ] First\n- [x] Second\n- [ ] Third")
    }

    func testTogglingAnotherTodoDoesNotChangeCurrentLineTypingState() throws {
        let textView = makeTextView()
        textView.load(markdown: "- [ ] First\n- [ ] Second\n- [ ] Third")
        let decorations = BlockDecorationLayout.decorations(
            in: textView,
            textContainerOrigin: textView.textContainerOrigin,
            scale: 1
        )

        let first = try XCTUnwrap(decorations.first)
        XCTAssertTrue(textView.toggleTodo(at: NSPoint(x: first.markerRect.midX, y: first.markerRect.midY)))

        XCTAssertEqual(textView.typingAttributes[.dayDreamBlockKind] as? MarkdownBlockKind, .todo(checked: false))
        XCTAssertEqual(textView.exportMarkdown(), "- [x] First\n- [ ] Second\n- [ ] Third")
    }

    /// 回归：光标在文末幻影空行时点击上方 checkbox，
    /// 不得在光标处刷出一个已勾选的幻影 checkbox（typing 状态不得被污染）。
    func testTogglingTodoAbovePhantomLineDoesNotSpawnCheckedTodo() throws {
        let textView = makeTextView()
        textView.load(markdown: "- [ ] Task\n")
        // load 后光标落在文末换行后的幻影空行上。
        let decoration = try XCTUnwrap(BlockDecorationLayout.decorations(
            in: textView,
            textContainerOrigin: textView.textContainerOrigin,
            scale: 1
        ).first)

        XCTAssertTrue(textView.toggleTodo(at: NSPoint(x: decoration.markerRect.midX, y: decoration.markerRect.midY)))

        XCTAssertEqual(textView.typingAttributes[.dayDreamBlockKind] as? MarkdownBlockKind, .body)
        XCTAssertEqual(textView.exportMarkdown(), "- [x] Task\n")
        // 幻影空行不得产生任何装饰。
        let decorationsAfter = BlockDecorationLayout.decorations(
            in: textView,
            textContainerOrigin: textView.textContainerOrigin,
            scale: 1
        )
        XCTAssertEqual(decorationsAfter.count, 1)
    }

    func testListMarkerSitsDirectlyBeforeTextIndent() throws {
        let textView = makeTextView()
        textView.load(markdown: "1. First")
        let decoration = try XCTUnwrap(BlockDecorationLayout.decorations(
            in: textView,
            textContainerOrigin: textView.textContainerOrigin,
            scale: 1
        ).first)
        let textStartX = textView.textContainerOrigin.x + 30

        XCTAssertLessThanOrEqual(textStartX - decoration.markerRect.maxX, 5)
    }

    func testListMarkerUsesTextBaselineInsteadOfLooseLineFragmentCenter() throws {
        let textView = makeTextView()
        textView.load(markdown: "1. First")
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let decoration = try XCTUnwrap(BlockDecorationLayout.decorations(
            in: textView,
            textContainerOrigin: textView.textContainerOrigin,
            scale: 1
        ).first)
        let glyph = layoutManager.glyphIndexForCharacter(at: 0)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let baseline = textView.textContainerOrigin.y + lineRect.minY
            + layoutManager.location(forGlyphAt: glyph).y
        let markerFont = BlockDecorationLayout.markerFont(scale: 1)

        XCTAssertEqual(decoration.markerRect.minY, baseline - markerFont.ascender, accuracy: 0.01)
    }

    func testTodoCheckmarkPointsDownThenUpInFlippedCoordinates() {
        let points = TodoCheckmarkLayout.points(in: NSRect(x: 0, y: 0, width: 16, height: 16), scale: 1)

        XCTAssertGreaterThan(points.middle.y, points.start.y)
        XCTAssertLessThan(points.end.y, points.middle.y)
    }

    func testEmptyHeadingReturnsMutedPlaceholderLabel() {
        let textView = makeTextView()
        textView.load(markdown: "### ")

        XCTAssertEqual(textView.headingPlaceholder(at: 0), "Heading 3")
        textView.insertText("Title", replacementRange: textView.selectedRange())
        XCTAssertNil(textView.headingPlaceholder(at: textView.selectedRange().location))
    }

    func testEmptyHeadingPlaceholderUsesTheCaretBaseline() throws {
        let textView = makeTextView()
        textView.load(markdown: "# ")
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let container = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: container)
        let font = try XCTUnwrap(textView.typingAttributes[.font] as? NSFont)
        let lineRect = layoutManager.extraLineFragmentRect

        let placeholderRect = try XCTUnwrap(textView.headingPlaceholderRect(at: 0))
        let expectedY = textView.textContainerOrigin.y
            + lineRect.maxY + font.descender - font.ascender

        XCTAssertEqual(placeholderRect.minY, expectedY, accuracy: 0.01)
    }

    private func attributedStorage(for markdown: String) throws -> NSAttributedString {
        MarkdownTextStorage.attributedString(
            from: MarkdownDocumentCodec.parse(markdown),
            appearance: try XCTUnwrap(NSAppearance(named: .aqua)),
            scale: 1
        )
    }

    private func makeTextView(width: CGFloat = 700) -> DayDreamTextView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        let textView = DayDreamTextView(
            frame: NSRect(x: 0, y: 0, width: width, height: 800),
            textContainer: container
        )
        textView.textContainerInset = .zero
        return textView
    }
}
