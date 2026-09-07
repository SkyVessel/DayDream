import AppKit
import Combine

/// 快捷键中枢：菜单命令（DayDreamCommands）与视图层（WorkspaceView/SidebarView）
/// 之间的解耦层。视图在 onAppear 时注册动作闭包。
@MainActor
final class ShortcutCenter: ObservableObject {
    static let shared = ShortcutCenter()

    /// 侧栏是否处于「焦点」状态（⌘O 打开后进入，点击编辑器退出）。
    /// ⌘R / ⌘C / ⌘V 仅在此状态下接管。
    @Published var isSidebarFocused = false

    /// 侧栏键盘导航当前所在行。
    @Published var sidebarNavigationURL: URL?

    weak var mainWindow: NSWindow?

    // 由 WorkspaceView / SidebarView 注册
    var newNote: () -> Void = {}
    var toggleSidebar: () -> Void = {}
    var renameSelection: () -> Void = {}
    var copySelection: () -> Void = {}
    var paste: () -> Void = {}
    var deleteSelection: () -> Void = {}
    var refocusEditor: () -> Void = {}
    var toggleBold: () -> Void = {}
    var toggleItalic: () -> Void = {}
    var toggleHighlight: () -> Void = {}
    var toggleTextColor: () -> Void = {}
    var toggleInlineCode: () -> Void = {}

    @Published var ultraFocusEnabled = false
    var writingCommand: (ShortcutCommand) -> Void = { _ in }

    private init() {}
}

extension Notification.Name {
    /// 请求侧栏对指定 URL 进入重命名状态（object 为 URL）。
    static let dayDreamBeginRename = Notification.Name("DayDream.beginRename")
}
