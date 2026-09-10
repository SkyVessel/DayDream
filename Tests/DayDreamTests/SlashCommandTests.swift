import AppKit
import XCTest
@testable import DayDream

@MainActor
final class SlashCommandTests: XCTestCase {
    func testCatalogContainsOnlyRequestedCommands() {
        XCTAssertEqual(SlashCommandCatalog.all.map(\.kind), [
            .body,
            .body,
            .divider,
            .heading(level: 1),
            .heading(level: 2),
            .heading(level: 3),
            .heading(level: 4),
            .bullet,
            .numbered,
            .todo(checked: false),
            .quote,
            .code(language: nil),
        ])
        XCTAssertEqual(SlashCommandCatalog.all.map(\.syntax), [
            "page", "link page", "---", "#", "##", "###", "####", "-", "1.", "[ ]", ">", "```",
        ])
    }

    func testSelectionWrapsInBothDirections() {
        XCTAssertEqual(SlashCommandNavigation.moved(from: 8, by: 1, count: 9), 0)
        XCTAssertEqual(SlashCommandNavigation.moved(from: 0, by: -1, count: 9), 8)
        XCTAssertEqual(SlashCommandNavigation.moved(from: 2, by: 1, count: 9), 3)
    }

    func testSlashOnEmptyParagraphOpensAndAppliesCommand() {
        let textView = makeTextView()

        textView.insertText("/", replacementRange: NSRange(location: 0, length: 0))

        XCTAssertTrue(textView.isSlashCommandMenuOpen)
        textView.applySlashCommand(.heading(level: 2))
        XCTAssertFalse(textView.isSlashCommandMenuOpen)
        XCTAssertEqual(textView.string, "")
        XCTAssertEqual(textView.currentBlockKind(at: 0), .heading(level: 2))
    }

    func testSlashAfterExistingTextDoesNotOpenMenu() {
        let textView = makeTextView()
        textView.load(markdown: "Body")

        textView.insertText("/", replacementRange: textView.selectedRange())

        XCTAssertFalse(textView.isSlashCommandMenuOpen)
        XCTAssertEqual(textView.string, "Body/")
    }

    func testBackspaceClosesSlashMenuAndDeletesSlash() {
        let textView = makeTextView()
        textView.insertText("/", replacementRange: NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertFalse(textView.isSlashCommandMenuOpen)
        XCTAssertEqual(textView.string, "")
    }

    func testSlashPanelBuildsAtExpectedSizeBesideCaretInAWindow() throws {
        let textView = makeTextView()
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 700, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = textView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        let existingPanels = Set(NSApp.windows.compactMap { window in
            (window as? SlashCommandPanel).map(ObjectIdentifier.init)
        })

        textView.insertText("/", replacementRange: NSRange(location: 0, length: 0))

        let panel = try XCTUnwrap(NSApp.windows.compactMap { $0 as? SlashCommandPanel }.first {
            !existingPanels.contains(ObjectIdentifier($0))
        })
        XCTAssertTrue(textView.isSlashCommandMenuOpen)
        XCTAssertEqual(panel.frame.width, 320, accuracy: 0.001)
        XCTAssertGreaterThan(panel.frame.height, 350)
        window.close()
        panel.close()
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
