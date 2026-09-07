import AppKit
import XCTest
@testable import DayDream

@MainActor
final class EditorInteractionTests: XCTestCase {
    private func editor(_ markdown: String = "") -> DayDreamTextView {
        let storage = NSTextStorage()
        let manager = TypingLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 600, height: 10000))
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        let view = DayDreamTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 700), textContainer: container)
        view.load(markdown: markdown)
        return view
    }
    private func key(_ character: String, code: UInt16, type: NSEvent.EventType = .keyDown) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: 0, context: nil, characters: character, charactersIgnoringModifiers: character,
            isARepeat: false, keyCode: code)!
    }
    func testResetViaKeyEquivalentAndCustomBindingAffectsFutureTextOnly() {
        let prefs = ShortcutPreferences.shared
        let old = prefs.shortcut(for: .resetWritingStyle)
        defer { prefs.set(old, for: .resetWritingStyle) }
        let view = editor()
        view.activeWritingStyle = .bold; view.activeWritingColor = .pink
        view.insertText("styled", replacementRange: view.selectedRange())
        prefs.set(AppShortcut(key: "`", modifiers: .command), for: .resetWritingStyle)
        XCTAssertTrue(view.performKeyEquivalent(with: key("·", code: 50)))
        view.insertText("plain", replacementRange: view.selectedRange())
        XCTAssertNotNil(view.textStorage!.attribute(.dayDreamBold, at: 0, effectiveRange: nil))
        for location in 6..<view.string.utf16.count {
            XCTAssertNil(view.textStorage!.attribute(.dayDreamBold, at: location, effectiveRange: nil))
            XCTAssertNil(view.textStorage!.attribute(.dayDreamTextColor, at: location, effectiveRange: nil))
        }
        prefs.set(AppShortcut(key: "j", modifiers: .command), for: .resetWritingStyle)
        view.activeWritingStyle = .italic
        XCTAssertTrue(view.performKeyEquivalent(with: key("j", code: 38)))
        XCTAssertNil(view.activeWritingStyle)
    }
    func testTabOnlyNestsNumberAtStart() {
        for source in ["- item", "- [ ] item", "1. item"] {
            let view = editor(source)
            view.setSelectedRange(NSRange(location: 2, length: 0))
            view.doCommand(by: #selector(NSResponder.insertTab(_:)))
            XCTAssertEqual(view.string, "it\tem")
            XCTAssertEqual(view.currentListIndentation(at: 0), "")
        }
        for source in ["- item", "- [ ] item"] {
            let view = editor(source)
            view.setSelectedRange(NSRange(location: 0, length: 0))
            view.doCommand(by: #selector(NSResponder.insertTab(_:)))
            XCTAssertEqual(view.string, "\titem")
            XCTAssertEqual(view.currentListIndentation(at: 0), "")
        }
        let view = editor("7. item")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(view.string, "item")
        XCTAssertEqual(view.currentListIndentation(at: 0), "  ")
    }
    func testSlashQueryFiltersAndAppliesWholeQuery() {
        let view = editor()
        view.insertText("/", replacementRange: view.selectedRange())
        view.insertText("quo", replacementRange: view.selectedRange())
        XCTAssertTrue(view.isSlashCommandMenuOpen)
        XCTAssertEqual(view.filteredSlashCommands.map(\.kind), [.quote])
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(view.string, "")
        XCTAssertEqual(view.currentBlockKind(at: 0), .quote)
        XCTAssertEqual(SlashCommandCatalog.matching("复选框").map(\.kind), [.todo(checked: false)])
        XCTAssertTrue(SlashCommandCatalog.matching("zzzz").isEmpty)
    }
    func testSlashBackspaceUpdatesResults() {
        let view = editor()
        view.insertText("/", replacementRange: view.selectedRange())
        view.insertText("hx", replacementRange: view.selectedRange())
        XCTAssertTrue(view.filteredSlashCommands.isEmpty)
        view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        XCTAssertFalse(view.filteredSlashCommands.isEmpty)
        XCTAssertTrue(view.isSlashCommandMenuOpen)
    }
    func testAdjacentQuotesHaveOneContinuousRule() {
        let view = editor("> first\n> second\n\n> third")
        let marks = BlockDecorationLayout.decorations(in: view, textContainerOrigin: view.textContainerOrigin, scale: 1)
        XCTAssertEqual(marks.count, 2)
        XCTAssertEqual(marks[0].characterRange.length, "first\nsecond\n".utf16.count)
        XCTAssertLessThan(marks[0].markerRect.maxY, marks[1].markerRect.minY)
    }
    func testToolbarWaitsForMatchingReleaseAndBadgeExpires() {
        let view = editor("text")
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { view.writingBadgeTimer?.invalidate(); window.orderOut(nil); window.contentView = nil; window.close() }
        view.writingBarTrigger = 18
        view.cycleWritingBar(0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        XCTAssertTrue(view.writingBarPanel!.isVisible)
        XCTAssertFalse(view.writingBarPanel!.canBecomeKey)
        XCTAssertNil(view.activeWritingStyle)
        let pending = view.pendingWritingTool
        view.doCommand(by: #selector(NSResponder.moveLeft(_:)))
        view.dismissWritingBar()
        XCTAssertTrue(view.writingBarPanel!.isVisible)
        XCTAssertEqual(view.pendingWritingTool, pending)
        view.handleWritingBarRelease(key("a", code: 0, type: .keyUp))
        XCTAssertTrue(view.writingBarPanel!.isVisible)
        view.handleWritingBarRelease(key("1", code: 18, type: .keyUp))
        XCTAssertTrue(view.writingBarPanel!.isVisible)
        XCTAssertNil(view.activeWritingStyle)
        let release = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 55)!
        view.handleWritingBarRelease(release)
        XCTAssertFalse(view.writingBarPanel!.isVisible)
        XCTAssertNotNil(view.writingBadge)
        XCTAssertEqual(view.activeWritingStyle, pending)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertNil(view.writingBadge)
    }
    func testMissingFontFacesStillHaveVisibleBoldAndItalic() throws {
        let imported = FontLibrary.shared.fonts.first { $0.displayName == "iA Writer Mono S Regular" }
        guard let name = imported?.postScriptName else { throw XCTSkip("Imported font is not installed on this machine") }
        let font = try XCTUnwrap(NSFont(name: name, size: 20))
        for (bold, italic) in [(true, false), (false, true)] {
            let attributes = DayDreamTheme.inlineStyledAttributes(base: [.font: font], bold: bold, italic: italic,
                inlineCode: false, linkDestination: nil, imageDestination: nil, textColorName: nil,
                highlightName: nil, for: NSAppearance(named: .darkAqua)!)
            let rendered = attributes[.font] as! NSFont
            let traits = NSFontManager.shared.traits(of: rendered)
            if bold { XCTAssertTrue(traits.contains(.boldFontMask) || (attributes[.strokeWidth] as? Double ?? 0) < 0) }
            if italic { XCTAssertTrue(traits.contains(.italicFontMask) || (attributes[.obliqueness] as? Double ?? 0) > 0) }
        }
    }

    func testNativeClipboardKeyEquivalents() {
        let board = NSPasteboard.general
        let saved = board.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        defer { board.clearContents(); board.writeObjects(saved) }
        let view = editor("hello")
        view.setSelectedRange(NSRange(location: 0, length: 5))
        XCTAssertTrue(view.performKeyEquivalent(with: key("c", code: 8)))
        XCTAssertEqual(board.string(forType: .string), "hello")
        XCTAssertTrue(view.performKeyEquivalent(with: key("x", code: 7)))
        XCTAssertEqual(view.string, "")
        XCTAssertTrue(view.performKeyEquivalent(with: key("v", code: 9)))
        XCTAssertEqual(view.string, "hello")
    }
}
