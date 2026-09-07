import AppKit
import SwiftUI
import XCTest
@testable import DayDream

@MainActor
final class EditorViewTests: XCTestCase {
    func testEditorAcceptsInsertedText() throws {
        _ = NSApplication.shared

        let hostingView = NSHostingView(rootView: EditorView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 720, height: 880)
        hostingView.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(hostingView.firstDayDreamTextView)
        XCTAssertNotNil(textView.textStorage)

        textView.insertText("hello", replacementRange: NSRange(location: 0, length: 0))

        XCTAssertEqual(textView.string, "hello")
    }

    func testRapidTypingCoalescesMarkdownNotifications() throws {
        let textView = try makeTextView()
        var changes: [String] = []
        textView.markdownDidChange = { changes.append($0) }

        for character in "fast typing" {
            textView.insertText(String(character), replacementRange: textView.selectedRange())
        }

        XCTAssertTrue(changes.isEmpty)
        let deadline = Date().addingTimeInterval(0.5)
        while changes.isEmpty, RunLoop.main.run(mode: .default, before: deadline) {}
        XCTAssertEqual(changes, ["fast typing"])
    }

    func testUneditedMarkdownExportsOriginalSourceExactly() throws {
        let textView = try makeTextView()
        let markdown = #"""
* item
5. first
6. second
- [X] task
> quote
```swift
let emphasized = *value*
```
<span style="background-color:pink;color:yellow">styled</span>
"""#

        textView.load(markdown: markdown)

        XCTAssertEqual(textView.exportMarkdown(), markdown)
    }

    func testUneditedWindowsLineEndingsRemainByteForByteIdentical() throws {
        let textView = try makeTextView()
        let markdown = "# Title\r\n\r\n* item\r\n"

        textView.load(markdown: markdown)

        XCTAssertEqual(textView.exportMarkdown(), markdown)
    }

    func testEditingOneLineKeepsNeighboringMarkdownSourceUntouched() throws {
        let textView = try makeTextView()
        textView.load(markdown: "* first\n5. second\n> untouched")
        let changedRange = (textView.string as NSString).range(of: "second")

        textView.textStorage?.replaceCharacters(in: changedRange, with: "changed")

        XCTAssertEqual(textView.exportMarkdown(), "* first\n5. changed\n> untouched")
    }

    func testNewlyTypedSpaceUsesConfiguredExtraWidth() throws {
        let previousWidth = EditorSettings.shared.spaceWidth
        EditorSettings.shared.spaceWidth = 3
        defer { EditorSettings.shared.spaceWidth = previousWidth }

        let textView = try makeTextView()
        textView.insertText("word ", replacementRange: NSRange(location: 0, length: 0))

        let kern = try XCTUnwrap(
            textView.textStorage?.attribute(.kern, at: 4, effectiveRange: nil) as? CGFloat
        )
        XCTAssertEqual(kern, DayDreamTheme.letterSpacing + 3, accuracy: 0.001)
    }

    func testFocusModeDimsOnlyTextOutsideCurrentSentence() throws {
        let previous = EditorSettings.shared.focusModeEnabled
        EditorSettings.shared.focusModeEnabled = true
        defer { EditorSettings.shared.focusModeEnabled = previous }

        let textView = try makeTextView()
        textView.load(markdown: "First sentence. Second sentence!")
        textView.setSelectedRange(NSRange(location: 20, length: 0))
        let manager = try XCTUnwrap(textView.layoutManager)

        XCTAssertNotNil(manager.temporaryAttribute(
            .foregroundColor,
            atCharacterIndex: 0,
            effectiveRange: nil
        ))
        XCTAssertNil(manager.temporaryAttribute(
            .foregroundColor,
            atCharacterIndex: 20,
            effectiveRange: nil
        ))
        XCTAssertEqual(textView.exportMarkdown(), "First sentence. Second sentence!")
    }

    func testHighlightUsesSemanticAttributeWithoutSystemBackground() throws {
        let textView = try makeTextView()
        textView.load(markdown: #"<span style="background-color:yellow">marked</span>"#)

        XCTAssertEqual(
            textView.textStorage?.attribute(.dayDreamHighlight, at: 0, effectiveRange: nil) as? String,
            "yellow"
        )
        XCTAssertNil(textView.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil))
    }

    func testHighlightToggleAppliesToMixedSelectionThenRemovesWholeSelection() throws {
        let textView = try makeTextView()
        textView.load(markdown: #"<span style="background-color:caret">one</span> two"#)
        textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))

        textView.toggleHighlight()
        XCTAssertEqual(
            textView.exportMarkdown(),
            #"<span style="background-color:#E8C0C8">one two</span>"#
        )

        textView.toggleHighlight()
        XCTAssertEqual(textView.exportMarkdown(), "one two")
    }

    func testInlineCodeShortcutActionWritesPortableBacktickMarkdown() throws {
        let textView = try makeTextView()
        textView.load(markdown: "code")
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        textView.toggleInlineCode()

        XCTAssertEqual(textView.exportMarkdown(), "`code`")
        XCTAssertEqual(
            textView.textStorage?.attribute(.dayDreamInlineCode, at: 0, effectiveRange: nil) as? Bool,
            true
        )
    }

    func testRemovingInlineStyleClearsUnsupportedUnderlineDecoration() throws {
        let textView = try makeTextView()
        textView.load(markdown: #"<span style="background-color:caret">marked</span>"#)
        let range = NSRange(location: 0, length: textView.string.utf16.count)
        textView.textStorage?.addAttributes([
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: DayDreamTheme.darkCaret,
        ], range: range)
        textView.layoutManager?.addTemporaryAttributes([
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: DayDreamTheme.darkCaret,
        ], forCharacterRange: range)
        textView.setSelectedRange(range)

        textView.toggleHighlight()

        XCTAssertNil(textView.textStorage?.attribute(.underlineStyle, at: 0, effectiveRange: nil))
        XCTAssertNil(textView.textStorage?.attribute(.underlineColor, at: 0, effectiveRange: nil))
        XCTAssertNil(textView.layoutManager?.temporaryAttribute(
            .underlineStyle,
            atCharacterIndex: 0,
            effectiveRange: nil
        ))
        XCTAssertNil(textView.layoutManager?.temporaryAttribute(
            .underlineColor,
            atCharacterIndex: 0,
            effectiveRange: nil
        ))
    }

    func testSelectionAndInlineStyleActionDoNotOpenLegacyPanel() throws {
        let textView = try makeTextView()
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 720, height: 880),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = textView.enclosingScrollView ?? textView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        defer { window.close() }
        textView.load(markdown: "select me")
        textView.setSelectedRange(NSRange(location: 0, length: 6))
        XCTAssertFalse(textView.isFormatPanelVisible)

        textView.toggleHighlight()

        XCTAssertFalse(textView.isFormatPanelVisible)
    }

    func testAdjacentHighlightRunsJoinAtCaretHeight() throws {
        let textView = try makeTextView()
        textView.load(markdown: #"<span style="background-color:yellow">one</span> <span style="background-color:yellow">two</span>"#)
        textView.layoutManager?.ensureLayout(for: try XCTUnwrap(textView.textContainer))

        let fragment = try XCTUnwrap(textView.inlineHighlightFragments().only)
        let font = try XCTUnwrap(
            textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        )
        XCTAssertEqual(fragment.preset, "yellow")
        XCTAssertEqual(fragment.rect.height, font.ascender - font.descender, accuracy: 0.01)
    }

    func testHighlightInvalidationIncludesPixelsOutsideGlyphBounds() {
        let fragment = InlineHighlightFragment(
            preset: "caret",
            characterRange: NSRange(location: 3, length: 5),
            rect: NSRect(x: 40, y: 50, width: 80, height: 24)
        )

        XCTAssertEqual(
            InlineHighlightLayout.invalidationRects(
                for: [fragment],
                intersecting: NSRange(location: 4, length: 1)
            ),
            [NSRect(x: 38, y: 48, width: 84, height: 28)]
        )
    }

    func testEditorUsesCompactDefaultPageInsets() throws {
        let textView = try makeTextView()

        XCTAssertEqual(textView.textContainerInset.width, 32, accuracy: 0.001)
        XCTAssertEqual(textView.textContainerInset.height, 40, accuracy: 0.001)
    }

    func testWideEditorCentersAReadablePage() throws {
        let textView = try makeTextView(width: 1800)

        XCTAssertEqual(textView.textContainerInset.width, 300, accuracy: 0.001)
    }

    func testCommandPlusScalesTheEntirePageByTenPercent() throws {
        let textView = try makeTextView()
        textView.string = "hello"

        let handled = textView.performKeyEquivalent(with: try commandKeyEvent(
            characters: "+",
            charactersIgnoringModifiers: "=",
            modifiers: [.command, .shift],
            keyCode: 24
        ))

        XCTAssertTrue(handled)
        XCTAssertEqual(try XCTUnwrap(textView.font).pointSize, 20.9, accuracy: 0.001)
        XCTAssertEqual(textView.textContainerInset.width, 35.2, accuracy: 0.001)
        XCTAssertEqual(textView.textContainerInset.height, 44, accuracy: 0.001)
        let storedFont = try XCTUnwrap(
            textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        )
        XCTAssertEqual(storedFont.pointSize, 20.9, accuracy: 0.001)
    }

    func testZoomInStopsAtTwoHundredPercent() throws {
        let textView = try makeTextView()
        let event = try commandKeyEvent(
            characters: "+",
            charactersIgnoringModifiers: "=",
            modifiers: [.command, .shift],
            keyCode: 24
        )

        for _ in 0..<20 {
            _ = textView.performKeyEquivalent(with: event)
        }

        XCTAssertEqual(try XCTUnwrap(textView.font).pointSize, 38, accuracy: 0.001)
        XCTAssertEqual(textView.textContainerInset.width, 64, accuracy: 0.001)
    }

    func testZoomOutStopsAtFiftyPercent() throws {
        let textView = try makeTextView()
        let event = try commandKeyEvent(
            characters: "-",
            charactersIgnoringModifiers: "-",
            modifiers: [.command],
            keyCode: 27
        )

        for _ in 0..<20 {
            _ = textView.performKeyEquivalent(with: event)
        }

        XCTAssertEqual(try XCTUnwrap(textView.font).pointSize, 9.5, accuracy: 0.001)
        XCTAssertEqual(textView.textContainerInset.width, 16, accuracy: 0.001)
    }

    private func makeTextView(width: CGFloat = 720) throws -> DayDreamTextView {
        _ = NSApplication.shared

        let hostingView = NSHostingView(rootView: EditorView())
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 880)
        hostingView.layoutSubtreeIfNeeded()
        return try XCTUnwrap(hostingView.firstDayDreamTextView)
    }

    private func commandKeyEvent(
        characters: String,
        charactersIgnoringModifiers: String,
        modifiers: NSEvent.ModifierFlags,
        keyCode: UInt16
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}

private extension Array {
    var only: Element? { count == 1 ? self[0] : nil }
}

private extension NSView {
    var firstDayDreamTextView: DayDreamTextView? {
        if let textView = self as? DayDreamTextView {
            return textView
        }

        return subviews.lazy.compactMap(\.firstDayDreamTextView).first
    }
}
