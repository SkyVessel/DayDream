import SwiftUI
import AppKit

@main
struct DayDreamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands { DayDreamCommands() }
    }
}

/// 快捷键菜单命令：动作由 WorkspaceView/SidebarView 注册到 ShortcutCenter。
struct DayDreamCommands: Commands {
    private var center: ShortcutCenter { ShortcutCenter.shared }
    @ObservedObject var shortcuts = ShortcutPreferences.shared

    var body: some Commands {
        // 新建笔记与关闭笔记由活动编辑器的快捷键中心处理。
        CommandGroup(replacing: .newItem) {
            Button(L10n.t("新建笔记", "New Note")) {
                if NSApp.keyWindow == nil {
                    AppDelegate.current?.showWorkspace()
                    DispatchQueue.main.async { ShortcutCenter.shared.newNote() }
                } else { center.newNote() }
            }
                .keyboardShortcut(
                    shortcuts.shortcut(for: .newNote).keyEquivalent,
                    modifiers: shortcuts.shortcut(for: .newNote).eventModifiers
                )
        }
        CommandMenu(L10n.t("工作区", "Workspace")) {
            Button(L10n.t("打开笔记库", "Open Library")) { AppDelegate.current?.showWorkspace() }
            Button(L10n.t("搜索文件", "Search Files")) { center.searchFiles() }
                .keyboardShortcut(shortcuts.shortcut(for: .searchFiles).keyEquivalent, modifiers: shortcuts.shortcut(for: .searchFiles).eventModifiers)
            Divider()
            Button(L10n.t("专注模式", "Focus Mode")) { EditorSettings.shared.focusModeEnabled.toggle() }
                .keyboardShortcut(shortcuts.shortcut(for: .toggleFocus).keyEquivalent, modifiers: shortcuts.shortcut(for: .toggleFocus).eventModifiers)
            Button(L10n.t("打开 / 关闭侧栏", "Toggle Sidebar")) { center.toggleSidebar() }
                .keyboardShortcut(
                    shortcuts.shortcut(for: .toggleSidebar).keyEquivalent,
                    modifiers: shortcuts.shortcut(for: .toggleSidebar).eventModifiers
                )
            Button(L10n.t("关闭笔记", "Close Note")) {
                center.closeNote()
            }
            .keyboardShortcut(
                shortcuts.shortcut(for: .closeWindow).keyEquivalent,
                modifiers: shortcuts.shortcut(for: .closeWindow).eventModifiers
            )

            Divider()

            Button(L10n.t("重命名", "Rename")) { if center.isSidebarFocused { center.renameSelection() } }
                .keyboardShortcut(
                    shortcuts.shortcut(for: .renameSelection).keyEquivalent,
                    modifiers: shortcuts.shortcut(for: .renameSelection).eventModifiers
                )
            Button(L10n.t("复制", "Copy")) { if center.isSidebarFocused { center.copySelection() } }

            Button(L10n.t("粘贴", "Paste")) { if center.isSidebarFocused { center.paste() } }

        }
        CommandMenu(L10n.t("格式", "Format")) {
            Button(L10n.t("恢复默认打字样式", "Reset Typing Style")) {
                (NSApp.keyWindow?.firstResponder as? DayDreamTextView)?.resetSelectedAndTypingStyle()
            }
            .keyboardShortcut(shortcuts.shortcut(for: .resetWritingStyle).keyEquivalent,
                              modifiers: shortcuts.shortcut(for: .resetWritingStyle).eventModifiers)
            Divider()
            formattingButton(L10n.t("粗体", "Bold"), command: .bold, action: center.toggleBold)
            formattingButton(L10n.t("斜体", "Italic"), command: .italic, action: center.toggleItalic)
            formattingButton(L10n.t("下划线", "Underline"), command: .underline) { (NSApp.keyWindow?.firstResponder as? DayDreamTextView)?.toggleDecoration(.underline) }
            formattingButton(L10n.t("删除线", "Strikethrough"), command: .strikethrough) { (NSApp.keyWindow?.firstResponder as? DayDreamTextView)?.toggleDecoration(.strikethrough) }
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
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var current: AppDelegate?
    override init() { super.init(); Self.current = self }
    private var externalWindows: [ExternalDocumentWindow] = []
    private var workspaceWindow: WorkspaceWindowController?

    func showWorkspace() {
        if workspaceWindow == nil { workspaceWindow = WorkspaceWindowController() }
        workspaceWindow?.showWindow(nil)
        workspaceWindow?.window?.makeKeyAndOrderFront(nil)
    }

    func searchWorkspace() {
        showWorkspace()
        workspaceWindow?.requestSearch()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showWorkspace() }
        return false
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        showWorkspace()
        return true
    }


    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        var succeeded = true
        for filename in filenames {
            let url = URL(fileURLWithPath: filename).standardizedFileURL
            if let existing = externalWindows.first(where: { $0.fileDocument.currentURL == url }) {
                existing.showWindow(nil); existing.window?.makeKeyAndOrderFront(nil)
                continue
            }
            guard let controller = ExternalDocumentWindow(url: url) else { succeeded = false; continue }
            controller.onClose = { [weak self, weak controller] in
                self?.externalWindows.removeAll { $0 === controller }
            }
            externalWindows.append(controller)
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
        }
        sender.reply(toOpenOrPrint: succeeded ? .success : .failure)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        externalWindows.allSatisfy { $0.save() } && workspaceWindow?.save() != false ? .terminateNow : .terminateCancel
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // 应用设置中的外观模式（跟随系统 / 浅色 / 深色）。
        EditorSettings.shared.applyAppearance()
        ShortcutEventMonitor.shared.install()
        // The native open-untitled event opens the library. File-open events go
        // exclusively through openFiles, without scheduling a competing window.
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

/// Library windows are explicit, so a Finder-open event creates only its preview.
@MainActor
final class WorkspaceWindowController: NSWindowController, NSWindowDelegate {
    private weak var left: WorkspaceCoordinator?
    private weak var right: WorkspaceCoordinator?
    private var searchPending = false

    func requestSearch() {
        guard let left else { searchPending = true; return }
        left.center.searchFiles()
    }

    func registerCoordinator(_ coordinator: WorkspaceCoordinator, isRight: Bool) {
        if isRight { right = coordinator; return }
        left = coordinator
        if searchPending {
            searchPending = false
            coordinator.center.searchFiles()
        }
    }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 880), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        let content = NSHostingView(rootView: WorkspaceHost(registerCoordinator: { [weak self] coordinator, isRight in
            self?.registerCoordinator(coordinator, isRight: isRight)
        }))
        content.frame = NSRect(origin: .zero, size: window.contentLayoutRect.size)
        content.autoresizingMask = [.width, .height]
        window.contentView = content
        window.contentMinSize = NSSize(width: 560, height: 420)
        window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    func save() -> Bool { left?.flushDocument() != false && right?.flushDocument() != false }
    func windowShouldClose(_ sender: NSWindow) -> Bool { save() }
}
