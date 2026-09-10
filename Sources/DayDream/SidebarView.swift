import SwiftUI
import UniformTypeIdentifiers

struct SidebarRow: Equatable {
    let node: WorkspaceNode
    let depth: Int
}

enum SidebarTreeProjection {
    static func rows(
        from nodes: [WorkspaceNode],
        expandedFolders: Set<URL>
    ) -> [SidebarRow] {
        var result: [SidebarRow] = []
        func append(_ nodes: [WorkspaceNode], depth: Int) {
            for node in nodes {
                result.append(SidebarRow(node: node, depth: depth))
                if node.kind == .folder, expandedFolders.contains(node.url) {
                    append(node.children, depth: depth + 1)
                }
            }
        }
        append(nodes, depth: 0)
        return result
    }
}

struct SidebarView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject private var settings = EditorSettings.shared
    @ObservedObject var shortcutCenter = ShortcutCenter.shared
    var onOpenReference: ((URL) -> Void)?
    let isFullScreen: Bool
    /// 打开笔记（由 WorkspaceView 注入，进入当前焦点窗格）。
    var onOpenNote: ((URL) -> Void)?
    /// 结构变更（重命名/移动/删除）同步给窗格。
    var onStructureChange: ((WorkspaceStructureChange) -> Void)?
    @State private var expandedFolders: Set<URL> = []
    @State private var editingURL: URL?
    @State private var draftName = ""
    @State private var isAddMenuPresented = false
    @State private var hoveredURL: URL?
    /// 哪一行文件夹的「+」弹窗处于打开状态。
    @State private var folderAddMenuURL: URL?
    @State private var pendingDeletion: WorkspaceNode?
    /// 拖拽悬停高亮的目标行。
    @State private var dropTargetURL: URL?
    @FocusState private var focusedEditingURL: URL?

    private var rows: [SidebarRow] {
        SidebarTreeProjection.rows(
            from: store.nodes,
            expandedFolders: expandedFolders
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(rows, id: \.node.id) { row in
                            nodeRow(row)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.bottom, 14)
                }
                .dropDestination(for: URL.self) { items, _ in
                    performDrops(items, onto: nil)
                }
                .onChange(of: shortcutCenter.sidebarNavigationURL) { _, url in
                    if let url {
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(url, anchor: .center)
                        }
                        if shortcutCenter.isSidebarFocused,
                           let row = rows.first(where: { $0.node.url == url }),
                           row.node.kind == .note {
                            store.select(url)
                            onOpenNote?(url)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(width: 0.5)
        }
        .background {
            // 侧栏键盘导航（⌘O 进入）：↑/↓ 移动，Enter 选取，Esc 退出。
            if shortcutCenter.isSidebarFocused {
                Group {
                    Button("") { moveSidebarNavigation(by: -1) }
                        .keyboardShortcut(.upArrow, modifiers: [])
                    Button("") { moveSidebarNavigation(by: 1) }
                        .keyboardShortcut(.downArrow, modifiers: [])
                    Button("") { confirmSidebarNavigation() }
                        .keyboardShortcut(.return, modifiers: [])
                    Button("") { exitSidebarNavigation() }
                        .keyboardShortcut(.escape, modifiers: [])
                }
                .frame(width: 0, height: 0)
                .opacity(0)
            }
        }
        .onAppear { registerShortcutActions() }
        .onReceive(NotificationCenter.default.publisher(for: .dayDreamBeginRename)) { note in
            if let target = note.userInfo?["center"] as? ShortcutCenter, target !== shortcutCenter { return }
            if let url = note.object as? URL {
                beginRename(url, currentName: url.deletingPathExtension().lastPathComponent)
            }
        }
        .alert(
            L10n.t("删除这篇笔记？", "Delete this note?"),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            )
        ) {
            Button(L10n.t("取消", "Cancel"), role: .cancel) {
                pendingDeletion = nil
            }
            .keyboardShortcut(.cancelAction)
            Button(L10n.t("删除", "Delete"), role: .destructive) {
                guard let node = pendingDeletion else { return }
                pendingDeletion = nil
                deleteNode(node)
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text(L10n.t(
                "“\(pendingDeletion?.name ?? "")”将被移到废纸篓。",
                "“\(pendingDeletion?.name ?? "")” will be moved to the Trash."
            ))
        }
    }

    private var header: some View {
        HStack(spacing: 3) {
            Button(action: chooseRepository) {
                Text(L10n.t("笔记库", "Library"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t("选择笔记库", "Choose a repository") + "\n\(store.rootURL.path)")
            .accessibilityLabel(L10n.t("选择笔记库", "Choose Library"))

            if store.repositoryURLs.count > 1 {
                repositoryArrow(
                    .chevronLeft,
                    enabled: store.canSelectPreviousRepository,
                    help: "Previous repository",
                    action: store.selectPreviousRepository
                )
                repositoryArrow(
                    .chevronRight,
                    enabled: store.canSelectNextRepository,
                    help: "Next repository",
                    action: store.selectNextRepository
                )
            }

            Spacer(minLength: 0)

            Button(action: importDocument) {
                DayDreamIcon(name: .importDocument, color: .secondary, strokeWidth: 1.65)
                    .frame(width: 16, height: 16)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t("导入 Markdown 或 Word", "Import Markdown or Word"))
            .accessibilityLabel(L10n.t("导入", "Import"))

            Color.clear
                .frame(width: 30, height: 30)

            Button {
                isAddMenuPresented.toggle()
            } label: {
                DayDreamIcon(name: .plus, color: .secondary)
                    .frame(width: 17, height: 17)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t("新建笔记或文件夹", "Add a note or folder"))
            .accessibilityLabel("Add")
            .popover(isPresented: $isAddMenuPresented, arrowEdge: .top) {
                addMenu
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, isFullScreen ? 29 : 6)
        .padding(.bottom, 8)
        .frame(height: isFullScreen ? 68 : 48)
    }

    private var addMenu: some View {
        VStack(spacing: 2) {
            addMenuButton(title: L10n.t("新建笔记", "New Note"), icon: .fileText, action: createNote)
            addMenuButton(title: L10n.t("新建文件夹", "New Folder"), icon: .folder, action: createFolder)
        }
        .padding(6)
        .frame(width: 176)
    }

    private func addMenuButton(
        title: String,
        icon: DayDreamIconName,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                DayDreamIcon(name: icon, color: .secondary, strokeWidth: 1.65)
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func repositoryArrow(
        _ icon: DayDreamIconName,
        enabled: Bool,
        help: String,
        action: @escaping () throws -> Void
    ) -> some View {
        Button {
            do {
                try action()
                resetTransientState()
            } catch {
                store.errorMessage = error.localizedDescription
            }
        } label: {
            DayDreamIcon(name: icon, color: .secondary, strokeWidth: 1.8)
                .frame(width: 12, height: 12)
                .frame(width: 22, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    @ViewBuilder
    private func nodeRow(_ row: SidebarRow) -> some View {
        HStack(spacing: 7) {
            if row.node.kind == .folder {
                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        if expandedFolders.contains(row.node.url) {
                            expandedFolders.remove(row.node.url)
                        } else {
                            expandedFolders.insert(row.node.url)
                        }
                    }
                } label: {
                    DayDreamIcon(name: .chevronRight, color: .secondary, strokeWidth: 1.8)
                        .frame(width: 12, height: 12)
                        .rotationEffect(.degrees(expandedFolders.contains(row.node.url) ? 90 : 0))
                        .frame(width: 28, height: 31)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, -6)
                .accessibilityLabel(expandedFolders.contains(row.node.url)
                    ? L10n.t("收起文件夹", "Collapse folder")
                    : L10n.t("展开文件夹", "Expand folder"))
            } else {
                Color.clear.frame(width: 16, height: 20)
            }

            if editingURL == row.node.url {
                rowIcon(row.node)
                TextField(L10n.t("名称", "Name"), text: $draftName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5))
                        .focused($focusedEditingURL, equals: row.node.url)
                        .onSubmit { commitRename(row.node) }
                        .onExitCommand { cancelRename() }
                Spacer(minLength: 0)
            } else {
                Button {
                    selectNode(row.node)
                } label: {
                    HStack(spacing: 7) {
                        rowIcon(row.node)
                        Text(row.node.name)
                            .font(.system(size: 13.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if row.node.url.pathExtension.lowercased() == "pdf" {
                            Text("PDF").font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.node.name)
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        selectNode(row.node)
                        beginRename(row.node.url, currentName: row.node.name)
                    }
                )

                // 文件夹行悬停时出现「+」：在内部新建笔记或文件夹（可无限嵌套）。
                // 弹窗打开期间保持显示，否则鼠标移向弹窗时按钮消失会把弹窗带走。
                if row.node.kind == .folder,
                   hoveredURL == row.node.url || folderAddMenuURL == row.node.url {
                    Button {
                        folderAddMenuURL = row.node.url
                    } label: {
                        DayDreamIcon(name: .plus, color: .secondary)
                            .frame(width: 13, height: 13)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("在其中新建笔记或文件夹", "Add a note or folder inside"))
                    .accessibilityLabel("Add inside \(row.node.name)")
                    .popover(
                        isPresented: folderAddMenuBinding(for: row.node.url),
                        arrowEdge: .trailing
                    ) {
                        folderAddMenu(for: row.node.url)
                    }
                }
            }
        }
        .padding(.leading, CGFloat(row.depth) * 17)
        .padding(.horizontal, 7)
        .frame(height: 31)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(rowBackgroundFill(for: row.node.url))
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredURL = hovering ? row.node.url : (hoveredURL == row.node.url ? nil : hoveredURL)
        }
        .contextMenu { rowContextMenu(for: row.node) }
        .draggableIf(editingURL != row.node.url, payload: row.node.url)
        .dropDestination(for: URL.self) { items, _ in
            performDrops(items, onto: row.node)
        } isTargeted: { targeted in
            if targeted {
                dropTargetURL = row.node.url
            } else if dropTargetURL == row.node.url {
                dropTargetURL = nil
            }
        }
    }

    private func rowIcon(_ node: WorkspaceNode) -> some View {
        DayDreamIcon(
            name: node.kind == .folder ? .folder : .fileText,
            color: .secondary,
            strokeWidth: 1.65
        )
        .frame(width: 16, height: 16)
    }

    private func selectNode(_ node: WorkspaceNode) {
        store.select(node.url)
        shortcutCenter.isSidebarFocused = true
        shortcutCenter.sidebarNavigationURL = node.url
        if node.kind == .note {
            onOpenNote?(node.url)
        }
    }

    private func createNote() {
        createNote(in: store.parentForNewNode())
    }

    private func createNote(in parent: URL?) {
        isAddMenuPresented = false
        folderAddMenuURL = nil
        do {
            let url = try store.createNote(in: parent)
            if let parent, parent.path != store.rootURL.path {
                expandedFolders.insert(parent)
            }
            store.select(url)
            onOpenNote?(url)
            beginRename(url, currentName: url.deletingPathExtension().lastPathComponent)
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func createFolder() {
        createFolder(in: store.parentForNewNode())
    }

    private func createFolder(in parent: URL?) {
        isAddMenuPresented = false
        folderAddMenuURL = nil
        do {
            let url = try store.createFolder(in: parent)
            if let parent, parent.path != store.rootURL.path {
                expandedFolders.insert(parent)
            }
            expandedFolders.insert(url)
            store.select(url)
            beginRename(url, currentName: url.lastPathComponent)
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func importDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!, .init(filenameExtension: "markdown")!, .init(filenameExtension: "docx")!, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = L10n.t("导入", "Import")
        let appearancePicker = DocumentAppearancePicker(selection: .current)
        panel.accessoryView = appearancePicker
        guard panel.runModal() == .OK, let source = panel.url else { return }

        do {
            let url = try store.importDocument(from: source)
            appearancePicker.selection.store(for: url)
            store.select(url)
            onOpenNote?(url)
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func beginRename(_ url: URL, currentName: String) {
        editingURL = url
        draftName = currentName
        DispatchQueue.main.async {
            focusedEditingURL = url
        }
    }

    private func commitRename(_ node: WorkspaceNode) {
        do {
            let wasExpanded = expandedFolders.remove(node.url) != nil
            let renamed = try store.rename(node.url, to: draftName)
            onStructureChange?(.moved(from: node.url, to: renamed))
            if wasExpanded { expandedFolders.insert(renamed) }
            editingURL = nil
            focusedEditingURL = nil
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func cancelRename() {
        editingURL = nil
        focusedEditingURL = nil
    }

    // MARK: - 行悬停「+」弹窗

    private func folderAddMenuBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { folderAddMenuURL == url },
            set: { if !$0 { folderAddMenuURL = nil } }
        )
    }

    private func folderAddMenu(for folder: URL) -> some View {
        VStack(spacing: 2) {
            addMenuButton(title: L10n.t("新建笔记", "New Note"), icon: .fileText) { createNote(in: folder) }
            addMenuButton(title: L10n.t("新建文件夹", "New Folder"), icon: .folder) { createFolder(in: folder) }
        }
        .padding(6)
        .frame(width: 176)
    }

    // MARK: - 右键菜单

    @ViewBuilder
    private func rowContextMenu(for node: WorkspaceNode) -> some View {
        if node.kind == .note {
            Button(L10n.t("在侧栏中打开", "Open in Side Pane")) { onOpenReference?(node.url) }
            Divider()
        }
        if node.kind == .folder {
            Button(L10n.t("新建笔记", "New Note")) { createNote(in: node.url) }
            Button(L10n.t("新建文件夹", "New Folder")) { createFolder(in: node.url) }
            Divider()
        }
        Button(L10n.t("重命名…", "Rename…")) {
            beginRename(node.url, currentName: node.name)
        }
        Button(L10n.t("复制", "Duplicate")) {
            duplicateNode(node)
        }
        Button(L10n.t("在 Finder 中显示", "Reveal in Finder")) {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        }
        Divider()
        Button(L10n.t("移到废纸篓", "Move to Trash"), role: .destructive) {
            deleteNode(node)
        }
    }

    private func duplicateNode(_ node: WorkspaceNode) {
        do {
            try store.duplicate(node.url)
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func deleteNode(_ node: WorkspaceNode) {
        do {
            expandedFolders.remove(node.url)
            try store.delete(node.url)
            onStructureChange?(.removed(node.url))
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    // MARK: - 拖拽转移

    private func rowBackgroundFill(for url: URL) -> Color {
        if dropTargetURL == url { return Color.primary.opacity(0.14) }
        if shortcutCenter.isSidebarFocused,
           shortcutCenter.sidebarNavigationURL == url {
            return Color.primary.opacity(0.16)
        }
        if store.selectedURL == url { return Color.primary.opacity(0.075) }
        return .clear
    }

    /// 把拖拽物放到某一行上：文件夹行 = 放入其中；笔记行 = 放入它所在的文件夹。
    private func performDrops(_ sources: [URL], onto target: WorkspaceNode?) -> Bool {
        guard !sources.isEmpty else { return false }
        var appearance = DocumentAppearance.current
        if sources.contains(where: { !$0.standardizedFileURL.path.hasPrefix(store.rootURL.path + "/") }) {
            let alert = NSAlert()
            alert.messageText = L10n.t("导入笔记", "Import Documents")
            let picker = DocumentAppearancePicker(selection: appearance)
            alert.accessoryView = picker
            alert.addButton(withTitle: L10n.t("导入", "Import"))
            alert.addButton(withTitle: L10n.t("取消", "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            appearance = picker.selection
        }
        let folder = target.map { $0.kind == .folder ? $0.url : $0.url.deletingLastPathComponent() }
        return sources.map { performDrop($0, toFolder: folder, expandOnSuccess: target?.kind == .folder ? folder : nil, appearance: appearance) }.contains(true)
    }

    private func performDrop(_ source: URL, onto target: WorkspaceNode) -> Bool {
        let destinationFolder = (target.kind == .folder
            ? target.url
            : target.url.deletingLastPathComponent()).standardizedFileURL
        return performDrop(source, toFolder: destinationFolder, expandOnSuccess: target.kind == .folder ? target.url : nil)
    }

    /// 把拖拽物放到空白区域：移回库根目录。
    private func performDropToRoot(_ source: URL) -> Bool {
        performDrop(source, toFolder: nil, expandOnSuccess: nil)
    }

    private func performDrop(_ source: URL, toFolder folder: URL?, expandOnSuccess: URL?, appearance: DocumentAppearance? = nil) -> Bool {
        let standardized = source.standardizedFileURL
        if !standardized.path.hasPrefix(store.rootURL.path + "/") {
            do {
                let imported = try store.importDocument(from: standardized, into: folder ?? store.rootURL)
                (appearance ?? .current).store(for: imported)
                if let expandOnSuccess { expandedFolders.insert(expandOnSuccess) }
                store.select(imported)
                onOpenNote?(imported)
                return true
            } catch {
                store.errorMessage = error.localizedDescription
                return false
            }
        }

        let destination = (folder ?? store.rootURL).standardizedFileURL
        // 拖到自身 / 自己的后代 / 原地不动：拒绝（动画弹回）。
        guard destination.path != standardized.path,
              !destination.path.hasPrefix(standardized.path + "/"),
              standardized.deletingLastPathComponent().standardizedFileURL != destination else {
            return false
        }

        do {
            let moved = try store.move(standardized, toFolder: folder)
            onStructureChange?(.moved(from: standardized, to: moved))
            if let expandOnSuccess { expandedFolders.insert(expandOnSuccess) }
            // 被拖动的文件夹如果处于展开状态，跟随新路径。
            if expandedFolders.contains(standardized) {
                expandedFolders.remove(standardized)
                expandedFolders.insert(moved)
            }
            return true
        } catch {
            store.errorMessage = error.localizedDescription
            return false
        }
    }

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.title = "Choose a DayDream Repository"
        panel.message = "Choose a folder containing your Markdown notes."
        panel.prompt = "Open"
        panel.directoryURL = store.rootURL
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.openRepository(url)
            resetTransientState()
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    // MARK: - 侧栏键盘导航（⌘O）

    private func moveSidebarNavigation(by delta: Int) {
        let allRows = rows
        guard !allRows.isEmpty else { return }
        let current = shortcutCenter.sidebarNavigationURL
        let index = allRows.firstIndex { $0.node.url == current } ?? (delta > 0 ? -1 : allRows.count)
        let next = min(max(index + delta, 0), allRows.count - 1)
        shortcutCenter.sidebarNavigationURL = allRows[next].node.url
    }

    private func confirmSidebarNavigation() {
        guard let url = shortcutCenter.sidebarNavigationURL,
              let row = rows.first(where: { $0.node.url == url }) else { return }
        if row.node.kind == .folder {
            withAnimation(.easeOut(duration: 0.14)) {
                if expandedFolders.contains(url) {
                    expandedFolders.remove(url)
                } else {
                    expandedFolders.insert(url)
                }
            }
        } else {
            selectNode(row.node)
            shortcutCenter.toggleSidebar()
        }
    }

    private func exitSidebarNavigation() {
        shortcutCenter.isSidebarFocused = false
        shortcutCenter.sidebarNavigationURL = nil
        shortcutCenter.refocusEditor()
    }

    // MARK: - 快捷键动作注册（⌘R / ⌘C / ⌘V）

    private func registerShortcutActions() {
        shortcutCenter.renameSelection = { [store] in
            if let url = store.selectedURL {
                NotificationCenter.default.post(name: .dayDreamBeginRename, object: url, userInfo: ["center": shortcutCenter])
            }
        }
        shortcutCenter.copySelection = { [store] in
            guard let url = store.selectedURL else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([url as NSURL])
        }
        shortcutCenter.paste = { [store] in
            guard let urls = NSPasteboard.general.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL], let source = urls.first else { return }
            do {
                let target = store.selectedURL.map { url -> URL in
                    ["md", "markdown", "pdf"].contains(url.pathExtension.lowercased())
                        ? url.deletingLastPathComponent()
                        : url
                }
                try store.pasteItem(from: source, into: target)
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
        shortcutCenter.deleteSelection = {
            guard shortcutCenter.isSidebarFocused,
                  let url = shortcutCenter.sidebarNavigationURL ?? store.selectedURL,
                  let node = rows.first(where: { $0.node.url == url })?.node,
                  node.kind == .note else { return }
            pendingDeletion = node
        }
    }

    private func resetTransientState() {
        expandedFolders = []
        editingURL = nil
        focusedEditingURL = nil
    }
}

private extension View {
    /// 重命名编辑期间禁用拖拽，避免与文本选择手势冲突。
    @ViewBuilder
    func draggableIf(_ condition: Bool, payload: URL) -> some View {
        if condition {
            draggable(payload)
        } else {
            self
        }
    }
}
