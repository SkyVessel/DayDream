import SwiftUI
import AppKit

@main
struct DayDreamApp: App {
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
