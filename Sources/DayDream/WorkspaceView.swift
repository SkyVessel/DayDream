import AppKit
import SwiftUI

/// 工作区协调器：分屏状态、焦点窗格、快捷键动作。
/// 快捷键闭包需要逃逸并修改状态，所以集中在 class 里。
@MainActor
final class WorkspaceCoordinator: ObservableObject {
    @Published var isSplit = false
    /// 焦点窗格：0 = 左（或唯一），1 = 右。
    @Published var focusedPane = 0
    /// 各窗格的底层文本视图（用于 ⌘⌥←/→ 焦点切换，看光标就够了）。
    var textViews: [Int: DayDreamTextView] = [:]

    private var store: WorkspaceStore?
    private var paneA: EditorPaneStore?
    private var paneB: EditorPaneStore?
    private var center: ShortcutCenter { ShortcutCenter.shared }

    func pane(for index: Int) -> EditorPaneStore? {
        index == 1 ? paneB : paneA
    }

    func focusedPaneStore() -> EditorPaneStore? {
        pane(for: focusedPane)
    }

    func flushPanes() {
        paneA?.flush()
        paneB?.flush()
    }

    func configure(store: WorkspaceStore, paneA: EditorPaneStore, paneB: EditorPaneStore) {
        self.store = store
        self.paneA = paneA
        self.paneB = paneB
        registerShortcuts()
    }

    // MARK: - 标签页与分屏

    func closeTab(at index: Int, in paneIndex: Int) {
        guard let pane = pane(for: paneIndex) else { return }
        pane.closeTab(at: index)
        // 分屏中右窗格关空了：焦点回到左窗格（分屏保留，可继续 ⌘O 选笔记）。
        if pane.tabs.isEmpty, isSplit, paneIndex == 1 {
            focusedPane = 0
        }
    }

    func focusEditor() {
        DispatchQueue.main.async { [center, weak self] in
            guard let self else { return }
            if let textView = self.textViews[self.focusedPane] {
                center.mainWindow?.makeFirstResponder(textView)
            }
        }
    }

    private func unsplit() {
        guard let paneA, let paneB else { return }
        paneB.flush()
        paneA.mergeTabs(from: paneB)
        isSplit = false
        focusedPane = 0
    }

    // MARK: - 快捷键动作注册

    private func registerShortcuts() {
        guard let store, let paneA, let paneB else { return }
        let center = center

        store.beforeMutation = { [paneA, paneB] in
            paneA.flush()
            paneB.flush()
        }

        center.newNote = { [store, weak self] in
            guard let self else { return }
            do {
                let parent = store.parentForNewNode()
                let url = try store.createNote(in: parent)
                store.select(url)
                self.focusedPaneStore()?.open(url)
                NotificationCenter.default.post(name: .dayDreamBeginRename, object: url)
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }

        center.openSidebarAndNavigate = { [store, weak self] in
            self?.sidebarVisibilityHandler?(true)
            center.isSidebarFocused = true
            center.sidebarNavigationURL = store.selectedURL ?? store.nodes.first?.url
            center.mainWindow?.makeFirstResponder(nil)
        }

        center.toggleSplit = { [weak self] in
            guard let self else { return }
            if self.isSplit {
                self.unsplit()
            } else {
                self.isSplit = true
                self.focusedPane = 1
            }
        }

        center.switchPaneFocus = { [weak self] in
            guard let self, self.isSplit else { return }
            self.focusedPane = 1 - self.focusedPane
            self.focusEditor()
        }

        center.switchTab = { [weak self] tabNumber in
            guard let self else { return }
            self.focusedPaneStore()?.selectTab(at: tabNumber - 1)
            self.focusEditor()
        }

        center.closeTabOrWindow = { [weak self] in
            guard let self else { return }
            // 设置等非主窗口在前时，⌘W 关闭该窗口。
            if let key = NSApp.keyWindow, key != center.mainWindow {
                key.performClose(nil)
                return
            }
            if let pane = self.focusedPaneStore(), pane.activeIndex >= 0 {
                self.closeTab(at: pane.activeIndex, in: self.focusedPane)
            } else if self.isSplit {
                self.unsplit()
            } else {
                center.mainWindow?.performClose(nil)
            }
        }

        center.refocusEditor = { [weak self] in
            self?.focusEditor()
        }
    }

    /// ⌘O 需要把侧栏打开——由 View 注入（@State 归 View 管）。
    var sidebarVisibilityHandler: ((Bool) -> Void)?
}

@MainActor
struct WorkspaceView: View {
    @StateObject private var store: WorkspaceStore
    @ObservedObject private var settings = EditorSettings.shared
    @StateObject private var coordinator = WorkspaceCoordinator()
    @ObservedObject private var shortcutCenter = ShortcutCenter.shared

