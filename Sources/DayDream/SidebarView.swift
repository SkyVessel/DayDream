import SwiftUI

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
    let isFullScreen: Bool
    @State private var expandedFolders: Set<URL> = []
    @State private var editingURL: URL?
    @State private var draftName = ""
    @State private var isAddMenuPresented = false
    @State private var hoveredURL: URL?
    /// 哪一行文件夹的「+」弹窗处于打开状态。
    @State private var folderAddMenuURL: URL?
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
                guard let source = items.first else { return false }
                return performDropToRoot(source)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(width: 0.5)
        }
        .alert(
            "DayDream couldn’t complete that action",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
    }

    private var header: some View {
        HStack(spacing: 3) {
            Button(action: chooseRepository) {
                Text("Library")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Choose a repository\n\(store.rootURL.path)")
            .accessibilityLabel("Choose Library")

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
            .help("Add a note or folder")
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
            addMenuButton(title: "New Note", icon: .fileText, action: createNote)
            addMenuButton(title: "New Folder", icon: .folder, action: createFolder)
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
                        .frame(width: 16, height: 20)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 16, height: 20)
            }

            if editingURL == row.node.url {
                rowIcon(row.node)
                TextField("Name", text: $draftName)
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
                    .help("Add a note or folder inside")
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
            guard let source = items.first else { return false }
            return performDrop(source, onto: row.node)
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
        do {
            try store.select(node.url)
        } catch {
            store.errorMessage = error.localizedDescription
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
            try store.select(url)
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
            try store.select(url)
            beginRename(url, currentName: url.lastPathComponent)
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
            addMenuButton(title: "New Note", icon: .fileText) { createNote(in: folder) }
            addMenuButton(title: "New Folder", icon: .folder) { createFolder(in: folder) }
        }
        .padding(6)
        .frame(width: 176)
    }

    // MARK: - 右键菜单

    @ViewBuilder
    private func rowContextMenu(for node: WorkspaceNode) -> some View {
        if node.kind == .folder {
            Button("New Note") { createNote(in: node.url) }
            Button("New Folder") { createFolder(in: node.url) }
            Divider()
        }
        Button("Rename…") {
            beginRename(node.url, currentName: node.name)
        }
        Button("Duplicate") {
            duplicateNode(node)
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        }
        Divider()
        Button("Move to Trash", role: .destructive) {
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
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    // MARK: - 拖拽转移

    private func rowBackgroundFill(for url: URL) -> Color {
        if dropTargetURL == url { return Color.primary.opacity(0.14) }
        if store.selectedURL == url { return Color.primary.opacity(0.075) }
        return .clear
    }

    /// 把拖拽物放到某一行上：文件夹行 = 放入其中；笔记行 = 放入它所在的文件夹。
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

    private func performDrop(_ source: URL, toFolder folder: URL?, expandOnSuccess: URL?) -> Bool {
        let standardized = source.standardizedFileURL
        // 只接受库内部的拖拽；来自 Finder 的外部文件直接拒绝。
        guard standardized.path.hasPrefix(store.rootURL.path + "/") else { return false }

        let destination = (folder ?? store.rootURL).standardizedFileURL
        // 拖到自身 / 自己的后代 / 原地不动：拒绝（动画弹回）。
        guard destination.path != standardized.path,
              !destination.path.hasPrefix(standardized.path + "/"),
              standardized.deletingLastPathComponent().standardizedFileURL != destination else {
            return false
        }

        do {
            let moved = try store.move(standardized, toFolder: folder)
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
