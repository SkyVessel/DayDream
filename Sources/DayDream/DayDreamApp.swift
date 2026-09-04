import SwiftUI
import AppKit

@main
struct DayDreamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            WorkspaceView()
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 720, height: 880)
        .commands {
            DayDreamCommands()
        }

        // 设置页面：自动出现在 DayDream 应用菜单（⌘,）。
        Settings {
            SettingsView()
        }
    }
}

/// 快捷键菜单命令：动作由 WorkspaceView/SidebarView 注册到 ShortcutCenter。
struct DayDreamCommands: Commands {
    @ObservedObject var center = ShortcutCenter.shared
    @ObservedObject var settings = EditorSettings.shared

    var body: some Commands {
        // 替换 WindowGroup 默认的「新窗口」⌘N 与「关闭窗口」⌘W。
        CommandGroup(replacing: .newItem) {
            Button(L10n.t("新建笔记", "New Note")) { center.newNote() }
                .keyboardShortcut("n", modifiers: .command)
            Divider()
            // ⌘W：先关标签页，没有标签才关窗口。
            Button(L10n.t("关闭标签页", "Close Tab")) { center.closeTabOrWindow() }
                .keyboardShortcut("w", modifiers: .command)
        }
        CommandMenu(L10n.t("工作区", "Workspace")) {
            Button(L10n.t("聚焦侧栏", "Focus Sidebar")) { center.openSidebarAndNavigate() }
                .keyboardShortcut("o", modifiers: .command)
            Button(L10n.t("左右分屏", "Split Editor")) { center.toggleSplit() }
                .keyboardShortcut("d", modifiers: .command)
            Button(L10n.t("切换分屏焦点", "Switch Split Focus")) { center.switchPaneFocus() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button(L10n.t("切换分屏焦点", "Switch Split Focus")) { center.switchPaneFocus() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])

            Divider()

            ForEach(1...9, id: \.self) { number in
                Button(L10n.t("标签 \(number)", "Tab \(number)")) { center.switchTab(number) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
            }

            Divider()

            Button(L10n.t("重命名", "Rename")) { center.renameSelection() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!center.isSidebarFocused)
            Button(L10n.t("复制", "Copy")) { center.copySelection() }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(!center.isSidebarFocused)
            Button(L10n.t("粘贴", "Paste")) { center.paste() }
                .keyboardShortcut("v", modifiers: .command)
                .disabled(!center.isSidebarFocused)
        }
    }
}

/// 手工打包 / swift run 的应用默认激活策略不对，窗口无法成为 key window，
/// 导致键盘输入进不来。这里显式激活。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // 应用设置中的外观模式（跟随系统 / 浅色 / 深色）。
        EditorSettings.shared.applyAppearance()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 激活后确保焦点落在编辑器上，光标淡入。
        if let window = NSApp.keyWindow ?? NSApp.windows.first,
           !(window.firstResponder is NSTextView),
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
        ShortcutCenter.shared.mainWindow = window
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.backgroundColor = DayDreamTheme.background(for: window.effectiveAppearance)
        window.toolbar = nil
    }
}
