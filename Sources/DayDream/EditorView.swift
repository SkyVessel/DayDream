import SwiftUI
import AppKit

/// 编辑器本体：SwiftUI 与 DayDreamTextView 之间的 Markdown 桥接层。
struct EditorView: NSViewRepresentable {
    let markdown: String
    let documentURL: URL?
    let reloadRevision: Int
    let autofocus: Bool
    let onMarkdownChange: (String) -> Void
    /// 编辑器获得键盘焦点时回调（用于退出侧栏焦点）。
    var onBecameFirstResponder: (() -> Void)?
    /// 创建后把底层文本视图注册出去（用于从侧栏恢复编辑器焦点）。
    var registerTextView: ((DayDreamTextView) -> Void)?

    init(
        markdown: String = "",
        documentURL: URL? = nil,
        reloadRevision: Int = 0,
        autofocus: Bool = true,
        onMarkdownChange: @escaping (String) -> Void = { _ in },
        onBecameFirstResponder: (() -> Void)? = nil,
        registerTextView: ((DayDreamTextView) -> Void)? = nil
    ) {
        self.markdown = markdown
        self.documentURL = documentURL
        self.reloadRevision = reloadRevision
        self.autofocus = autofocus
        self.onMarkdownChange = onMarkdownChange
        self.onBecameFirstResponder = onBecameFirstResponder
        self.registerTextView = registerTextView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onMarkdownChange: onMarkdownChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = NSTextStorage()
        let layoutManager = TypingLayoutManager()
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

        let scrollView = EditorScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.appearance = DocumentAppearance.stored(for: documentURL)?.appearance
        scrollView.backgroundColor = DayDreamTheme.background(for: scrollView.effectiveAppearance)

        context.coordinator.loadedURL = documentURL
        context.coordinator.loadedRevision = reloadRevision
        context.coordinator.hasLoadedDocument = true
        context.coordinator.onMarkdownChange = onMarkdownChange
        textView.onBecameFirstResponder = onBecameFirstResponder
        registerTextView?(textView)
        textView.markdownDidChange = { [coordinator = context.coordinator] markdown in
            coordinator.onMarkdownChange(markdown)
        }
        textView.documentURL = documentURL
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
        scrollView.appearance = DocumentAppearance.stored(for: documentURL)?.appearance
        scrollView.backgroundColor = DayDreamTheme.background(for: scrollView.effectiveAppearance)
        context.coordinator.onMarkdownChange = onMarkdownChange
        guard let textView = scrollView.documentView as? DayDreamTextView else { return }
        textView.onBecameFirstResponder = onBecameFirstResponder

        if !context.coordinator.hasLoadedDocument
            || context.coordinator.loadedURL != documentURL
            || context.coordinator.loadedRevision != reloadRevision {
            let oldURL = context.coordinator.loadedURL
            let selection = textView.selectedRange()
            let isRename = oldURL != documentURL && oldURL?.deletingLastPathComponent() == documentURL?.deletingLastPathComponent()
                && oldURL.map { !FileManager.default.fileExists(atPath: $0.path) } == true
                && textView.exportMarkdown() == markdown
            context.coordinator.loadedURL = documentURL
            context.coordinator.loadedRevision = reloadRevision
            context.coordinator.hasLoadedDocument = true
            textView.documentURL = documentURL
            if !isRename {
                textView.load(markdown: markdown)
                if oldURL == documentURL {
                    let location = min(selection.location, textView.string.utf16.count)
                    textView.setSelectedRange(NSRange(location: location, length: min(selection.length, textView.string.utf16.count - location)))
                }
            }
        }
    }

    final class Coordinator {
        var loadedURL: URL?
        var loadedRevision = 0
        var hasLoadedDocument = false
        var onMarkdownChange: (String) -> Void

        init(onMarkdownChange: @escaping (String) -> Void) {
            self.onMarkdownChange = onMarkdownChange
        }
    }
}

/// Wheel and trackpad momentum events follow the viewport in Ultra Focus.
final class EditorScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard let editor = documentView as? DayDreamTextView, editor.isUltraFocus else {
            super.scrollWheel(with: event)
            return
        }
        editor.ultraScrollTimer?.invalidate(); editor.ultraScrollTimer = nil
        editor.isUserScrollingUltra = true
        defer { editor.isUserScrollingUltra = false }
        super.scrollWheel(with: event)
        editor.followUltraFocusViewport()
    }
}
