import Combine
import Foundation

enum WorkspaceNodeKind: Equatable, Hashable, Sendable {
    case folder
    case note
}

struct WorkspaceNode: Identifiable, Equatable, Hashable, Sendable {
    let url: URL
    let kind: WorkspaceNodeKind
    var children: [WorkspaceNode]

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

/// 库结构管理：文件树、选中项、多笔记库。
/// 文档内容的读写由 DocumentController 负责。
@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var nodes: [WorkspaceNode] = []
    @Published private(set) var selectedURL: URL?
    @Published private(set) var repositoryURLs: [URL]
    @Published private(set) var repositoryIndex: Int
    @Published var errorMessage: String?

    var rootURL: URL { repositoryURLs[repositoryIndex] }
    var canSelectPreviousRepository: Bool { repositoryIndex > 0 }
    var canSelectNextRepository: Bool { repositoryIndex + 1 < repositoryURLs.count }

    /// 结构变更（重命名/移动/删除/粘贴）前调用——视图层先把当前文档落盘。
    var beforeMutation: (() -> Void)?

    private let fileManager: FileManager
    private let repositoryDefaults: UserDefaults?

    private static let repositoryPathsKey = "repositoryPaths"
    private static let selectedRepositoryPathKey = "selectedRepositoryPath"

