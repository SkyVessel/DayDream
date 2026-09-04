import AppKit
import SwiftUI
import XCTest
@testable import DayDream

@MainActor
final class WorkspaceViewTests: XCTestCase {
    func testEditorBridgeLoadsMarkdownAndPublishesSerializedChanges() throws {
        let noteURL = URL(fileURLWithPath: "/tmp/First.md")
        var changes: [String] = []
        let hostingView = NSHostingView(rootView: EditorView(
            markdown: "# Title",
            documentURL: noteURL,
            onMarkdownChange: { changes.append($0) }
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 720, height: 880)
        hostingView.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(hostingView.firstMarkdownTextView)

        XCTAssertEqual(textView.string, "Title")
        textView.insertText("!", replacementRange: textView.selectedRange())

        XCTAssertEqual(changes.last, "# Title!")
    }

    func testChangingDocumentURLReplacesEditorContent() throws {
        let firstURL = URL(fileURLWithPath: "/tmp/First.md")
        let secondURL = URL(fileURLWithPath: "/tmp/Second.md")
        let hostingView = NSHostingView(rootView: EditorView(
            markdown: "# First",
            documentURL: firstURL,
            onMarkdownChange: { _ in }
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 720, height: 880)
        hostingView.layoutSubtreeIfNeeded()

        hostingView.rootView = EditorView(
            markdown: "- Second",
            documentURL: secondURL,
            onMarkdownChange: { _ in }
        )
        hostingView.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(hostingView.firstMarkdownTextView)
        XCTAssertEqual(textView.string, "Second")
        XCTAssertEqual(textView.exportMarkdown(), "- Second")
    }
}

private extension NSView {
    var firstMarkdownTextView: DayDreamTextView? {
        if let textView = self as? DayDreamTextView { return textView }
        return subviews.lazy.compactMap(\.firstMarkdownTextView).first
    }
}
