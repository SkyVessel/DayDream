import AppKit
import XCTest
@testable import DayDream

@MainActor
final class ToolbarPolishTests: XCTestCase {
    private func editor(_ source: String = "sample") -> DayDreamTextView {
        let storage = NSTextStorage(), manager = TypingLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 600, height: 10000))
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        let view = DayDreamTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 700), textContainer: container)
        view.load(markdown: source)
        return view
    }

    func testHighlightAndLegacyToolsFollowSettingsForSelectionAndFutureText() {
        let settings = EditorSettings.shared
        let previous = settings.highlightPreset
        defer { settings.highlightPreset = previous }
        settings.highlightPreset = "pink"
        let view = editor()
        view.setSelectedRange(NSRange(location: 0, length: 6))
        view.pendingWritingTool = WritingTool(rawValue: "highlight:yellow")!
        view.commitWritingBarSelection()
        XCTAssertEqual(view.textStorage!.attribute(.dayDreamHighlight, at: 0, effectiveRange: nil) as? String, "pink")
        settings.highlightPreset = "green"
        view.setSelectedRange(NSRange(location: 6, length: 0))
        view.insertText("new", replacementRange: view.selectedRange())
        XCTAssertEqual(view.textStorage!.attribute(.dayDreamHighlight, at: 6, effectiveRange: nil) as? String, "green")
        XCTAssertEqual(view.textStorage!.attribute(.dayDreamHighlight, at: 0, effectiveRange: nil) as? String, "pink")
        XCTAssertEqual(WritingTool.allCases.filter { $0.highlightColor != nil }.count, 1)
    }

    func testEachSelectedInlineStyleCanBeAppliedThenRemoved() {
        let cases: [(WritingTool, NSAttributedString.Key)] = [
            (.bold, .dayDreamBold), (.italic, .dayDreamItalic), (.inlineCode, .dayDreamInlineCode),
            (.font("Helvetica"), .dayDreamFontFamily), (.pink, .dayDreamTextColor), (.highlight, .dayDreamHighlight)
        ]
        for (tool, key) in cases {
            let view = editor()
            view.setSelectedRange(NSRange(location: 0, length: 6))
            view.pendingWritingTool = tool; view.commitWritingBarSelection()
            XCTAssertNotNil(view.textStorage!.attribute(key, at: 0, effectiveRange: nil), tool.rawValue)
            view.pendingWritingTool = tool; view.commitWritingBarSelection()
            XCTAssertNil(view.textStorage!.attribute(key, at: 0, effectiveRange: nil), tool.rawValue)
            view.setSelectedRange(NSRange(location: 6, length: 0))
            view.insertText("plain", replacementRange: view.selectedRange())
            XCTAssertNil(view.textStorage!.attribute(key, at: 6, effectiveRange: nil), tool.rawValue)
        }
    }

    func testMixedSelectionAppliesFirstAndTogglePreservesOtherStyles() {
        let view = editor()
        view.setSelectedRange(NSRange(location: 0, length: 3))
        view.applyWritingToolToSelection(.bold)
        view.setSelectedRange(NSRange(location: 0, length: 6))
        view.applyWritingToolToSelection(.bold)
        XCTAssertTrue(view.writingToolIsAppliedToSelection(.bold))
        view.applyWritingToolToSelection(.highlight)
        view.applyWritingToolToSelection(.bold)
        XCTAssertFalse(view.writingToolIsAppliedToSelection(.bold))
        XCTAssertTrue(view.writingToolIsAppliedToSelection(.highlight))
    }

    func testParagraphStyleTogglesBackToBody() {
        let view = editor("first\nsecond")
        view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
        let tool = WritingTool(rawValue: "block:quote")!
        view.applyWritingToolToSelection(tool)
        XCTAssertTrue(view.writingToolIsAppliedToSelection(tool))
        view.applyWritingToolToSelection(tool)
        XCTAssertEqual(view.currentBlockKind(at: 0), .body)
        XCTAssertEqual(view.currentBlockKind(at: 6), .body)
    }

    func testSiteIconUsesSquareImageBounds() {
        let icon = SiteIconAttachment(url: URL(fileURLWithPath: "/unused-test-icon"), size: 18)
        XCTAssertEqual(icon.bounds.width, 18)
        XCTAssertEqual(icon.bounds.height, 18)
    }

    func testDefaultResetIsCommandThreeAndCustomShortcutIsPreserved() throws {
        XCTAssertEqual(ShortcutCommand.resetWritingStyle.defaultShortcut, AppShortcut(key: "3", modifiers: .command))
        let name = "DayDreamTests.Reset." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = ShortcutPreferences(defaults: defaults)
        XCTAssertEqual(settings.shortcut(for: .resetWritingStyle).key, "3")
        settings.set(AppShortcut(key: "q", modifiers: .command), for: .resetWritingStyle)
        XCTAssertEqual(ShortcutPreferences(defaults: defaults).shortcut(for: .resetWritingStyle).key, "q")
        settings.resetToDefaults()
        XCTAssertEqual(settings.shortcut(for: .resetWritingStyle).key, "3")
    }
}
