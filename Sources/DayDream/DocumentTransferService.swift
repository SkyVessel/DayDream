import AppKit
import Foundation
import PDFKit

enum DocumentTransferError: LocalizedError, Equatable {
    case unsupportedFormat
    case invalidMarkdownEncoding
    case unreadablePDF
    case unreadableWordDocument
    case destinationUnavailable

    var errorDescription: String? {
        switch self {
        case .unreadablePDF:
            return L10n.t("无法读取这个 PDF 文件。", "The PDF file could not be read.")
        case .unsupportedFormat:
            return L10n.t("仅支持 Markdown、PDF 和 Word (.docx) 文件。", "Only Markdown, PDF and Word (.docx) files are supported.")
        case .invalidMarkdownEncoding:
            return L10n.t("Markdown 文件不是有效的 UTF-8 文本。", "The Markdown file is not valid UTF-8 text.")
        case .unreadableWordDocument:
            return L10n.t("无法读取这个 Word 文档。", "The Word document could not be read.")
        case .destinationUnavailable:
            return L10n.t("目标文件夹不可用。", "The destination folder is unavailable.")
        }
    }
}

/// DayDream 与外部 Markdown / Word 文档之间的可预期、非破坏性转换。
final class DocumentTransferService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @discardableResult
    func importDocument(from source: URL, into directory: URL) throws -> URL {
        guard isDirectory(directory) else { throw DocumentTransferError.destinationUnavailable }
        let fileExtension = source.pathExtension.lowercased()
        let baseName = source.deletingPathExtension().lastPathComponent
        let destination = uniqueURL(in: directory, baseName: baseName, pathExtension: fileExtension == "pdf" ? "pdf" : "md")

        switch fileExtension {
        case "md", "markdown":
            let data = try Data(contentsOf: source)
            guard String(data: data, encoding: .utf8) != nil else {
                throw DocumentTransferError.invalidMarkdownEncoding
            }
            try MediaResources.copyAlongsideDocument(from: source, to: destination)
            try data.write(to: destination, options: .atomic)
        case "pdf":
            guard PDFDocument(url: source) != nil else { throw DocumentTransferError.unreadablePDF }
            try fileManager.copyItem(at: source, to: destination)
        case "docx":
            let markdown = try markdown(fromWordDocument: source)
            try Data(markdown.utf8).write(to: destination, options: .atomic)
        default:
            throw DocumentTransferError.unsupportedFormat
        }
        return destination
    }

    func exportPDFDocument(_ source: URL, to destination: URL, mode: DocumentAppearance) throws {
        guard let pdf = PDFDocument(url: source) else { throw DocumentTransferError.unreadablePDF }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { throw DocumentTransferError.destinationUnavailable }
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, [kCGPDFContextSubject as String: "DayDream " + mode.rawValue] as CFDictionary) else { throw DocumentTransferError.destinationUnavailable }
        let wasDark = pdf.documentAttributes?[PDFDocumentAttribute.subjectAttribute] as? String == "DayDream dark"
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            var bounds = page.bounds(for: .mediaBox)
            let pageInfo = [kCGPDFContextMediaBox as String: NSData(bytes: &bounds, length: MemoryLayout<CGRect>.size)] as CFDictionary
            context.beginPDFPage(pageInfo)
            context.setFillColor(NSColor.white.cgColor); context.fill(bounds)
            page.draw(with: .mediaBox, to: context)
            if (mode == .dark) != wasDark {
                context.setBlendMode(.difference)
                context.setFillColor(NSColor.white.cgColor); context.fill(bounds)
                context.setBlendMode(.normal)
            }
            context.endPDFPage()
        }
        context.closePDF()
        try (data as Data).write(to: destination, options: .atomic)
    }

    func exportMarkdown(_ markdown: String, to destination: URL, sourceURL: URL? = nil) throws {
        if let sourceURL { try MediaResources.copyAlongsideDocument(from: sourceURL, to: destination, markdown: markdown) }
        try Data(markdown.utf8).write(to: destination, options: .atomic)
    }

    @MainActor
    func exportPDF(_ markdown: String, to destination: URL, sourceURL: URL? = nil, mode: DocumentAppearance = .light, editor: DayDreamTextView? = nil) throws {
        let layout = DocumentExportLayout(markdown: markdown, sourceURL: sourceURL, mode: mode, source: editor)
        try layout.pdfData().write(to: destination, options: .atomic)
    }

    @MainActor
    func exportWord(_ markdown: String, to destination: URL, sourceURL: URL? = nil, mode: DocumentAppearance = .light, editor: DayDreamTextView? = nil) throws {
        let layout = DocumentExportLayout(markdown: markdown, sourceURL: sourceURL, mode: .light, source: editor)
        try WordDocumentExporter.data(layout: layout).write(to: destination, options: .atomic)
    }

    func markdown(fromWordDocument url: URL) throws -> String {
        var documentAttributes: NSDictionary?
        guard let attributed = try? NSAttributedString(
            url: url,
            options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
            documentAttributes: &documentAttributes
        ) else {
            throw DocumentTransferError.unreadableWordDocument
        }
        return markdown(from: WordImportSemantics.restore(attributed, package: try Data(contentsOf: url)))
    }

    private func markdown(from attributed: NSAttributedString) -> String {
        let source = attributed.string as NSString
        var lines: [String] = []
        var location = 0

        while location < source.length {
            let paragraphRange = source.paragraphRange(for: NSRange(location: location, length: 0))
            var contentRange = paragraphRange
            while contentRange.length > 0,
                  CharacterSet.newlines.contains(UnicodeScalar(source.character(at: NSMaxRange(contentRange) - 1))!) {
                contentRange.length -= 1
            }
            let plain = source.substring(with: contentRange)
            let prefix = markdownPrefix(for: plain, attributed: attributed, range: contentRange)
            let bodyOffset = prefix.removedUTF16Length
            let safeOffset = min(bodyOffset, contentRange.length)
            let bodyRange = NSRange(
                location: contentRange.location + safeOffset,
                length: contentRange.length - safeOffset
            )
            let body = inlineMarkdown(from: attributed.attributedSubstring(from: bodyRange))
            lines.append(prefix.markdown + body)
            location = NSMaxRange(paragraphRange)
        }

        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    private func markdownPrefix(
        for text: String,
        attributed: NSAttributedString,
        range: NSRange
    ) -> (markdown: String, removedUTF16Length: Int) {
        let leadingCount = text.prefix(while: { $0 == " " || $0 == "\t" }).utf16.count
        let trimmed = String(text.dropFirst(leadingCount)).replacingOccurrences(of: "\t", with: " ")
        let indentation = String(text.prefix(leadingCount))

        if trimmed.hasPrefix("• ") { return (indentation + "- ", leadingCount + 2) }
        if trimmed.hasPrefix("☐ ") { return (indentation + "- [ ] ", leadingCount + 2) }
        if trimmed.hasPrefix("☒ ") || trimmed.hasPrefix("☑ ") {
            return (indentation + "- [x] ", leadingCount + 2)
        }
        if trimmed.hasPrefix("› ") { return ("> ", leadingCount + 2) }
        if let ordered = trimmed.range(of: #"^\d+\. "#, options: .regularExpression) {
            let marker = String(trimmed[ordered])
            return (indentation + marker, leadingCount + marker.utf16.count)
        }

        let level = range.length > 0 ? (attributed.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel ?? 0 : 0
        if level > 0 { return (String(repeating: "#", count: min(6, level)) + " ", 0) }
        return ("", 0)
    }

    private func inlineMarkdown(from attributed: NSAttributedString) -> String {
        guard attributed.length > 0 else { return "" }
        var output = ""
        let isHeading = ((attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel ?? 0) > 0
        attributed.enumerateAttributes(
            in: NSRange(location: 0, length: attributed.length),
            options: []
        ) { attributes, range, _ in
            var text = (attributed.string as NSString).substring(with: range)
            guard !text.isEmpty else { return }
            let font = attributes[.font] as? NSFont
            let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
            let bold = !isHeading && traits.contains(.boldFontMask)
            let italic = traits.contains(.italicFontMask)
            let monospaced = traits.contains(.fixedPitchFontMask)
            if monospaced { text = "`\(text)`" }
            else if bold && italic { text = "***\(text)***" }
            else if bold { text = "**\(text)**" }
            else if italic { text = "*\(text)*" }
            if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { text = "~~" + text + "~~" }
            if (attributes[.underlineStyle] as? Int ?? 0) != 0 { text = "<u>" + text + "</u>" }
            if let link = attributes[.link] {
                let destination = (link as? URL)?.absoluteString ?? String(describing: link)
                text = "[\(text)](\(destination))"
            }
            output += text
        }
        let pattern = #"([^\s()]+) \((https?://[^\s)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return output }
        let fullRange = NSRange(location: 0, length: (output as NSString).length)
        return regex.stringByReplacingMatches(
            in: output,
            range: fullRange,
            withTemplate: "[$1]($2)"
        )
    }

    private func isDirectory(_ url: URL) -> Bool {
        var value: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &value) && value.boolValue
    }

    private func uniqueURL(in directory: URL, baseName: String, pathExtension: String) -> URL {
        var suffix = 1
        while true {
            let name = suffix == 1 ? baseName : "\(baseName) \(suffix)"
            let candidate = directory.appending(path: "\(name).\(pathExtension)")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            suffix += 1
        }
    }
}