    init(
        rootURL: URL = WorkspaceStore.defaultRootURL(),
        fileManager: FileManager = .default,
        repositoryDefaults: UserDefaults? = nil
    ) {
        let initialRoot = rootURL.standardizedFileURL
        let storedURLs = repositoryDefaults?
            .stringArray(forKey: Self.repositoryPathsKey)?
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
            ?? []
        var repositories = storedURLs.filter { url in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
        if !repositories.contains(initialRoot) {
            repositories.insert(initialRoot, at: 0)
        }
        let selectedPath = repositoryDefaults?.string(forKey: Self.selectedRepositoryPathKey)

        self.repositoryURLs = repositories
        self.repositoryIndex = repositories.firstIndex { $0.path == selectedPath } ?? 0
        self.fileManager = fileManager
        self.repositoryDefaults = repositoryDefaults
        do {
            try fileManager.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true
            )
            try reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    nonisolated static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return base.appending(path: "DayDream/Library", directoryHint: .isDirectory)
    }

    func reload() throws {
        nodes = try scanDirectory(rootURL)
    }

    func openRepository(_ url: URL) throws {
        let repository = url.standardizedFileURL
        try validateRepository(repository)

        if let existingIndex = repositoryURLs.firstIndex(of: repository) {
            try selectRepository(at: existingIndex)
        } else {
            beforeMutation?()
            repositoryURLs.append(repository)
            try selectRepository(at: repositoryURLs.count - 1)
        }
    }

    func selectPreviousRepository() throws {
        guard canSelectPreviousRepository else { return }
        try selectRepository(at: repositoryIndex - 1)
    }

    func selectNextRepository() throws {
        guard canSelectNextRepository else { return }
        try selectRepository(at: repositoryIndex + 1)
    }

    func createNote(in parentURL: URL?) throws -> URL {
        let parent = try validatedDirectory(parentURL)
        let url = uniqueURL(in: parent, baseName: "Untitled", pathExtension: "md")
        try Data().write(to: url, options: .atomic)
        try reload()
        return url
    }

    func createFolder(in parentURL: URL?) throws -> URL {
        let parent = try validatedDirectory(parentURL)
        let url = uniqueURL(in: parent, baseName: "New Folder", pathExtension: nil)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        try reload()
        return url
    }

    @discardableResult
    func importDocument(
        from source: URL,
        service: DocumentTransferService = DocumentTransferService()
    ) throws -> URL {
        beforeMutation?()
        let parent = try validatedDirectory(parentForNewNode())
        let url = try service.importDocument(from: source, into: parent)
        try reload()
        return url
    }

    @discardableResult
    func rename(_ url: URL, to proposedName: String) throws -> URL {
        beforeMutation?()
        let source = url.standardizedFileURL
        let isNote = source.pathExtension.lowercased() == "md"
        let cleaned = sanitizedName(proposedName)
        guard !cleaned.isEmpty else {
            throw WorkspaceStoreError.invalidName
        }

        let destination = source.deletingLastPathComponent().appending(
            path: isNote ? cleaned + ".md" : cleaned,
            directoryHint: isNote ? .notDirectory : .isDirectory
        )
        if destination != source, fileManager.fileExists(atPath: destination.path) {
            throw WorkspaceStoreError.nameAlreadyExists
        }
        if destination != source {
            try fileManager.moveItem(at: source, to: destination)
        }

        if selectedURL == source {
            selectedURL = destination
        }
        try reload()
        return destination
    }

    /// 选中只影响侧栏高亮与「新建」的父目录推断，不涉及内容加载。
    func select(_ url: URL?) {
        selectedURL = url?.standardizedFileURL
    }

    /// 拖拽移动：把笔记或文件夹转移到目标文件夹（nil = 库根目录）。
    /// 返回移动后的新 URL。
    @discardableResult
    func move(_ url: URL, toFolder targetFolder: URL?) throws -> URL {
        beforeMutation?()
        let source = url.standardizedFileURL
        let destinationFolder = try validatedDirectory(targetFolder)

        // 不能移动到自身内部（文件夹拖进自己或自己的后代）。
        if destinationFolder.path == source.path
            || destinationFolder.path.hasPrefix(source.path + "/") {
            throw WorkspaceStoreError.cannotMoveIntoItself
        }

        // 父目录没变：无事发生。
        let currentParent = source.deletingLastPathComponent().standardizedFileURL
        guard currentParent != destinationFolder else { return source }

        let destination = destinationFolder.appending(path: source.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            throw WorkspaceStoreError.nameAlreadyExists
        }
        try MediaResources.copyAlongsideDocument(from: source, to: destination)
        try fileManager.moveItem(at: source, to: destination)

        // 同步选中项路径（选中的笔记被移动，或它所在的文件夹被移动）。
        if let selected = selectedURL {
            if selected == source {
                selectedURL = destination
            } else if selected.path.hasPrefix(source.path + "/") {
                let relative = String(selected.path.dropFirst(source.path.count + 1))
                selectedURL = destination.appending(path: relative)
            }
        }
        try reload()
        return destination
    }

    /// 复制（拷贝为新文件/新文件夹，名称自动加后缀唯一化）。
    @discardableResult
    func duplicate(_ url: URL) throws -> URL {
        beforeMutation?()
        let source = url.standardizedFileURL
        guard source.path.hasPrefix(rootURL.path + "/") else {
            throw WorkspaceStoreError.outsideLibrary
        }
        let isNote = source.pathExtension.lowercased() == "md"
        let baseName = isNote
            ? source.deletingPathExtension().lastPathComponent
            : source.lastPathComponent
        let destination = uniqueURL(
            in: source.deletingLastPathComponent(),
            baseName: baseName + " copy",
            pathExtension: isNote ? "md" : nil
        )
        try fileManager.copyItem(at: source, to: destination)
        try reload()
        return destination
    }

    /// 粘贴（⌘V）：把剪贴板里的文件/文件夹拷贝进目标文件夹。
    /// 库内部条目 = 复制；库外部条目 = 导入（仅限 .md 与文件夹）。
    @discardableResult
    func pasteItem(from source: URL, into targetFolder: URL?) throws -> URL {
        beforeMutation?()
        let destinationFolder = try validatedDirectory(targetFolder)
        let src = source.standardizedFileURL

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: src.path, isDirectory: &isDirectory) else {
            throw WorkspaceStoreError.folderUnavailable
        }
        guard isDirectory.boolValue || src.pathExtension.lowercased() == "md" else {
            throw WorkspaceStoreError.unsupportedItem
        }
        // 目标不能在源内部（文件夹粘贴到自身或自己的后代）。
        if destinationFolder.path == src.path
            || destinationFolder.path.hasPrefix(src.path + "/") {
            throw WorkspaceStoreError.cannotMoveIntoItself
        }

        let baseName = isDirectory.boolValue
            ? src.lastPathComponent
            : src.deletingPathExtension().lastPathComponent
        let destination = uniqueURL(
            in: destinationFolder,
            baseName: baseName,
            pathExtension: isDirectory.boolValue ? nil : "md"
        )
        try MediaResources.copyAlongsideDocument(from: src, to: destination)
        try fileManager.copyItem(at: src, to: destination)
        try reload()
        return destination
    }

