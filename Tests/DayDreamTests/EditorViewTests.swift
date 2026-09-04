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

private extension NSView {
    var firstDayDreamTextView: DayDreamTextView? {
        if let textView = self as? DayDreamTextView {
            return textView
        }

        return subviews.lazy.compactMap(\.firstDayDreamTextView).first
    }
}