    @StateObject private var paneA = EditorPaneStore()
    @StateObject private var paneB = EditorPaneStore()

    @State private var isSidebarVisible = true
    @State private var isFullScreen = false

    init() {
        _store = StateObject(wrappedValue: WorkspaceStore(repositoryDefaults: .standard))
    }

    init(store: WorkspaceStore) {
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if isSidebarVisible {
                    SidebarView(
                        store: store,
                        isFullScreen: isFullScreen,
                        onOpenNote: { url in
                            if coordinator.isSplit,
                               paneB.tabs.contains(url), !paneA.tabs.contains(url) {
                                coordinator.focusedPane = 1
                            } else {
                                coordinator.focusedPane = 0
                            }
                            coordinator.focusedPaneStore()?.open(url)
                        },
                        onStructureChange: { change in
                            paneA.applyStructureChange(change)
                            paneB.applyStructureChange(change)
                        }
                    )
                    .frame(width: 250)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                HStack(spacing: 0) {
                    paneView(paneA, index: 0)
                    if coordinator.isSplit {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor).opacity(0.4))
                            .frame(width: 0.5)
                        paneView(paneB, index: 1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            sidebarToggle
                .padding(.leading, sidebarToggleLeadingInset)
                .padding(.top, sidebarToggleTopInset)
                .offset(y: sidebarToggleVerticalOffset)
                .zIndex(10)
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Color(nsColor: DayDreamTheme.background(for: NSApp.effectiveAppearance)))
        .animation(.easeOut(duration: 0.16), value: isSidebarVisible)
        .animation(.easeOut(duration: 0.18), value: isFullScreen)
        .animation(.easeOut(duration: 0.16), value: coordinator.isSplit)
        .onAppear {
            coordinator.sidebarVisibilityHandler = { visible in
                withAnimation { isSidebarVisible = visible }
            }
            coordinator.configure(store: store, paneA: paneA, paneB: paneB)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            coordinator.flushPanes()
        }
        .onDisappear {
            coordinator.flushPanes()
        }
    }

    // MARK: - 窗格

    @ViewBuilder
    private func paneView(_ pane: EditorPaneStore, index: Int) -> some View {
        VStack(spacing: 0) {
            if !pane.tabs.isEmpty {
                TabStripView(
                    pane: pane,
                    onSelect: { tabIndex in
                        coordinator.focusedPane = index
                        pane.selectTab(at: tabIndex)
                        coordinator.focusEditor()
                    },
                    onClose: { tabIndex in
                        coordinator.closeTab(at: tabIndex, in: index)
                    }
                )
            }

            if let url = pane.activeURL {
                EditorView(
                    markdown: pane.markdown,
                    documentURL: url,
                    autofocus: false,
                    onMarkdownChange: { pane.updateMarkdown($0) },
                    onBecameFirstResponder: {
                        coordinator.focusedPane = index
                        shortcutCenter.isSidebarFocused = false
                        shortcutCenter.sidebarNavigationURL = nil
                    },
                    registerTextView: { textView in
                        coordinator.textViews[index] = textView
                    }
                )
            } else {
                ZStack {
                    Color(nsColor: DayDreamTheme.background(for: NSApp.effectiveAppearance))
                    Text(store.nodes.isEmpty
                         ? L10n.t("创建你的第一篇笔记", "Create your first note")
                         : L10n.t("选择一篇笔记", "Select a note"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary.opacity(0.58))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 侧栏开关

    private var sidebarToggle: some View {
        Button {
            isSidebarVisible.toggle()
        } label: {
            DayDreamIcon(
                name: .sidebar,
                color: Color(nsColor: .secondaryLabelColor),
                strokeWidth: 1.65
            )
            .frame(width: 17, height: 17)
            .frame(width: 32, height: 32)
            .background(.ultraThinMaterial, in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isSidebarVisible ? L10n.t("隐藏侧栏", "Hide sidebar") : L10n.t("显示侧栏", "Show sidebar"))
        .accessibilityLabel(isSidebarVisible ? L10n.t("隐藏侧栏", "Hide sidebar") : L10n.t("显示侧栏", "Show sidebar"))
    }

    private var sidebarToggleLeadingInset: CGFloat {
        if isSidebarVisible { return 175 }
        return isFullScreen ? 8 : 76
    }

    private var sidebarToggleTopInset: CGFloat {
        if isSidebarVisible { return isFullScreen ? 28.5 : 8 }
        return isFullScreen ? 9 : 8
    }

    private var sidebarToggleVerticalOffset: CGFloat {
        isSidebarVisible || isFullScreen ? 0 : -40
    }
}
