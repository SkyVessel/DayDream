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
            }
        }
        .padding(.leading, CGFloat(row.depth) * 17)
        .padding(.horizontal, 7)
        .frame(height: 31)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(store.selectedURL == row.node.url ? Color.primary.opacity(0.075) : .clear)
        }
        .contentShape(Rectangle())
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
        isAddMenuPresented = false
        do {
            let parent = store.parentForNewNode()
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
        isAddMenuPresented = false
        do {
            let parent = store.parentForNewNode()
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
