import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SidebarShortcutAction: Equatable {
    case showAndFocusSidebar
    case hideAndFocusEditor
}

enum SidebarShortcutRouting {
    static func action(isSidebarVisible: Bool) -> SidebarShortcutAction {
        isSidebarVisible ? .hideAndFocusEditor : .showAndFocusSidebar
    }
}

/// 工作区协调器：连接单文档编辑器、侧栏与菜单快捷键。
@MainActor
final class WorkspaceCoordinator: ObservableObject {
    @Published var wordCount = 0
    @Published var isRetyping = false
    weak var textView: DayDreamTextView? {
        didSet {
            textView?.wordCountDidChange = { [weak self] in self?.wordCount = $0 }
            textView?.retypeStateDidChange = { [weak self] in self?.isRetyping = $0 }
            textView?.setUltraFocus(center.ultraFocusEnabled)
        }
    }

    private var store: WorkspaceStore?
    private var document: DocumentController?
    private var center: ShortcutCenter { ShortcutCenter.shared }

    func configure(store: WorkspaceStore, document: DocumentController) {
        self.store = store
        self.document = document
        registerShortcuts()
    }

    func flushDocument() {
        textView?.flushPendingMarkdownChange()
        document?.flush()
    }

    func focusEditor() {
        DispatchQueue.main.async { [center, weak self] in
            guard let textView = self?.textView else { return }
            center.mainWindow?.makeFirstResponder(textView)
        }
    }

    private func registerShortcuts() {
        guard let store, let document else { return }
        let center = center

        store.beforeMutation = { [weak self] in
            self?.flushDocument()
        }

        center.newNote = { [weak self, store, document] in
            do {
                self?.flushDocument()
                let parent = store.parentForNewNode()
                let url = try store.createNote(in: parent)
                store.select(url)
                document.open(url)
                NotificationCenter.default.post(name: .dayDreamBeginRename, object: url)
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }

        center.toggleSidebar = { [store, weak self] in
            guard !center.ultraFocusEnabled, let self, let action = sidebarToggleHandler?() else { return }
            switch action {
            case .showAndFocusSidebar:
                center.isSidebarFocused = true
                center.sidebarNavigationURL = store.selectedURL ?? store.nodes.first?.url
                center.mainWindow?.makeFirstResponder(nil)
            case .hideAndFocusEditor:
                center.isSidebarFocused = false
                center.sidebarNavigationURL = nil
                focusEditor()
            }
        }

        center.refocusEditor = { [weak self] in
            self?.focusEditor()
        }

        center.writingCommand = { [weak self] command in
            guard let self else { return }
            switch command {
            case .enterUltraFocus: center.ultraFocusEnabled = true; self.focusEditor()
            case .exitUltraFocus: center.ultraFocusEnabled = false; self.focusEditor()
            case .writingBarOne, .writingBarTwo:
                guard let textView = self.textView, center.mainWindow?.firstResponder === textView else { return }
                textView.cycleWritingBar(command == .writingBarOne ? 0 : 1)
            case .resetWritingStyle: self.textView?.resetWritingStyle()
            case .retype: self.textView?.toggleRetype()
            default: break
            }
        }

        center.toggleBold = { [weak self] in self?.performInlineStyle { $0.toggleBold() } }
        center.toggleItalic = { [weak self] in self?.performInlineStyle { $0.toggleItalic() } }
        center.toggleHighlight = { [weak self] in self?.performInlineStyle { $0.toggleHighlight() } }
        center.toggleTextColor = { [weak self] in self?.performInlineStyle { $0.toggleTextColor() } }
        center.toggleInlineCode = { [weak self] in self?.performInlineStyle { $0.toggleInlineCode() } }
    }

    private func performInlineStyle(_ action: (DayDreamTextView) -> Void) {
        guard let textView, textView.retypeSession == nil, center.mainWindow?.firstResponder === textView else { return }
        action(textView)
    }

    /// ⌘O 切换侧栏——由 View 注入（@State 归 View 管）。
    var sidebarToggleHandler: (() -> SidebarShortcutAction)?
}

@MainActor
struct WorkspaceView: View {
    @StateObject private var store: WorkspaceStore
    @StateObject private var document = DocumentController()
    @StateObject private var coordinator = WorkspaceCoordinator()
    @ObservedObject private var shortcutCenter = ShortcutCenter.shared
    @ObservedObject private var settings = EditorSettings.shared

    @State private var isSidebarVisible = true
    @State private var isFullScreen = false
    @State private var isExportMenuPresented = false
    @State private var isMoreMenuPresented = false

    init() {
        _store = StateObject(wrappedValue: WorkspaceStore(repositoryDefaults: .standard))
    }

