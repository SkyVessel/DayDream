import Foundation
import XCTest
@testable import DayDream

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    func testReloadBuildsFolderFirstRecursiveTreeFromMarkdownFilesOnly() throws {
        let root = try makeTemporaryDirectory()
        let folder = root.appending(path: "Folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "# Nested".write(to: folder.appending(path: "Nested.md"), atomically: true, encoding: .utf8)
        try "ignore".write(to: root.appending(path: "ignore.txt"), atomically: true, encoding: .utf8)
        try "Body".write(to: root.appending(path: "Root.md"), atomically: true, encoding: .utf8)

        let store = WorkspaceStore(rootURL: root, autosaveDelay: 0)
        try store.reload()

        XCTAssertEqual(store.nodes.map(\.name), ["Folder", "Root"])
        XCTAssertEqual(store.nodes[0].kind, .folder)
        XCTAssertEqual(store.nodes[0].children.map(\.name), ["Nested"])
        XCTAssertEqual(store.nodes[0].children[0].kind, .note)
    }

    func testNewNodesUseSelectedFolderAndUniqueNames() throws {
        let store = WorkspaceStore(rootURL: try makeTemporaryDirectory(), autosaveDelay: 0)
        try store.reload()

        let folder = try store.createFolder(in: nil)
        let first = try store.createNote(in: folder)
        let second = try store.createNote(in: folder)

        XCTAssertEqual(first.deletingLastPathComponent().path, folder.path)
        XCTAssertEqual(second.deletingLastPathComponent().path, folder.path)
        XCTAssertNotEqual(first.lastPathComponent, second.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
    }

    func testSelectingAnotherNoteFlushesCurrentMarkdown() throws {
        let store = WorkspaceStore(rootURL: try makeTemporaryDirectory(), autosaveDelay: 60)
        try store.reload()
        let first = try store.createNote(in: nil)
        let second = try store.createNote(in: nil)

        try store.select(first)
        store.updateCurrentMarkdown("# Saved")
        try store.select(second)

        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "# Saved")
        XCTAssertEqual(store.selectedURL, second)
        XCTAssertEqual(store.currentMarkdown, "")
    }

    func testRenameSanitizesSeparatorsAndUpdatesSelection() throws {
        let store = WorkspaceStore(rootURL: try makeTemporaryDirectory(), autosaveDelay: 0)
        try store.reload()
        let note = try store.createNote(in: nil)
        try store.select(note)

        let renamed = try store.rename(note, to: "  My/Note:Draft  ")

        XCTAssertEqual(renamed.lastPathComponent, "My-Note-Draft.md")
        XCTAssertEqual(store.selectedURL, renamed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testExplicitFlushWritesLatestMarkdownAtomically() throws {
        let store = WorkspaceStore(rootURL: try makeTemporaryDirectory(), autosaveDelay: 60)
        try store.reload()
        let note = try store.createNote(in: nil)
        try store.select(note)

        store.updateCurrentMarkdown("- [ ] Ship")
        try store.flushPendingSave()

        XCTAssertEqual(try String(contentsOf: note, encoding: .utf8), "- [ ] Ship")
    }

    func testOpeningRepositoryAddsItSwitchesContentsAndCreatesThere() throws {
        let first = try makeTemporaryDirectory()
        let second = try makeTemporaryDirectory()
        try "Second".write(
            to: second.appending(path: "Existing.md"),
            atomically: true,
            encoding: .utf8
        )
        let store = WorkspaceStore(rootURL: first, autosaveDelay: 0)

        try store.openRepository(second)
        let created = try store.createNote(in: nil)

        XCTAssertEqual(store.repositoryURLs, [first.standardizedFileURL, second.standardizedFileURL])
        XCTAssertEqual(store.rootURL, second.standardizedFileURL)
        XCTAssertEqual(store.nodes.map(\.name), ["Existing", "Untitled"])
        XCTAssertEqual(created.deletingLastPathComponent(), second.standardizedFileURL)
    }

    func testRepositoryArrowsMoveWithinHistoryWithoutWrapping() throws {
        let first = try makeTemporaryDirectory()
        let second = try makeTemporaryDirectory()
        let third = try makeTemporaryDirectory()
        let store = WorkspaceStore(rootURL: first, autosaveDelay: 0)
        try store.openRepository(second)
        try store.openRepository(third)

        XCTAssertTrue(store.canSelectPreviousRepository)
        XCTAssertFalse(store.canSelectNextRepository)

        try store.selectPreviousRepository()
        XCTAssertEqual(store.rootURL, second.standardizedFileURL)
        try store.selectPreviousRepository()
        XCTAssertEqual(store.rootURL, first.standardizedFileURL)
        try store.selectPreviousRepository()
        XCTAssertEqual(store.rootURL, first.standardizedFileURL)
        XCTAssertFalse(store.canSelectPreviousRepository)

        try store.selectNextRepository()
        XCTAssertEqual(store.rootURL, second.standardizedFileURL)
    }

    func testRepositoryHistoryRestoresLastSelection() throws {
        let first = try makeTemporaryDirectory()
        let second = try makeTemporaryDirectory()
        let suiteName = "DayDreamTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }

        let original = WorkspaceStore(
            rootURL: first,
            autosaveDelay: 0,
            repositoryDefaults: defaults
        )
        try original.openRepository(second)

        let restored = WorkspaceStore(
            rootURL: first,
            autosaveDelay: 0,
            repositoryDefaults: defaults
        )

        XCTAssertEqual(restored.repositoryURLs, [first.standardizedFileURL, second.standardizedFileURL])
        XCTAssertEqual(restored.rootURL, second.standardizedFileURL)
    }

    func testMoveNoteIntoFolderUpdatesTree() throws {
        let store = WorkspaceStore(rootURL: try makeTemporaryDirectory(), autosaveDelay: 0)
        try store.reload()
        let folder = try store.createFolder(in: nil)
        let note = try store.createNote(in: nil)

        let moved = try store.move(note, toFolder: folder)

        XCTAssertEqual(moved.deletingLastPathComponent().standardizedFileURL, folder.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: note.path))
        XCTAssertEqual(store.nodes.first?.children.map(\.url), [moved])
    }

    func testMoveFolderIntoOwnDescendantThrows() throws {
        let store = WorkspaceStore(rootURL: try makeTemporaryDirectory(), autosaveDelay: 0)
        try store.reload()
        let parent = try store.createFolder(in: nil)
        let child = try store.createFolder(in: parent)

        XCTAssertThrowsError(try store.move(parent, toFolder: child)) { error in
            XCTAssertEqual(error as? WorkspaceStoreError, .cannotMoveIntoItself)
        }
    }

    func testMoveToSameParentIsNoOp() throws {
        let store = WorkspaceStore(rootURL: try makeTemporaryDirectory(), autosaveDelay: 0)
        try store.reload()
        let folder = try store.createFolder(in: nil)
        let note = try store.createNote(in: folder)

        let moved = try store.move(note, toFolder: folder)
        XCTAssertEqual(moved.standardizedFileURL, note.standardizedFileURL)
    }

    func testMoveFolderUpdatesSelectedNoteInsideIt() throws {
        let store = WorkspaceStore(rootURL: try makeTemporaryDirectory(), autosaveDelay: 0)
        try store.reload()
        let folderA = try store.createFolder(in: nil)
        let folderB = try store.createFolder(in: nil)
        let note = try store.createNote(in: folderA)
        try store.select(note)

        let movedFolder = try store.move(folderA, toFolder: folderB)

        XCTAssertEqual(
            store.selectedURL,
            movedFolder.appending(path: note.lastPathComponent).standardizedFileURL
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.selectedURL!.path))
    }

    func testDeleteTrashesNoteAndClearsSelection() throws {
        let store = WorkspaceStore(rootURL: try makeTemporaryDirectory(), autosaveDelay: 0)
        try store.reload()
        let note = try store.createNote(in: nil)
        try store.select(note)

        try store.delete(note)

        XCTAssertNil(store.selectedURL)
        XCTAssertEqual(store.currentMarkdown, "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: note.path))
        XCTAssertTrue(store.nodes.isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
