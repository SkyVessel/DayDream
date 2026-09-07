import Foundation
import XCTest
@testable import DayDream

@MainActor
final class DocumentControllerTests: XCTestCase {
    func testOpeningAnotherDocumentFlushesCurrentAndLoadsNext() throws {
        let root = try makeTemporaryDirectory()
        let first = root.appending(path: "First.md")
        let second = root.appending(path: "Second.md")
        try "one".write(to: first, atomically: true, encoding: .utf8)
        try "two".write(to: second, atomically: true, encoding: .utf8)
        let controller = DocumentController(autosaveDelay: 60)

        controller.open(first)
        controller.updateMarkdown("one edited")
        controller.open(second)

        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "one edited")
        XCTAssertEqual(controller.currentURL, second.standardizedFileURL)
        XCTAssertEqual(controller.markdown, "two")
    }

    func testFlushDoesNotRecreateDeletedFile() throws {
        let root = try makeTemporaryDirectory()
        let note = root.appending(path: "Note.md")
        try "x".write(to: note, atomically: true, encoding: .utf8)
        let controller = DocumentController(autosaveDelay: 60)

        controller.open(note)
        controller.updateMarkdown("ghost")
        try FileManager.default.removeItem(at: note)
        controller.flush()

        XCTAssertFalse(FileManager.default.fileExists(atPath: note.path))
    }

    func testStructureChangesTrackOrClearCurrentDocument() throws {
        let root = try makeTemporaryDirectory()
        let folder = root.appending(path: "Folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let note = folder.appending(path: "Note.md")
        try "x".write(to: note, atomically: true, encoding: .utf8)
        let controller = DocumentController(autosaveDelay: 0)
        controller.open(note)

        let movedFolder = root.appending(path: "Renamed", directoryHint: .isDirectory)
        controller.applyStructureChange(.moved(from: folder, to: movedFolder))
        XCTAssertEqual(controller.currentURL, movedFolder.appending(path: "Note.md").standardizedFileURL)

        controller.applyStructureChange(.removed(movedFolder))
        XCTAssertNil(controller.currentURL)
        XCTAssertEqual(controller.markdown, "")
    }

    func testFlushDoesNotOverwriteAnExternalEdit() throws {
        let root = try makeTemporaryDirectory()
        let note = root.appending(path: "Note.md")
        try "original".write(to: note, atomically: true, encoding: .utf8)
        let controller = DocumentController(autosaveDelay: 60)

        controller.open(note)
        controller.updateMarkdown("local edit")
        try "external edit".write(to: note, atomically: true, encoding: .utf8)

        XCTAssertFalse(controller.flush())
        XCTAssertEqual(try String(contentsOf: note, encoding: .utf8), "external edit")
        XCTAssertEqual(controller.externalEditConflict, note.standardizedFileURL)
        XCTAssertEqual(controller.markdown, "local edit")
    }

    func testExternalConflictCanReloadDiskOrExplicitlyKeepLocalVersion() throws {
        let root = try makeTemporaryDirectory()
        let note = root.appending(path: "Note.md")
        try "original".write(to: note, atomically: true, encoding: .utf8)
        let controller = DocumentController(autosaveDelay: 60)

        controller.open(note)
        controller.updateMarkdown("first local edit")
        try "first external edit".write(to: note, atomically: true, encoding: .utf8)
        XCTAssertFalse(controller.flush())

        controller.reloadFromDisk()
        XCTAssertEqual(controller.markdown, "first external edit")
        XCTAssertNil(controller.externalEditConflict)

        controller.updateMarkdown("second local edit")
        try "second external edit".write(to: note, atomically: true, encoding: .utf8)
        XCTAssertFalse(controller.flush())
        controller.overwriteExternalChanges()

        XCTAssertEqual(try String(contentsOf: note, encoding: .utf8), "second local edit")
        XCTAssertNil(controller.externalEditConflict)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
