import AppKit
import Foundation

enum DocumentTransferError: LocalizedError, Equatable {
    case unsupportedFormat
    case invalidMarkdownEncoding
    case unreadableWordDocument
    case destinationUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return L10n.t("仅支持 Markdown 和 Word (.docx) 文件。", "Only Markdown and Word (.docx) files are supported.")
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
        let destination = uniqueURL(in: directory, baseName: baseName, pathExtension: "md")

        switch fileExtension {
        case "md", "markdown":
            let data = try Data(contentsOf: source)
            guard String(data: data, encoding: .utf8) != nil else {
                throw DocumentTransferError.invalidMarkdownEncoding
            }
            try MediaResources.copyAlongsideDocument(from: source, to: destination)
            try data.write(to: destination, options: .atomic)
        case "docx":
            let markdown = try markdown(fromWordDocument: source)
            try Data(markdown.utf8).write(to: destination, options: .atomic)
        default:
            throw DocumentTransferError.unsupportedFormat
        }
        return destination
    }

    func exportMarkdown(_ markdown: String, to destination: URL, sourceURL: URL? = nil) throws {
        if let sourceURL { try MediaResources.copyAlongsideDocument(from: sourceURL, to: destination, markdown: markdown) }
        try Data(markdown.utf8).write(to: destination, options: .atomic)
    }

    func exportWord(_ markdown: String, to destination: URL, sourceURL: URL? = nil) throws {
        let attributed = attributedWordDocument(from: markdown, sourceURL: sourceURL)
        let attributes: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.officeOpenXML,
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

    private func attributedWordDocument(from markdown: String, sourceURL: URL?) -> NSAttributedString {
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
                    let width = min(440, image.size.width)
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
                attributes: [.font: font, .foregroundColor: NSColor.black]
            ))
            let parsed = InlineMarkdown.parse(block.text)
            let body = NSMutableAttributedString(
                string: parsed.plain,
                attributes: [.font: font, .foregroundColor: NSColor.black]
            )
            for run in parsed.runs where NSMaxRange(run.range) <= body.length {
                apply(run.style, to: body, range: run.range, baseFont: font)
            }
            for run in parsed.runs.reversed() {
                guard let destination = run.style.linkDestination,
                      NSMaxRange(run.range) <= body.length else { continue }
                body.insert(
                    NSAttributedString(
                        string: " (\(destination))",
                        attributes: [.font: font, .foregroundColor: NSColor.darkGray]
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
        baseFont: NSFont
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
        if let destination = style.linkDestination, let url = URL(string: destination) {
            text.addAttributes([.link: url, .foregroundColor: NSColor.systemBlue], range: range)
        }
        if let preset = style.textColor.flatMap(StyleColorPreset.init(rawValue:)) {
            text.addAttribute(
                .foregroundColor,
                value: DayDreamTheme.inlineTextColor(preset.rawValue, for: NSApp.effectiveAppearance),
                range: range
            )
        }
        if let preset = style.highlight.flatMap(StyleColorPreset.init(rawValue:)) {
            text.addAttribute(
                .backgroundColor,
                value: DayDreamTheme.inlineHighlightColor(preset.rawValue, for: NSApp.effectiveAppearance),
                range: range
            )
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
