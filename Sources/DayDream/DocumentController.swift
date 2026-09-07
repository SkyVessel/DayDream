import Combine
import Foundation

/// 唯一编辑器中的当前文档与防抖落盘。
/// 磁盘上的 .md 文件是唯一真相源；切换文档前会先保存当前内容。
@MainActor
final class DocumentController: ObservableObject {
    @Published private(set) var currentURL: URL?
    @Published private(set) var markdown = ""
    @Published private(set) var externalEditConflict: URL?
    @Published private(set) var reloadRevision = 0

    private let autosaveDelay: TimeInterval
    private let fileManager: FileManager
    private var pendingSave: DispatchWorkItem?
    private var lastKnownDiskData: Data?

    init(autosaveDelay: TimeInterval = 0.35, fileManager: FileManager = .default) {
        self.autosaveDelay = autosaveDelay
        self.fileManager = fileManager
    }

    func open(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard standardized != currentURL else { return }
        if currentURL != nil, !flush() { return }
        guard let data = try? Data(contentsOf: standardized),
              let contents = String(data: data, encoding: .utf8) else { return }
        currentURL = standardized
        markdown = contents
        lastKnownDiskData = data
        externalEditConflict = nil
    }

    func clear(saving: Bool = true) {
        if saving, !flush() { return }
        pendingSave?.cancel()
        pendingSave = nil
        currentURL = nil
        markdown = ""
        lastKnownDiskData = nil
        externalEditConflict = nil
    }

    func updateMarkdown(_ markdown: String) {
        self.markdown = markdown
        pendingSave?.cancel()
        guard currentURL != nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.flush()
        }
        pendingSave = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autosaveDelay, execute: workItem)
    }

    /// 文件已不存在时跳过，避免删除后被延迟保存幽灵重建。
    @discardableResult
    func flush() -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        guard let url = currentURL,
              fileManager.fileExists(atPath: url.path),
              let diskData = try? Data(contentsOf: url) else { return false }
        let desiredData = Data(markdown.utf8)
        if let lastKnownDiskData,
           diskData != lastKnownDiskData,
           diskData != desiredData {
            externalEditConflict = url
            return false
        }
        guard diskData != desiredData else {
            lastKnownDiskData = diskData
            externalEditConflict = nil
            return true
        }
        do {
            try desiredData.write(to: url, options: .atomic)
            lastKnownDiskData = desiredData
            externalEditConflict = nil
            return true
        } catch {
            return false
        }
    }

    func reloadFromDisk() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let url = currentURL,
              let data = try? Data(contentsOf: url),
              let contents = String(data: data, encoding: .utf8) else { return }
        markdown = contents
        lastKnownDiskData = data
        externalEditConflict = nil
        reloadRevision += 1
    }

    func overwriteExternalChanges() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let url = currentURL,
              fileManager.fileExists(atPath: url.path) else { return }
        let data = Data(markdown.utf8)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        lastKnownDiskData = data
        externalEditConflict = nil
    }

    func applyStructureChange(_ change: WorkspaceStructureChange) {
        guard let currentURL else { return }
        switch change {
        case let .moved(from, to):
            if currentURL == from {
                self.currentURL = to.standardizedFileURL
            } else if currentURL.path.hasPrefix(from.path + "/") {
                let relative = String(currentURL.path.dropFirst(from.path.count + 1))
                self.currentURL = to.appending(path: relative).standardizedFileURL
            }
        case let .removed(url):
            if currentURL == url || currentURL.path.hasPrefix(url.path + "/") {
                clear(saving: false)
            }
        }
    }
}

/// 库结构变更：moved 覆盖重命名与移动（路径变化）。
enum WorkspaceStructureChange {
    case moved(from: URL, to: URL)
    case removed(URL)
}
