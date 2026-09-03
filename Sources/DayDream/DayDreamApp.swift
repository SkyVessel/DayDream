import SwiftUI
import AppKit

@main
struct DayDreamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            EditorView()
                .frame(minWidth: 560, minHeight: 420)
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 720, height: 880)
    }
}

/// 手工打包 / swift run 的应用默认激活策略不对，窗口无法成为 key window，
/// 导致键盘输入进不来。这里显式激活。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 激活后确保焦点落在编辑器上，光标淡入。
        if let window = NSApp.keyWindow ?? NSApp.windows.first,
           let textView = window.contentView?.firstTextView {
            window.makeFirstResponder(textView)
        }
    }
}

private extension NSView {
    var firstTextView: NSTextView? {
        if let textView = self as? NSTextView { return textView }
        for subview in subviews {
            if let found = subview.firstTextView { return found }
        }
        return nil
    }
}

/// 把窗口配置成「一张纯纸」：隐藏标题栏，内容铺满，可拖拽背景移动窗口。
private struct WindowConfigurator: NSViewRepresentable {

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            configure(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        window.backgroundColor = DayDreamTheme.background(for: window.effectiveAppearance)
    }

    private func configure(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.backgroundColor = DayDreamTheme.background(for: window.effectiveAppearance)
        window.toolbar = nil
    }
}
