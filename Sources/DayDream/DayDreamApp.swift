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
    @ObservedObject var shortcuts = ShortcutPreferences.shared

    var body: some Commands {
        // 替换 WindowGroup 默认的「新窗口」⌘N；⌘W 保持系统关闭窗口行为。
        CommandGroup(replacing: .newItem) {
            Button(L10n.t("新建笔记", "New Note")) { center.newNote() }
                .keyboardShortcut(
                    shortcuts.shortcut(for: .newNote).keyEquivalent,
                    modifiers: shortcuts.shortcut(for: .newNote).eventModifiers
                )
        }
        CommandMenu(L10n.t("工作区", "Workspace")) {
            Button(L10n.t("打开 / 关闭侧栏", "Toggle Sidebar")) { center.toggleSidebar() }
                .keyboardShortcut(
                    shortcuts.shortcut(for: .toggleSidebar).keyEquivalent,
                    modifiers: shortcuts.shortcut(for: .toggleSidebar).eventModifiers
                )
            Button(L10n.t("关闭窗口", "Close Window")) {
                (NSApp.keyWindow ?? center.mainWindow)?.performClose(nil)
            }
            .keyboardShortcut(
                shortcuts.shortcut(for: .closeWindow).keyEquivalent,
                modifiers: shortcuts.shortcut(for: .closeWindow).eventModifiers
            )

            Divider()

            Button(L10n.t("重命名", "Rename")) { center.renameSelection() }
                .keyboardShortcut(
                    shortcuts.shortcut(for: .renameSelection).keyEquivalent,
                    modifiers: shortcuts.shortcut(for: .renameSelection).eventModifiers
                )
                .disabled(!center.isSidebarFocused)
            Button(L10n.t("复制", "Copy")) { center.copySelection() }

                .disabled(!center.isSidebarFocused)
            Button(L10n.t("粘贴", "Paste")) { center.paste() }

                .disabled(!center.isSidebarFocused)
        }
        CommandMenu(L10n.t("格式", "Format")) {
            Button(L10n.t("恢复默认打字样式", "Reset Typing Style")) {
                (NSApp.keyWindow?.firstResponder as? DayDreamTextView)?.resetWritingStyle()
            }
            .keyboardShortcut(shortcuts.shortcut(for: .resetWritingStyle).keyEquivalent,
                              modifiers: shortcuts.shortcut(for: .resetWritingStyle).eventModifiers)
            Divider()
            formattingButton(L10n.t("粗体", "Bold"), command: .bold, action: center.toggleBold)
            formattingButton(L10n.t("斜体", "Italic"), command: .italic, action: center.toggleItalic)
            formattingButton(L10n.t("高亮", "Highlight"), command: .highlight, action: center.toggleHighlight)
            formattingButton(L10n.t("文字颜色", "Text Color"), command: .textColor, action: center.toggleTextColor)
            formattingButton(L10n.t("行内代码", "Inline Code"), command: .inlineCode, action: center.toggleInlineCode)
        }
    }

    private func formattingButton(
        _ title: String,
        command: ShortcutCommand,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .keyboardShortcut(
                shortcuts.shortcut(for: command).keyEquivalent,
                modifiers: shortcuts.shortcut(for: command).eventModifiers
            )
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
        ShortcutEventMonitor.shared.install()
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