    /// 删除（移到废纸篓，可恢复）。
    func delete(_ url: URL) throws {
        beforeMutation?()
        let source = url.standardizedFileURL
        guard source.path.hasPrefix(rootURL.path + "/") else {
            throw WorkspaceStoreError.outsideLibrary
        }
        try fileManager.trashItem(at: source, resultingItemURL: nil)

        // 选中的笔记被删除（或所在文件夹被删除）：取消选中。
        if let selected = selectedURL,
           selected == source || selected.path.hasPrefix(source.path + "/") {
            selectedURL = nil
        }
        try reload()
    }

    func parentForNewNode() -> URL? {
        guard let selectedURL else { return nil }
        return selectedURL.pathExtension.lowercased() == "md"
            ? selectedURL.deletingLastPathComponent()
            : selectedURL
    }

    private func selectRepository(at index: Int) throws {
        guard repositoryURLs.indices.contains(index), index != repositoryIndex else {
            persistRepositories()
            return
        }
        beforeMutation?()
        try validateRepository(repositoryURLs[index])
        selectedURL = nil
        repositoryIndex = index
        try reload()
        persistRepositories()
    }

    private func validateRepository(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw WorkspaceStoreError.folderUnavailable
        }
    }

    private func persistRepositories() {
        repositoryDefaults?.set(repositoryURLs.map(\.path), forKey: Self.repositoryPathsKey)
        repositoryDefaults?.set(rootURL.path, forKey: Self.selectedRepositoryPathKey)
    }

    private func scanDirectory(_ directory: URL) throws -> [WorkspaceNode] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey]
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).compactMap { url -> WorkspaceNode? in
            let values = try url.resourceValues(forKeys: keys)
            guard values.isHidden != true else { return nil }
            if values.isDirectory == true {
                return WorkspaceNode(url: url.standardizedFileURL, kind: .folder, children: try scanDirectory(url))
            }
            guard url.pathExtension.lowercased() == "md" else { return nil }
            return WorkspaceNode(url: url.standardizedFileURL, kind: .note, children: [])
        }.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .folder }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func validatedDirectory(_ candidate: URL?) throws -> URL {
        let directory = (candidate ?? rootURL).standardizedFileURL
        guard directory.path == rootURL.path || directory.path.hasPrefix(rootURL.path + "/") else {
            throw WorkspaceStoreError.outsideLibrary
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw WorkspaceStoreError.folderUnavailable
        }
        return directory
    }

    private func uniqueURL(in directory: URL, baseName: String, pathExtension: String?) -> URL {
        var suffix = 1
        while true {
            let name = suffix == 1 ? baseName : "\(baseName) \(suffix)"
            let fileName = pathExtension.map { name + "." + $0 } ?? name
            let candidate = directory.appending(path: fileName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    private func sanitizedName(_ proposedName: String) -> String {
        proposedName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\0", with: "")
    }
}

enum WorkspaceStoreError: LocalizedError {
    case invalidName
    case nameAlreadyExists
    case outsideLibrary
    case folderUnavailable
    case cannotMoveIntoItself
    case unsupportedItem

    var errorDescription: String? {
        switch self {
        case .invalidName: return "Name cannot be empty."
        case .nameAlreadyExists: return "An item with that name already exists."
        case .outsideLibrary: return "That location is outside the DayDream library."
        case .folderUnavailable: return "The selected folder is unavailable."
        case .cannotMoveIntoItself: return "A folder cannot be moved into itself."
        case .unsupportedItem: return "Only Markdown files and folders can be pasted here."
        }
    }
}
