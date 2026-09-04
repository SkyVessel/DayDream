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

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var nodes: [WorkspaceNode] = []
    @Published private(set) var selectedURL: URL?
    @Published private(set) var repositoryURLs: [URL]
    @Published private(set) var repositoryIndex: Int
    @Published var currentMarkdown = ""
    @Published var errorMessage: String?

    var rootURL: URL { repositoryURLs[repositoryIndex] }
    var canSelectPreviousRepository: Bool { repositoryIndex > 0 }
    var canSelectNextRepository: Bool { repositoryIndex + 1 < repositoryURLs.count }

    private let autosaveDelay: TimeInterval
    private let fileManager: FileManager
    private let repositoryDefaults: UserDefaults?
    private var pendingSave: DispatchWorkItem?

    private static let repositoryPathsKey = "repositoryPaths"
    private static let selectedRepositoryPathKey = "selectedRepositoryPath"

    init(
        rootURL: URL = WorkspaceStore.defaultRootURL(),
        autosaveDelay: TimeInterval = 0.35,
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
        self.autosaveDelay = autosaveDelay
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
            try flushPendingSave()
            repositoryURLs.append(repository)
            try selectRepository(at: repositoryURLs.count - 1, flushCurrent: false)
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
    func rename(_ url: URL, to proposedName: String) throws -> URL {
        try flushPendingSave()
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

    func select(_ url: URL?) throws {
        try flushPendingSave()
        pendingSave?.cancel()
        pendingSave = nil

        guard let url else {
            selectedURL = nil
            currentMarkdown = ""
            return
        }

        let selected = url.standardizedFileURL
        selectedURL = selected
        if selected.pathExtension.lowercased() == "md" {
            currentMarkdown = try String(contentsOf: selected, encoding: .utf8)
        } else {
            currentMarkdown = ""
        }
    }

    func updateCurrentMarkdown(_ markdown: String) {
        currentMarkdown = markdown
        pendingSave?.cancel()

        guard selectedURL?.pathExtension.lowercased() == "md" else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                try self.flushPendingSave()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
        pendingSave = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autosaveDelay, execute: workItem)
    }

    func flushPendingSave() throws {
        pendingSave?.cancel()
        pendingSave = nil
        guard let url = selectedURL,
              url.pathExtension.lowercased() == "md" else { return }
        try Data(currentMarkdown.utf8).write(to: url, options: .atomic)
    }

    func parentForNewNode() -> URL? {
        guard let selectedURL else { return nil }
        return selectedURL.pathExtension.lowercased() == "md"
            ? selectedURL.deletingLastPathComponent()
            : selectedURL
    }

    private func selectRepository(at index: Int, flushCurrent: Bool = true) throws {
        guard repositoryURLs.indices.contains(index), index != repositoryIndex else {
            persistRepositories()
            return
        }
        if flushCurrent {
            try flushPendingSave()
        }
        try validateRepository(repositoryURLs[index])
        pendingSave?.cancel()
        pendingSave = nil
        selectedURL = nil
        currentMarkdown = ""
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

    var errorDescription: String? {
        switch self {
        case .invalidName: return "Name cannot be empty."
        case .nameAlreadyExists: return "An item with that name already exists."
        case .outsideLibrary: return "That location is outside the DayDream library."
        case .folderUnavailable: return "The selected folder is unavailable."
        }
    }
}