    init(store: WorkspaceStore) {
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if isSidebarVisible && !shortcutCenter.ultraFocusEnabled {
                    SidebarView(
                        store: store,
                        isFullScreen: isFullScreen,
                        onOpenNote: {
                            coordinator.flushDocument()
                            document.open($0)
                        },
                        onStructureChange: { document.applyStructureChange($0) }
                    )
                    .frame(width: 250)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                editorContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .topTrailing) {
                if !shortcutCenter.ultraFocusEnabled {
                editorToolbar(for: document.currentURL)
                    .padding(.top, isFullScreen ? 11 : 8)
                    .padding(.trailing, 12)
                    .offset(y: isFullScreen ? 0 : -40)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if settings.wordCountEnabled && !shortcutCenter.ultraFocusEnabled && document.currentURL != nil {
                    Text("\(coordinator.wordCount) words")
                        .font(Font(NSFont(descriptor: settings.editorFont.fontDescriptor, size: 12) ?? settings.editorFont))
                        .foregroundStyle(.secondary.opacity(0.65))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }

            if !shortcutCenter.ultraFocusEnabled {
            sidebarToggle
                .padding(.leading, sidebarToggleLeadingInset)
                .padding(.top, sidebarToggleTopInset)
                .offset(y: sidebarToggleVerticalOffset)
                .zIndex(10)
            }

        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Color(nsColor: DayDreamTheme.background(for: NSApp.effectiveAppearance)))
        .animation(.easeOut(duration: 0.16), value: isSidebarVisible)
        .animation(.easeOut(duration: 0.18), value: isFullScreen)
        .onAppear {
            coordinator.sidebarToggleHandler = {
                let action = SidebarShortcutRouting.action(isSidebarVisible: isSidebarVisible)
                withAnimation {
                    isSidebarVisible = action == .showAndFocusSidebar
                }
                return action
            }
            coordinator.configure(store: store, document: document)
        }
        .onChange(of: shortcutCenter.ultraFocusEnabled) { _, enabled in
            if enabled {
                isSidebarVisible = false
                isExportMenuPresented = false; isMoreMenuPresented = false
                shortcutCenter.isSidebarFocused = false
                shortcutCenter.sidebarNavigationURL = nil
            }
            coordinator.textView?.setUltraFocus(enabled)
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                shortcutCenter.mainWindow?.standardWindowButton(button)?.isHidden = enabled
            }
            coordinator.focusEditor()
        }
        .onChange(of: store.rootURL) { _, _ in
            // 切换库之前 beforeMutation 已保存；新库不沿用旧库文档。
            document.clear(saving: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            coordinator.flushDocument()
        }
        .onDisappear {
            coordinator.flushDocument()
        }
        .alert(
            L10n.t("文件已在其他应用中修改", "File changed in another app"),
            isPresented: Binding(
                get: { document.externalEditConflict != nil },
                set: { _ in }
            )
        ) {
            Button(L10n.t("载入磁盘版本", "Load Disk Version")) {
                document.reloadFromDisk()
            }
            Button(L10n.t("保留我的版本", "Keep My Version")) {
                document.overwriteExternalChanges()
            }
        } message: {
            Text(L10n.t(
                "为了避免覆盖内容，DayDream 已暂停保存。请选择要保留的版本。",
                "Saving was paused to prevent data loss. Choose which version to keep."
            ))
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        if let url = document.currentURL {
            EditorView(
                markdown: document.markdown,
                documentURL: url,
                reloadRevision: document.reloadRevision,
                autofocus: false,
                onMarkdownChange: { document.updateMarkdown($0) },
                onBecameFirstResponder: {
                    shortcutCenter.isSidebarFocused = false
                    shortcutCenter.sidebarNavigationURL = nil
                },
                registerTextView: { coordinator.textView = $0 }
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

    private func editorToolbar(for url: URL?) -> some View {
        HStack(spacing: 4) {
            Button {
                isMoreMenuPresented = false
                isExportMenuPresented.toggle()
            } label: {
                toolbarIcon(.exportDocument)
            }
            .buttonStyle(.plain)
            .help(L10n.t("导出", "Export"))
            .accessibilityLabel(L10n.t("导出", "Export"))
            .popover(isPresented: $isExportMenuPresented, arrowEdge: .top) {
                exportMenu(for: url)
            }

            Button {
                isExportMenuPresented = false
                isMoreMenuPresented.toggle()
            } label: {
                toolbarIcon(.more)
            }
            .buttonStyle(.plain)
            .help(L10n.t("更多", "More"))
            .accessibilityLabel(L10n.t("更多", "More"))
            .popover(isPresented: $isMoreMenuPresented, arrowEdge: .top) {
                moreMenu
            }
        }
    }

    private func exportMenu(for url: URL?) -> some View {
        VStack(spacing: 2) {
            toolbarMenuButton(L10n.t("导出 Markdown…", "Export Markdown…")) {
                guard let url else { return }
                isExportMenuPresented = false
                DispatchQueue.main.async { exportDocument(url: url, format: .markdown) }
            }
            .disabled(url == nil)

            toolbarMenuButton(L10n.t("导出 Word…", "Export Word…")) {
                guard let url else { return }
                isExportMenuPresented = false
                DispatchQueue.main.async { exportDocument(url: url, format: .word) }
            }
            .disabled(url == nil)
        }
        .padding(6)
        .frame(width: 196)
    }

    private var moreMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolbarMenuButton(coordinator.isRetyping ? L10n.t("退出重打练习", "Exit Retype") : L10n.t("重打练习", "Retype")) {
                isMoreMenuPresented = false
                coordinator.textView?.toggleRetype()
            }.disabled(document.currentURL == nil)
            Text(shortcutCenter.ultraFocusEnabled ? "" : ShortcutPreferences.shared.shortcut(for: .retype).displayName)
                .font(.system(size: 10)).foregroundStyle(.secondary).padding(.leading, 9)
            Divider()
            toolbarMenuButton(L10n.t("插入图片 / 视频文件…", "Insert Image / Video File…")) {
                isMoreMenuPresented = false
                DispatchQueue.main.async { coordinator.textView?.chooseMediaFiles() }
            }.disabled(document.currentURL == nil || coordinator.isRetyping)
            toolbarMenuButton(L10n.t("插入链接…", "Insert Link…")) {
                isMoreMenuPresented = false
                DispatchQueue.main.async { coordinator.textView?.chooseMediaLink() }
            }.disabled(document.currentURL == nil || coordinator.isRetyping)
            Divider()
            Toggle(L10n.t("专注模式", "Focus Mode"), isOn: $settings.focusModeEnabled)
            Divider()
            colorMenu(
                title: L10n.t("荧光笔颜色", "Highlight Color"),
                selection: $settings.highlightPreset
            )
            Divider()
            Toggle(
                L10n.t("单词自动补全", "Word Completion"),
                isOn: $settings.wordCompletionEnabled
            )
            Toggle(
                L10n.t("自动修正拼写", "Correct Spelling Automatically"),
                isOn: $settings.automaticSpellingCorrectionEnabled
            )
        }
        .font(.system(size: 13))
        .padding(12)
        .frame(width: 250, alignment: .leading)
    }

    private func toolbarMenuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toolbarIcon(_ name: DayDreamIconName) -> some View {
        DayDreamIcon(
            name: name,
            color: Color(nsColor: .labelColor).opacity(0.78),
            strokeWidth: name == .more ? 2.4 : 1.75
        )
            .frame(width: 16, height: 16)
            .frame(width: 32, height: 32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
    }

    private func colorMenu(title: String, selection: Binding<String>) -> some View {
        Menu(title) {
            ForEach(StyleColorPreset.allCases, id: \.self) { preset in
                Button {
                    selection.wrappedValue = preset.rawValue
                } label: {
                    HStack {
                        Text(colorName(preset))
                        if selection.wrappedValue == preset.rawValue { Image(systemName: "checkmark") }
                    }
                }
            }
        }
    }

    private func colorName(_ preset: StyleColorPreset) -> String {
        switch preset {
        case .caret: return L10n.t("主题色", "Theme")
        case .yellow: return L10n.t("黄色", "Yellow")
        case .green: return L10n.t("绿色", "Green")
        case .blue: return L10n.t("蓝色", "Blue")
        case .pink: return L10n.t("粉色", "Pink")
        }
    }

    private enum ExportFormat {
        case markdown
        case word
    }

    private func exportDocument(url: URL, format: ExportFormat) {
        coordinator.flushDocument()
        let panel = NSSavePanel()
        let fileExtension = format == .markdown ? "md" : "docx"
        panel.allowedContentTypes = [UTType(filenameExtension: fileExtension)!]
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + "." + fileExtension
        panel.canCreateDirectories = true
        panel.prompt = L10n.t("导出", "Export")
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            let service = DocumentTransferService()
            switch format {
            case .markdown:
                try service.exportMarkdown(document.markdown, to: destination, sourceURL: url)
            case .word:
                try service.exportWord(document.markdown, to: destination, sourceURL: url)
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private var sidebarToggle: some View {
        Button {
            withAnimation { isSidebarVisible.toggle() }
            if !isSidebarVisible {
                shortcutCenter.isSidebarFocused = false
                shortcutCenter.sidebarNavigationURL = nil
                coordinator.focusEditor()
            }
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
