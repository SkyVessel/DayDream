import AppKit
import XCTest
@testable import DayDream

@MainActor
final class DocumentTransferServiceTests: XCTestCase {
    func testMarkdownImportPreservesOriginalBytesAndUsesUniqueName() throws {
        let sourceDirectory = try makeTemporaryDirectory()
        let destinationDirectory = try makeTemporaryDirectory()
        let source = sourceDirectory.appending(path: "Notes.md")
        let bytes = Data("# Title\r\n\r\nBody  \r\n".utf8)
        try bytes.write(to: source)
        try Data().write(to: destinationDirectory.appending(path: "Notes.md"))

        let imported = try DocumentTransferService().importDocument(
            from: source,
            into: destinationDirectory
        )

        XCTAssertEqual(imported.lastPathComponent, "Notes 2.md")
        XCTAssertEqual(try Data(contentsOf: imported), bytes)
    }

    func testMarkdownExportWritesExactSource() throws {
        let directory = try makeTemporaryDirectory()
        let destination = directory.appending(path: "Export.md")
        let markdown = "# Title\n\n- one\n- two\n"

        try DocumentTransferService().exportMarkdown(markdown, to: destination)

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), markdown)
    }

    func testWordRoundTripKeepsHeadingsListsAndInlineStylesReadable() throws {
        let directory = try makeTemporaryDirectory()
        let destination = directory.appending(path: "Export.docx")
        let markdown = "# Title\n\n1. first\n2. second\n\n**bold** and *italic* and [link](https://example.com)"
        let service = DocumentTransferService()

        try service.exportWord(markdown, to: destination)
        let imported = try service.markdown(fromWordDocument: destination)

        XCTAssertTrue(imported.contains("# Title"))
        XCTAssertTrue(imported.contains("1. first"))
        XCTAssertTrue(imported.contains("2. second"))
        XCTAssertTrue(imported.contains("**bold**"))
        XCTAssertTrue(imported.contains("*italic*"))
        XCTAssertTrue(imported.contains("[link](https://example.com)"))
    }

    func testUnsupportedImportDoesNotCreateOutput() throws {
        let sourceDirectory = try makeTemporaryDirectory()
        let destinationDirectory = try makeTemporaryDirectory()
        let source = sourceDirectory.appending(path: "Notes.txt")
        try "plain".write(to: source, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try DocumentTransferService().importDocument(from: source, into: destinationDirectory)
        )
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destinationDirectory.path).isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
