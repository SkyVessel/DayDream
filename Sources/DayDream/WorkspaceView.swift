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
    weak var pdfView: ReaderPDFView? { didSet { if let pdfView { center.documentResponder = pdfView } } }
    weak var textView: DayDreamTextView? {
        didSet {
            if let textView { center.documentResponder = textView }
            textView?.wordCountDidChange = { [weak self] in self?.wordCount = $0 }
            textView?.retypeStateDidChange = { [weak self] in self?.isRetyping = $0 }
            textView?.setUltraFocus(center.ultraFocusEnabled)
            configureNoteLinks()
        }
    }

    private var isRenamingPage = false
    private var linkSearch: LibrarySearchController?
    private var store: WorkspaceStore?
    private var document: DocumentController?
    let center: ShortcutCenter
    init(center: ShortcutCenter? = nil) { self.center = center ?? .shared }

    func configure(store: WorkspaceStore, document: DocumentController) {
        self.store = store
        self.document = document
        document.didSave = { [weak self] url, markdown in self?.synchronizePageTitle(url, markdown: markdown) }
        registerShortcuts()
        configureNoteLinks()
    }

    func openDocument(_ url: URL) {
        guard flushDocument() else { return }
        document?.open(url)
        focusEditor()
    }

    private func configureNoteLinks() {
        textView?.linkExistingPage = { [weak self] range in
            guard let self, let store = self.store, let document = self.document,
                  let editor = self.textView, let window = self.center.mainWindow, self.flushDocument() else { return }
            let sourceURL = document.currentURL
            let sourceText = editor.string
            self.linkSearch = LibrarySearchController(root: store.rootURL, owner: window, linking: true) { [weak self, weak editor] url, _ in
                guard let self, let editor else { return }
                guard document.currentURL == sourceURL, editor.string == sourceText else {
                    store.errorMessage = L10n.t("笔记已变化，请重新选择链接位置。", "The note changed. Choose the link position again.")
                    return
                }
                _ = editor.insertNoteLink(target: NoteLinks.name(for: url, root: store.rootURL), label: url.deletingPathExtension().lastPathComponent, replacing: range)
                self.focusEditor()
            }
        }

        textView?.openNoteLink = { [weak self] target in
            guard let self, let store = self.store else { return }
            guard let url = NoteLinks.resolve(target, from: self.document?.currentURL, root: store.rootURL) else {
                store.errorMessage = L10n.t("找不到链接的笔记：", "Linked note not found: ") + target
                return
            }
            self.openDocument(url)
        }
        textView?.createLinkedPage = { [weak self] range in
            guard let self, let store = self.store, let document = self.document,
                  let editor = self.textView, self.flushDocument() else { return }
            do {
                let url = try store.createNote(in: document.currentURL?.deletingLastPathComponent())
                try ("# " + url.deletingPathExtension().lastPathComponent + "\n\n").write(to: url, atomically: true, encoding: .utf8)
                PageTitles.register(url)
                guard editor.insertNoteLink(target: NoteLinks.name(for: url, root: store.rootURL), label: url.deletingPathExtension().lastPathComponent, replacing: range), self.flushDocument() else { return }
                editor.selectPageTitleOnNextLoad = true
                document.open(url)
                self.focusEditor()
            } catch { store.errorMessage = error.localizedDescription }
        }
    }

    private func synchronizePageTitle(_ url: URL, markdown: String) {
        guard !isRenamingPage, PageTitles.contains(url), let store, let document,
              let title = PageTitles.title(in: markdown), title != url.deletingPathExtension().lastPathComponent else { return }
        isRenamingPage = true
        defer { isRenamingPage = false }
        do {
            let preparation = PageRenamePreparation()
            NotificationCenter.default.post(name: .dayDreamWillRenamePage, object: preparation)
            guard preparation.canProceed, document.currentURL == url,
                  let title = PageTitles.title(in: document.markdown), title != url.deletingPathExtension().lastPathComponent else { return }
            let destination = url.deletingLastPathComponent().appendingPathComponent(title).appendingPathExtension(url.pathExtension)
            let files = NoteLinks.files(in: store.rootURL)
            var updates: [(url: URL, before: Data, after: Data)] = []
            for source in files where source.pathExtension.lowercased() != "pdf" {
                let before = try Data(contentsOf: source)
                guard let text = String(data: before, encoding: .utf8) else { continue }
                let rewritten = PageTitles.replacingLinks(in: text, source: source, from: url, to: destination, root: store.rootURL, files: files)
                if rewritten != text { updates.append((source, before, Data(rewritten.utf8))) }
            }
            let renamed = try store.rename(url, to: title)
            var written: [(url: URL, before: Data, after: Data)] = []
            do {
                for update in updates {
                    let target = update.url == url ? renamed : update.url
                    guard try Data(contentsOf: target) == update.before else { throw CocoaError(.fileWriteFileExists) }
                    try update.after.write(to: target, options: .atomic)
                    written.append((target, update.before, update.after))
                }
            } catch {
                for update in written.reversed() where (try? Data(contentsOf: update.url)) == update.after {
                    try? update.before.write(to: update.url, options: .atomic)
                }
                try? FileManager.default.moveItem(at: renamed, to: url)
                try? store.reload()
                throw error
            }
            PageTitles.moved(from: url, to: renamed)
            let change = WorkspaceStructureChange.moved(from: url, to: renamed)
            document.applyStructureChange(change)
            NotificationCenter.default.post(name: .dayDreamStructureChanged, object: change)
            for update in written {
                NotificationCenter.default.post(name: .dayDreamNoteContentsChanged, object: update.url)
            }
        } catch { store.errorMessage = error.localizedDescription }
    }

    @discardableResult
    func flushDocument() -> Bool {
        textView?.flushPendingMarkdownChange()
        guard let document, document.currentURL != nil else { return true }
        return document.flush()
    }

    func focusEditor() {
        PaneShortcutRouting.activate(center)
        DispatchQueue.main.async { [center, weak self] in
            guard let self else { return }
            let responder: NSView? = self.document?.isPDF == true ? self.pdfView : self.textView
            if let responder { center.mainWindow?.makeFirstResponder(responder) }
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
                NotificationCenter.default.post(name: .dayDreamBeginRename, object: url, userInfo: ["center": center])
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

        center.historyBack = { [weak self, document] in self?.flushDocument(); document.navigateHistory(by: -1) }
        center.historyForward = { [weak self, document] in self?.flushDocument(); document.navigateHistory(by: 1) }

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
            case .resetWritingStyle: self.textView?.resetSelectedAndTypingStyle()
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
    @StateObject private var coordinator: WorkspaceCoordinator
    @StateObject private var shortcutCenter: ShortcutCenter
    var initialURL: URL? = nil
    var isEmbedded = false
    var showsChrome = true
    var sharedUltraFocus = false
    var onUltraFocusChanged: ((Bool) -> Void)?
    var onOpenReference: ((URL) -> Void)?
    var onClosePane: (() -> Void)?
    var focusPane: ((Bool) -> Void)?
    var registerCoordinator: ((WorkspaceCoordinator) -> Void)?
    @ObservedObject private var settings = EditorSettings.shared

    @State private var isSidebarVisible = true
    @State private var isFullScreen = false
    @State private var isExportMenuPresented = false
    @State private var isMoreMenuPresented = false
    @State private var backlinks: [URL] = []

    init(store: WorkspaceStore? = nil, initialURL: URL? = nil,
         isEmbedded: Bool = false, showsChrome: Bool = true, sharedUltraFocus: Bool = false,
         onUltraFocusChanged: ((Bool) -> Void)? = nil, onOpenReference: ((URL) -> Void)? = nil,
         onClosePane: (() -> Void)? = nil, focusPane: ((Bool) -> Void)? = nil,
         registerCoordinator: ((WorkspaceCoordinator) -> Void)? = nil) {
        let center = ShortcutCenter()
        _store = StateObject(wrappedValue: store ?? WorkspaceStore(repositoryDefaults: .standard))
        _shortcutCenter = StateObject(wrappedValue: center)
        _coordinator = StateObject(wrappedValue: WorkspaceCoordinator(center: center))
        self.initialURL = initialURL; self.isEmbedded = isEmbedded
        self.showsChrome = showsChrome; self.sharedUltraFocus = sharedUltraFocus
        self.onUltraFocusChanged = onUltraFocusChanged
        self.onOpenReference = onOpenReference; self.onClosePane = onClosePane
        self.focusPane = focusPane; self.registerCoordinator = registerCoordinator
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if showsChrome && isSidebarVisible && !shortcutCenter.ultraFocusEnabled {
                    SidebarView(
                        store: store,
                        shortcutCenter: shortcutCenter,
                        onOpenReference: onOpenReference,
                        isFullScreen: isFullScreen,
                        onOpenNote: {
                            coordinator.flushDocument()
                            document.open($0)
                        },
                        onStructureChange: { change in
                            NotificationCenter.default.post(name: .dayDreamStructureChanged, object: change)
                        }
                    )
                    .frame(width: isEmbedded ? 180 : 250)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                editorContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .topTrailing) {
                if showsChrome && !shortcutCenter.ultraFocusEnabled {
                editorToolbar(for: document.currentURL)
                    .padding(.top, isFullScreen ? 11 : 8)
                    .padding(.trailing, 12)
                    .offset(y: isFullScreen || isEmbedded ? 0 : -40)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showsChrome && !document.isPDF && settings.wordCountEnabled && !shortcutCenter.ultraFocusEnabled && document.currentURL != nil {
                    Text("\(coordinator.wordCount) words")
                        .font(Font(NSFont(descriptor: settings.editorFont.fontDescriptor, size: 12) ?? settings.editorFont))
                        .foregroundStyle(.secondary.opacity(0.65))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }

            if showsChrome && !shortcutCenter.ultraFocusEnabled {
            HStack(spacing: 2) {
                Button { shortcutCenter.searchFiles() } label: { Image(systemName: "magnifyingglass").frame(width: 24, height: 28) }
                    .help(L10n.t("搜索笔记", "Search notes"))
                Button { coordinator.flushDocument(); document.navigateHistory(by: -1) } label: { Image(systemName: "chevron.left").frame(width: 24, height: 28) }
                    .disabled(!document.history.canGoBack).help(L10n.t("上篇笔记", "Previous note"))
                Button { coordinator.flushDocument(); document.navigateHistory(by: 1) } label: { Image(systemName: "chevron.right").frame(width: 24, height: 28) }
                    .disabled(!document.history.canGoForward).help(L10n.t("下篇笔记", "Next note"))
            }.buttonStyle(.plain)
                .padding(.leading, isSidebarVisible ? (isEmbedded ? 192 : 262) : (isEmbedded ? 46 : 110))
                .padding(.top, 8)
                .offset(y: isFullScreen || isEmbedded ? 0 : -40)
            sidebarToggle
                .padding(.leading, sidebarToggleLeadingInset)
                .padding(.top, sidebarToggleTopInset)
                .offset(y: sidebarToggleVerticalOffset)
                .zIndex(10)
            }

        }
        .frame(minWidth: isEmbedded ? 320 : 560, minHeight: 420)
        .background(PaneShortcutBridge(center: shortcutCenter))
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
            shortcutCenter.ultraFocusEnabled = sharedUltraFocus
            coordinator.configure(store: store, document: document)
            registerCoordinator?(coordinator)
            if document.currentURL == nil, let initialURL { document.open(initialURL) }
            shortcutCenter.closeNote = {
                guard coordinator.flushDocument() else { return }
                document.clear()
                if document.currentURL == nil { onClosePane?() }
            }
            shortcutCenter.focusLeftPane = { focusPane?(false) }
            shortcutCenter.focusRightPane = { focusPane?(true) }
        }
        .onChange(of: sharedUltraFocus) { _, enabled in
            shortcutCenter.ultraFocusEnabled = enabled
        }
        .onChange(of: shortcutCenter.ultraFocusEnabled) { _, enabled in
            onUltraFocusChanged?(enabled)
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
            if PaneShortcutRouting.current(in: shortcutCenter.mainWindow) === shortcutCenter { coordinator.focusEditor() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dayDreamWillRenamePage)) { notification in
            if let preparation = notification.object as? PageRenamePreparation, !coordinator.flushDocument() { preparation.canProceed = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dayDreamNoteContentsChanged)) { notification in
            if let url = notification.object as? URL, url == document.currentURL { document.reloadFromDisk() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dayDreamLibraryContentsChanged)) { notification in
            if let root = notification.object as? URL, root == store.rootURL { try? store.reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dayDreamStructureChanged)) { notification in
            guard let change = notification.object as? WorkspaceStructureChange else { return }
            if case let .moved(from, to) = change { PageTitles.moved(from: from, to: to) }
            document.applyStructureChange(change)
            try? store.reload()
        }
        .onChange(of: document.currentURL) { _, url in
            store.select(url)
            shortcutCenter.sidebarNavigationURL = url
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
        .alert(L10n.t("DayDream 无法完成该操作", "DayDream couldn’t complete that action"), isPresented: Binding(
            get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button(L10n.t("好", "OK")) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
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
            if document.isPDF {
                PDFDocumentView(url: url, register: { coordinator.pdfView = $0 })
                    .id(document.reloadRevision)
                    .onAppear { coordinator.textView = nil }
            } else {
            EditorView(
                markdown: document.markdown,
                documentURL: url,
                reloadRevision: document.reloadRevision,
                autofocus: false,
                onMarkdownChange: { document.updateMarkdown($0) },
                onBecameFirstResponder: {
                    PaneShortcutRouting.activate(shortcutCenter)
                    shortcutCenter.isSidebarFocused = false
                    shortcutCenter.sidebarNavigationURL = nil
                },
                registerTextView: { coordinator.textView = $0 }
            )
            }
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
                if isMoreMenuPresented, let url = document.currentURL {
                    coordinator.flushDocument()
                    let root = store.rootURL
                    DispatchQueue.global(qos: .userInitiated).async {
                        let links = NoteLinks.backlinks(to: url, root: root)
                        DispatchQueue.main.async { if document.currentURL == url { backlinks = links } }
                    }
                }
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
            .disabled(url == nil || document.isPDF)

            toolbarMenuButton(L10n.t("导出 Word…", "Export Word…")) {
                guard let url else { return }
                isExportMenuPresented = false
                DispatchQueue.main.async { exportDocument(url: url, format: .word) }
            }
            .disabled(url == nil || document.isPDF)
            toolbarMenuButton(L10n.t("导出 PDF…", "Export PDF…")) {
                guard let url else { return }
                isExportMenuPresented = false
                DispatchQueue.main.async { exportDocument(url: url, format: .pdf) }
            }.disabled(url == nil)
        }
        .padding(6)
        .frame(width: 196)
    }

    private var moreMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu(L10n.t("反向链接", "Backlinks") + " (\(backlinks.count))") {
                if backlinks.isEmpty { Text(L10n.t("暂无关联笔记", "No linked mentions")) }
                ForEach(backlinks, id: \.self) { url in
                    Button(NoteLinks.name(for: url, root: store.rootURL)) {
                        isMoreMenuPresented = false; coordinator.openDocument(url)
                    }
                }
            }.disabled(document.currentURL == nil)
            Divider()
            toolbarMenuButton(coordinator.isRetyping ? L10n.t("退出重打练习", "Exit Retype") : L10n.t("重打练习", "Retype")) {
                isMoreMenuPresented = false
                coordinator.textView?.toggleRetype()
            }.disabled(document.currentURL == nil || document.isPDF)
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
        case pdf
    }

    private func exportDocument(url: URL, format: ExportFormat) {
        coordinator.flushDocument()
        let panel = NSSavePanel()
        let fileExtension = format == .markdown ? "md" : format == .pdf ? "pdf" : "docx"
        panel.allowedContentTypes = [UTType(filenameExtension: fileExtension)!]
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + "." + fileExtension
        panel.canCreateDirectories = true
        panel.prompt = L10n.t("导出", "Export")
        let appearancePicker = DocumentAppearancePicker(selection: DocumentAppearance.stored(for: url) ?? .current)
        panel.accessoryView = appearancePicker
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            let service = DocumentTransferService()
            switch format {
            case .markdown:
                try service.exportMarkdown(document.markdown, to: destination, sourceURL: url)
                appearancePicker.selection.store(for: destination)
            case .pdf:
                if document.isPDF { try service.exportPDFDocument(url, to: destination, mode: appearancePicker.selection) }
                else { try service.exportPDF(document.markdown, to: destination, sourceURL: url, mode: appearancePicker.selection) }
            case .word:
                try service.exportWord(document.markdown, to: destination, sourceURL: url, mode: appearancePicker.selection)
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
        if isEmbedded { return isSidebarVisible ? 138 : 8 }
        if isSidebarVisible { return 175 }
        return isFullScreen ? 8 : 76
    }

    private var sidebarToggleTopInset: CGFloat {
        if isEmbedded { return 8 }
        if isSidebarVisible { return isFullScreen ? 28.5 : 8 }
        return isFullScreen ? 9 : 8
    }

    private var sidebarToggleVerticalOffset: CGFloat {
        if isEmbedded { return 0 }
        return isSidebarVisible || isFullScreen ? 0 : -40
    }
}
