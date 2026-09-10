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

    func exportPDF(_ markdown: String, to destination: URL, sourceURL: URL? = nil, mode: DocumentAppearance = .light) throws {
        let storage = NSTextStorage(attributedString: attributedWordDocument(from: markdown, sourceURL: sourceURL, mode: mode))
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { throw DocumentTransferError.destinationUnavailable }
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &page, [kCGPDFContextSubject as String: "DayDream " + mode.rawValue] as CFDictionary) else { throw DocumentTransferError.destinationUnavailable }
        var previousEnd = 0
        repeat {
            let container = NSTextContainer(containerSize: NSSize(width: 468, height: 648))
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            manager.ensureLayout(for: container)
            let range = manager.glyphRange(for: container)
            context.beginPDFPage(nil)
            context.setFillColor(mode.background.cgColor)
            context.fill(page)
            context.saveGState()
            context.translateBy(x: 72, y: 720)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            manager.drawBackground(forGlyphRange: range, at: .zero)
            manager.drawGlyphs(forGlyphRange: range, at: .zero)
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
            context.endPDFPage()
            let end = NSMaxRange(range)
            if end >= manager.numberOfGlyphs || end <= previousEnd { break }
            previousEnd = end
        } while true
        context.closePDF()
        try (data as Data).write(to: destination, options: .atomic)
    }

    func exportWord(_ markdown: String, to destination: URL, sourceURL: URL? = nil, mode: DocumentAppearance = .light) throws {
        let attributed = attributedWordDocument(from: markdown, sourceURL: sourceURL, mode: mode)
        let attributes: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.officeOpenXML,
            .backgroundColor: mode.background,
            .paperSize: NSSize(width: 612, height: 792),
            .leftMargin: 72,
            .rightMargin: 72,
            .topMargin: 72,
            .bottomMargin: 72
        ]
        let data = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: attributes
        )
        try data.write(to: destination, options: .atomic)
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
        return markdown(from: attributed)
    }

    private func attributedWordDocument(from markdown: String, sourceURL: URL?, mode: DocumentAppearance = .light) -> NSAttributedString {
        let document = MarkdownDocumentCodec.parse(markdown)
        let result = NSMutableAttributedString()
        var orderedNumber = 0

        for (index, block) in document.blocks.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n")) }

            if let card = MediaCard.parse(block.text) {
                if card.kind == .image, let url = card.resolvedURL(documentURL: sourceURL), url.isFileURL,
                   let image = NSImage(contentsOf: url) {
                    let attachment = NSTextAttachment()
                    attachment.image = image
                    let width = min(440, image.size.width, 600 * image.size.width / max(1, image.size.height))
                    attachment.bounds = NSRect(x: 0, y: 0, width: width, height: width * image.size.height / max(1, image.size.width))
                    result.append(NSAttributedString(attachment: attachment))
                } else {
                    result.append(NSAttributedString(string: "\(card.title) (\(card.source))", attributes: [.font: NSFont.systemFont(ofSize: 11.5)]))
                }
                continue
            }
            let prefix: String
            let font: NSFont
            switch block.kind {
            case .divider:
                orderedNumber = 0
                prefix = "────────────────"
                font = .systemFont(ofSize: 11.5)
            case .body:
                orderedNumber = 0
                prefix = ""
                font = .systemFont(ofSize: 11.5)
            case let .heading(level):
                orderedNumber = 0
                prefix = ""
                font = .systemFont(ofSize: headingSize(level), weight: .bold)
            case .bullet:
                orderedNumber = 0
                prefix = block.indentation + "• "
                font = .systemFont(ofSize: 11.5)
            case .numbered:
                orderedNumber = orderedNumber == 0 ? block.orderedStart : orderedNumber + 1
                prefix = block.indentation + "\(orderedNumber). "
                font = .systemFont(ofSize: 11.5)
            case let .todo(checked):
                orderedNumber = 0
                prefix = block.indentation + (checked ? "☒ " : "☐ ")
                font = .systemFont(ofSize: 11.5)
            case .translation:
                orderedNumber = 0
                prefix = ""
                font = .systemFont(ofSize: 11.5)
            case .quote:
                orderedNumber = 0
                prefix = "› "
                font = .systemFont(ofSize: 11.5)
            case .code:
                orderedNumber = 0
                prefix = ""
                font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
            }

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.paragraphSpacing = block.kind.isList ? 2 : 7
            paragraphStyle.lineSpacing = 1.5
            if block.kind.isList {
                paragraphStyle.firstLineHeadIndent = 0
                paragraphStyle.headIndent = 22
            }

            let lineStart = result.length
            result.append(NSAttributedString(
                string: prefix,
                attributes: [.font: font, .foregroundColor: mode == .dark ? NSColor.white : NSColor.black]
            ))
            let parsed: (plain: String, runs: [InlineRun])
            if case .code = block.kind { parsed = (block.text, []) }
            else { parsed = InlineMarkdown.parse(block.text) }
            let body = NSMutableAttributedString(
                string: parsed.plain,
                attributes: [.font: font, .foregroundColor: mode == .dark ? NSColor.white : NSColor.black]
            )
            for run in parsed.runs where NSMaxRange(run.range) <= body.length {
                apply(run.style, to: body, range: run.range, baseFont: font, appearance: mode.appearance)
            }
            for run in parsed.runs.reversed() {
                guard let destination = run.style.linkDestination,
                      NSMaxRange(run.range) <= body.length else { continue }
                body.insert(
                    NSAttributedString(
                        string: " (\(destination))",
                        attributes: [.font: font, .foregroundColor: mode == .dark ? NSColor.lightGray : NSColor.darkGray]
                    ),
                    at: NSMaxRange(run.range)
                )
            }
            result.append(body)
            result.addAttribute(
                .paragraphStyle,
                value: paragraphStyle,
                range: NSRange(location: lineStart, length: result.length - lineStart)
            )
        }
        return result
    }

    private func apply(
        _ style: InlineStyle,
        to text: NSMutableAttributedString,
        range: NSRange,
        baseFont: NSFont,
        appearance: NSAppearance
    ) {
        var font = style.fontFamily.flatMap { NSFont(name: $0, size: baseFont.pointSize) } ?? baseFont
        var traits: NSFontTraitMask = []
        if style.bold { traits.insert(.boldFontMask) }
        if style.italic { traits.insert(.italicFontMask) }
        if style.code {
            font = .monospacedSystemFont(ofSize: baseFont.pointSize, weight: style.bold ? .bold : .regular)
        }
        if !traits.isEmpty, let converted = NSFontManager.shared.convert(font, toHaveTrait: traits) as NSFont? {
            font = converted
        }
        text.addAttribute(.font, value: font, range: range)
        if style.underline { text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
        if style.strikethrough { text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
        if let destination = style.linkDestination, let url = URL(string: destination) {
            text.addAttributes([.link: url, .foregroundColor: NSColor.systemBlue], range: range)
        }
        if let preset = style.textColor.flatMap(StyleColorPreset.init(rawValue:)) {
            text.addAttribute(
                .foregroundColor,
                value: DayDreamTheme.inlineTextColor(preset.rawValue, for: appearance),
                range: range
            )
        }
        if let preset = style.highlight.flatMap(StyleColorPreset.init(rawValue:)) {
            text.addAttribute(
                .backgroundColor,
                value: DayDreamTheme.inlineHighlightColor(preset.rawValue, for: appearance),
                range: range
            )
        }
        if style.strikethrough, range.length > 0,
           let color = text.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor {
            text.addAttribute(.foregroundColor, value: color.withAlphaComponent(color.alphaComponent * 0.45), range: range)
        }
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
        let trimmed = String(text.dropFirst(leadingCount))
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

        let font = range.length > 0 ? attributed.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont : nil
        if let font, font.pointSize >= 13 {
            let level: Int
            switch font.pointSize {
            case 21...: level = 1
            case 17...: level = 2
            case 14.5...: level = 3
            default: level = 4
            }
            return (String(repeating: "#", count: level) + " ", 0)
        }
        return ("", 0)
    }

    private func inlineMarkdown(from attributed: NSAttributedString) -> String {
        guard attributed.length > 0 else { return "" }
        var output = ""
        let firstFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let isHeading = (firstFont?.pointSize ?? 0) >= 13
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

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 24
        case 2: return 20
        case 3: return 16
        default: return 13.5
        }
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
