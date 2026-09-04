import Combine
import Foundation

/// 单个编辑器窗格：标签页列表 + 当前文档 + 各自的防抖落盘。
/// 磁盘上的 .md 文件是唯一真相源，窗格内容只是它的运行时投影。
@MainActor
final class EditorPaneStore: ObservableObject, Identifiable {
    let id = UUID()

    @Published private(set) var tabs: [URL] = []
    @Published private(set) var activeIndex: Int = -1
    @Published private(set) var markdown: String = ""

    var activeURL: URL? {
        tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil
    }

    private let autosaveDelay: TimeInterval
    private let fileManager: FileManager
    private var pendingSave: DispatchWorkItem?

    init(autosaveDelay: TimeInterval = 0.35, fileManager: FileManager = .default) {
        self.autosaveDelay = autosaveDelay
        self.fileManager = fileManager
    }

    // MARK: - 标签页

    func open(_ url: URL) {
        let standardized = url.standardizedFileURL
        if let index = tabs.firstIndex(of: standardized) {
            guard index != activeIndex else { return }
            flush()
            activeIndex = index
        } else {
            flush()
            tabs.append(standardized)
            activeIndex = tabs.count - 1
        }
        loadActive()
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index), index != activeIndex else { return }
        flush()
        activeIndex = index
        loadActive()
    }

    func closeTab(at index: Int) {
        removeTab(at: index, saving: true)
    }

    private func removeTab(at index: Int, saving: Bool) {
        guard tabs.indices.contains(index) else { return }
        let wasActive = index == activeIndex
        if wasActive, saving { flush() }
        if wasActive {
            pendingSave?.cancel()
            pendingSave = nil
        }
        tabs.remove(at: index)

        if tabs.isEmpty {
            activeIndex = -1
            markdown = ""
            return
        }
        if activeIndex > index {
            activeIndex -= 1
        } else if wasActive {
            activeIndex = min(index, tabs.count - 1)
        }
        if wasActive { loadActive() }
    }

    /// 合并另一个窗格的标签页（关闭分屏时调用）。
    func mergeTabs(from other: EditorPaneStore) {
        let wasEmpty = tabs.isEmpty
        for url in other.tabs where !tabs.contains(url) {
            tabs.append(url)
        }
        if wasEmpty, !tabs.isEmpty {
            activeIndex = tabs.count - 1
            loadActive()
        }
    }

    // MARK: - 内容

    func loadActive() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let url = activeURL else {
            markdown = ""
            return
        }
        markdown = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func updateMarkdown(_ markdown: String) {
        self.markdown = markdown
        pendingSave?.cancel()
        guard activeURL != nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.flush()
        }
        pendingSave = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autosaveDelay, execute: workItem)
    }

    /// 立即落盘。文件已不存在时跳过，避免幽灵重建被删除的文件。
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let url = activeURL,
              fileManager.fileExists(atPath: url.path) else { return }
        try? Data(markdown.utf8).write(to: url, options: .atomic)
    }

    // MARK: - 结构变更同步（重命名 / 移动 / 删除）

    func applyStructureChange(_ change: WorkspaceStructureChange) {
        switch change {
        case let .moved(from, to):
            tabs = tabs.map { tab in
                if tab == from { return to }
                if tab.path.hasPrefix(from.path + "/") {
                    let relative = String(tab.path.dropFirst(from.path.count + 1))
                    return to.appending(path: relative).standardizedFileURL
                }
                return tab
            }
        case let .removed(url):
            while let index = tabs.firstIndex(where: {
                $0 == url || $0.path.hasPrefix(url.path + "/")
            }) {
                removeTab(at: index, saving: false)
            }
        }
    }
}

/// 库结构变更：moved 覆盖重命名与移动（路径变化）。
enum WorkspaceStructureChange {
    case moved(from: URL, to: URL)
    case removed(URL)
}
