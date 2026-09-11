import AppKit
import PDFKit
import XCTest
@testable import DayDream

@MainActor
final class DocumentExportLayoutTests: XCTestCase {
    func testPDFPreservesTextWidthBackgroundAndPagination() throws {
        let text = (0..<100).map { "Paragraph \($0): readable export text." }.joined(separator: "\n")
        let source = DayDreamTextView(frame: NSRect(x: 0, y: 0, width: 720, height: 400), textContainer: nil)
        let layout = DocumentExportLayout(markdown: text, sourceURL: nil, mode: .dark, source: source)
        let data = try layout.pdfData()
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, layout.pages.count)
        XCTAssertGreaterThan(pdf.pageCount, 1)
        XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).width, 720)
        XCTAssertTrue(pdf.string?.contains("Paragraph 0:") == true)
        XCTAssertTrue(pdf.string?.contains("Paragraph 99:") == true)
        let image = try XCTUnwrap(pdf.page(at: 0)?.thumbnail(of: NSSize(width: 720, height: 1018), for: .mediaBox))
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let corner = try XCTUnwrap(bitmap.colorAt(x: 2, y: 2)?.usingColorSpace(.sRGB))
        XCTAssertLessThan(corner.redComponent, 0.3)
    }

    func testMediaGeometryAndEmbeddedWordImage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = NSImage(size: NSSize(width: 400, height: 200), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        try XCTUnwrap(image.tiffRepresentation).write(to: directory.appendingPathComponent("photo.tiff"))
        let card = MediaCard(kind: .image, source: "photo.tiff", title: "Test & image", x: 0.5, y: 50, width: 200)
        let text = card.markdown + "\n" + String(repeating: "Words wrap around the picture. ", count: 80)
        let layout = DocumentExportLayout(markdown: text, sourceURL: directory.appendingPathComponent("Note.md"), mode: .light, source: nil)
        let view = try XCTUnwrap(layout.editor.mediaViews[card.id])
        XCTAssertEqual(view.frame.width, 200)
        XCTAssertEqual(view.frame.height, 100)
        XCTAssertEqual(view.frame.minY, 90)
        XCTAssertEqual(layout.editor.textContainer?.exclusionPaths.count, 1)
        let pdf = try XCTUnwrap(PDFDocument(data: layout.pdfData()))
        XCTAssertTrue(pdf.string?.contains("Words wrap") == true)
        let word = try WordDocumentExporter.data(layout: layout)
        let file = directory.appendingPathComponent("Note.docx")
        try word.write(to: file)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-t", file.path]
        process.standardOutput = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        // Stored ZIP entries can be examined directly without a test dependency.
        let xml = String(decoding: word, as: UTF8.self)
        XCTAssertTrue(xml.contains("word/media/image1.png"))
        XCTAssertTrue(xml.contains("<wp:anchor"))
        let wordScale = min(1, 1584 / max(layout.pageSize.width, layout.pageSize.height))
        XCTAssertTrue(xml.contains("<wp:posOffset>\(Int((90 * wordScale * 12700).rounded()))</wp:posOffset>"))
        XCTAssertTrue(xml.contains("Test &amp; image"))
        XCTAssertFalse(xml.contains("<w:background"))
        XCTAssertTrue(xml.contains("<w:t xml:space=\"preserve\">"))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("DayDream-export-verification")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try layout.pdfData().write(to: output.appendingPathComponent("layout.pdf"))
        try word.write(to: output.appendingPathComponent("layout.docx"))
    }

    func testExportRetainsHighlightAndDoesNotChangeLiveEditor() throws {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        let source = DayDreamTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), textContainer: container)
        let markdown = "A <span style=\"background-color:pink\">highlighted phrase</span> and **bold**."
        source.load(markdown: markdown)
        source.setSelectedRange(NSRange(location: 2, length: 5))
        let before = source.exportMarkdown()
        let selection = source.selectedRange()
        let layout = DocumentExportLayout(markdown: markdown, sourceURL: nil, mode: .dark, source: source)
        XCTAssertFalse(layout.editor.inlineHighlightFragments().isEmpty)
        XCTAssertTrue(PDFDocument(data: try layout.pdfData())?.string?.contains("highlighted phrase") == true)
        XCTAssertEqual(source.exportMarkdown(), before)
        XCTAssertEqual(source.selectedRange(), selection)
        XCTAssertEqual(layout.editor.zoomScale, source.zoomScale)
        XCTAssertEqual(layout.editor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
                       source.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    }

    func testPageBreakDoesNotBisectFittingMedia() throws {
        let card = MediaCard(kind: .image, source: "missing.png", title: "Missing", x: 0, y: 850, width: 240)
        let layout = DocumentExportLayout(markdown: card.markdown + "\n" + String(repeating: "Long document.\n", count: 100), sourceURL: nil, mode: .light, source: nil)
        let rect = try XCTUnwrap(layout.editor.mediaViews[card.id]).frame.offsetBy(dx: 0, dy: -layout.margin)
        for page in layout.pages.dropLast() {
            XCTAssertFalse(page.upperBound > rect.minY && page.upperBound < rect.maxY)
        }
    }
}
