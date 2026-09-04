import SwiftUI
import AppKit

/// 编辑器本体：SwiftUI 与 DayDreamTextView 之间的 Markdown 桥接层。
struct EditorView: NSViewRepresentable {
    let markdown: String
    let documentURL: URL?
    let autofocus: Bool
    let onMarkdownChange: (String) -> Void

    init(
        markdown: String = "",
        documentURL: URL? = nil,
        autofocus: Bool = true,
        onMarkdownChange: @escaping (String) -> Void = { _ in }
    ) {
        self.markdown = markdown
        self.documentURL = documentURL
        self.autofocus = autofocus
        self.onMarkdownChange = onMarkdownChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onMarkdownChange: onMarkdownChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = DayDreamTextView(frame: .zero, textContainer: textContainer)
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

        context.coordinator.loadedURL = documentURL
        context.coordinator.hasLoadedDocument = true
        context.coordinator.onMarkdownChange = onMarkdownChange
        textView.markdownDidChange = { [coordinator = context.coordinator] markdown in
            coordinator.onMarkdownChange(markdown)
        }
        textView.load(markdown: markdown)

        // 打开窗口即进入输入状态，光标淡入。
        if autofocus {
            DispatchQueue.main.async {
                scrollView.window?.makeFirstResponder(textView)
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        scrollView.backgroundColor = DayDreamTheme.background(for: scrollView.effectiveAppearance)
        context.coordinator.onMarkdownChange = onMarkdownChange
        guard let textView = scrollView.documentView as? DayDreamTextView else { return }

        if !context.coordinator.hasLoadedDocument
            || context.coordinator.loadedURL != documentURL {
            context.coordinator.loadedURL = documentURL
            context.coordinator.hasLoadedDocument = true
            textView.load(markdown: markdown)
        }
    }

    final class Coordinator {
        var loadedURL: URL?
        var hasLoadedDocument = false
        var onMarkdownChange: (String) -> Void

        init(onMarkdownChange: @escaping (String) -> Void) {
            self.onMarkdownChange = onMarkdownChange
        }
    }
}
