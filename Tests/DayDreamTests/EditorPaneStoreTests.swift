import Foundation
import XCTest
@testable import DayDream

@MainActor
final class EditorPaneStoreTests: XCTestCase {

    func testOpenAddsTabAndLoadsContent() throws {
        let root = try makeTemporaryDirectory()
        let note = root.appending(path: "Note.md")
        try "# Hello".write(to: note, atomically: true, encoding: .utf8)

        let pane = EditorPaneStore(autosaveDelay: 0)
        pane.open(note)

        XCTAssertEqual(pane.tabs, [note.standardizedFileURL])
        XCTAssertEqual(pane.activeIndex, 0)
        XCTAssertEqual(pane.markdown, "# Hello")
    }

    func testSwitchingTabsFlushesPreviousDocument() throws {
        let root = try makeTemporaryDirectory()
        let first = root.appending(path: "First.md")
        let second = root.appending(path: "Second.md")
        try "one".write(to: first, atomically: true, encoding: .utf8)
        try "two".write(to: second, atomically: true, encoding: .utf8)

        let pane = EditorPaneStore(autosaveDelay: 60)
        pane.open(first)
        pane.updateMarkdown("one edited")
        pane.open(second)

        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "one edited")
        XCTAssertEqual(pane.markdown, "two")
    }

    func testCloseActiveTabActivatesNeighbor() throws {
        let root = try makeTemporaryDirectory()
        let first = root.appending(path: "First.md")
        let second = root.appending(path: "Second.md")
        try "one".write(to: first, atomically: true, encoding: .utf8)
        try "two".write(to: second, atomically: true, encoding: .utf8)

        let pane = EditorPaneStore(autosaveDelay: 0)
        pane.open(first)
        pane.open(second)
        pane.closeTab(at: 1)

        XCTAssertEqual(pane.tabs.count, 1)
        XCTAssertEqual(pane.activeIndex, 0)
        XCTAssertEqual(pane.markdown, "one")
    }

    func testCloseLastTabEmptiesPane() throws {
        let root = try makeTemporaryDirectory()
        let note = root.appending(path: "Note.md")
        try "x".write(to: note, atomically: true, encoding: .utf8)

        let pane = EditorPaneStore(autosaveDelay: 0)
        pane.open(note)
        pane.closeTab(at: 0)

        XCTAssertTrue(pane.tabs.isEmpty)
        XCTAssertEqual(pane.activeIndex, -1)
        XCTAssertEqual(pane.markdown, "")
    }

    func testFlushDoesNotRecreateDeletedFile() throws {
        let root = try makeTemporaryDirectory()
        let note = root.appending(path: "Note.md")
        try "x".write(to: note, atomically: true, encoding: .utf8)

        let pane = EditorPaneStore(autosaveDelay: 0)
        pane.open(note)
        pane.updateMarkdown("ghost")
        try FileManager.default.removeItem(at: note)
        pane.flush()

        XCTAssertFalse(FileManager.default.fileExists(atPath: note.path))
    }

    func testStructureChangeMovedUpdatesTabPaths() throws {
        let root = try makeTemporaryDirectory()
        let folder = root.appending(path: "Folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let note = folder.appending(path: "Note.md")
        try "x".write(to: note, atomically: true, encoding: .utf8)

        let pane = EditorPaneStore(autosaveDelay: 0)
        pane.open(note)

        let movedFolder = root.appending(path: "Renamed", directoryHint: .isDirectory)
        pane.applyStructureChange(.moved(from: folder.standardizedFileURL, to: movedFolder.standardizedFileURL))

        XCTAssertEqual(pane.activeURL, movedFolder.appending(path: "Note.md").standardizedFileURL)
    }

    func testStructureChangeRemovedClosesTabsWithoutSaving() throws {
        let root = try makeTemporaryDirectory()
        let note = root.appending(path: "Note.md")
        try "x".write(to: note, atomically: true, encoding: .utf8)

        let pane = EditorPaneStore(autosaveDelay: 0)
        pane.open(note)
        try FileManager.default.removeItem(at: note)
        pane.applyStructureChange(.removed(note.standardizedFileURL))

        XCTAssertTrue(pane.tabs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: note.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
