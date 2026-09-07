import Foundation
import XCTest
@testable import DayDream

final class FontLibraryTests: XCTestCase {
    func testImportedFontIsCopiedAndAvailableAfterReload() throws {
        let source = URL(fileURLWithPath: "/System/Library/Fonts/SFNSMono.ttf")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: source.path))
        let directory = try makeTemporaryDirectory()
        let library = FontLibrary(directoryURL: directory)

        let imported = try library.importFont(from: source)
        let reloaded = FontLibrary(directoryURL: directory)

        XCTAssertFalse(imported.isEmpty)
        XCTAssertEqual(reloaded.fonts, imported)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appending(path: source.lastPathComponent).path
        ))
    }

    func testImportRejectsUnsupportedFile() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.deletingLastPathComponent().appending(path: "\(UUID().uuidString).txt")
        try "not a font".write(to: source, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: source) }
        let library = FontLibrary(directoryURL: directory)

        XCTAssertThrowsError(try library.importFont(from: source))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
