import SwiftUI
import AppKit

/// 编辑器本体：一个滚动视图 + DayDreamTextView，除此之外什么都没有。
struct EditorView: NSViewRepresentable {

    func makeNSView(context: Context) -> NSScrollView {
        let textView = DayDreamTextView(frame: .zero, textContainer: nil)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = NSView.AutoresizingMask.width
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = DayDreamTheme.background(for: scrollView.effectiveAppearance)

        // 打开窗口即进入输入状态，光标淡入。
        DispatchQueue.main.async {
            scrollView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        scrollView.backgroundColor = DayDreamTheme.background(for: scrollView.effectiveAppearance)
    }
}
