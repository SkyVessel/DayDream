import AppKit
import XCTest
@testable import DayDream

@MainActor
final class TextEditingBehaviorTests: XCTestCase {

    /// doCommand 层面：空行上连续两次 deleteToBeginningOfLine（Cmd+Backspace 的绑定）。
    func testRepeatedDeleteToBeginningOfLineAtCommandLevel() {
        let textView = makeTextView()
        textView.load(markdown: "abc")
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(textView.string, "abc\n")

        textView.doCommand(by: #selector(NSResponder.deleteToBeginningOfLine(_:)))
        XCTAssertEqual(textView.string, "abc", "第一次应删除空行")

        textView.doCommand(by: #selector(NSResponder.deleteToBeginningOfLine(_:)))
        XCTAssertEqual(textView.string, "", "第二次应删除上一行内容")
    }

    /// keyDown 事件层面：模拟真实的 Cmd+Backspace 按键路由。
    /// 注意：命令键绑定需要文本视图挂在窗口里才会走 interpretKeyEvents 分发。
    func testRepeatedCommandBackspaceKeyEvents() {
        let textView = makeTextView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 800),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = textView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        defer { window.close() }

        textView.load(markdown: "abc")
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(textView.string, "abc\n")

        textView.keyDown(with: commandBackspaceEvent())
        XCTAssertEqual(textView.string, "abc", "第一次 Cmd+Backspace 应删除空行")

        textView.keyDown(with: commandBackspaceEvent())
        XCTAssertEqual(textView.string, "", "第二次 Cmd+Backspace 应删除上一行内容")

        textView.keyDown(with: commandBackspaceEvent())
        XCTAssertEqual(textView.string, "", "文档已空，不应崩溃")
    }

    // MARK: - 工具

    private func commandBackspaceEvent() -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{7F}",
            charactersIgnoringModifiers: "\u{7F}",
            isARepeat: false,
            keyCode: 51
        )!
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
