import AppKit

/// AppKit's DOCX importer drops hyperlinks and outline levels. Restore those
/// standard XML attributes for the stored ZIP packages produced by our exporter.
/// Content is matched before applying metadata; no stale source text is imported.
enum WordImportSemantics {
    static func restore(_ attributed: NSAttributedString, package: Data) -> NSAttributedString {
        let parts = storedParts(package)
        guard let xml = parts["word/document.xml"] else { return attributed }
        let reader = SemanticReader()
        if let relationships = parts["word/_rels/document.xml.rels"] {
            let parser = XMLParser(data: relationships); parser.delegate = reader
            guard parser.parse() else { return attributed }
        }
        let parser = XMLParser(data: xml); parser.delegate = reader
        guard parser.parse() else { return attributed }
        let result = NSMutableAttributedString(attributedString: attributed)
        let string = result.string as NSString
        var location = 0
        for paragraph in reader.paragraphs {
            guard location < result.length else { break }
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            guard string.substring(with: range).trimmingCharacters(in: .newlines) == paragraph.text else { return attributed }
            if let level = paragraph.level {
                let style = (result.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                style.headerLevel = level
                result.addAttribute(.paragraphStyle, value: style, range: range)
            }
            for (linkRange, id) in paragraph.links {
                if let target = reader.links[id] {
                    result.addAttribute(.link, value: target, range: NSRange(location: location + linkRange.location, length: linkRange.length))
                }
            }
            location = NSMaxRange(range)
        }
        return result
    }

    private final class SemanticReader: NSObject, XMLParserDelegate {
        struct Paragraph {
            var text = ""
            var level: Int?
            var links: [(NSRange, String)] = []
        }
        var paragraphs: [Paragraph] = []
        var links: [String: String] = [:]
        private var current: Paragraph?
        private var inRun = false
        private var inText = false
        private var link: String?
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            switch name {
            case "Relationship":
                if let id = attributes["Id"], let target = attributes["Target"], attributes["Type"]?.hasSuffix("/hyperlink") == true { links[id] = target }
            case "w:p": current = Paragraph()
            case "w:r": inRun = true
            case "w:t": inText = true
            case "w:tab": if inRun { current?.text += "\t" }
            case "w:outlineLvl": current?.level = attributes["w:val"].flatMap(Int.init).map { $0 + 1 }
            case "w:hyperlink": link = attributes["r:id"]
            default: break
            }
        }
        func parser(_ parser: XMLParser, foundCharacters text: String) {
            guard inText, let value = current else { return }
            if let link { current?.links.append((NSRange(location: value.text.utf16.count, length: text.utf16.count), link)) }
            current?.text += text
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "w:p": if let current { paragraphs.append(current) }; current = nil
            case "w:r": inRun = false
            case "w:t": inText = false
            case "w:hyperlink": link = nil
            default: break
            }
        }
    }

    private static func storedParts(_ data: Data) -> [String: Data] {
        var result: [String: Data] = [:]
        func number(_ offset: Int, _ count: Int) -> Int {
            (0..<count).reduce(0) { $0 | (Int(data[offset + $1]) << ($1 * 8)) }
        }
        var offset = 0
        while offset + 30 <= data.count, number(offset, 4) == 0x04034b50 {
            guard number(offset + 6, 2) & 8 == 0, number(offset + 8, 2) == 0 else { return [:] }
            let size = number(offset + 18, 4), nameSize = number(offset + 26, 2), extraSize = number(offset + 28, 2)
            let start = offset + 30 + nameSize + extraSize
            guard start <= data.count, size <= data.count - start else { return [:] }
            let name = String(decoding: data[(offset + 30)..<(offset + 30 + nameSize)], as: UTF8.self)
            if name == "word/document.xml" || name == "word/_rels/document.xml.rels" { result[name] = data.subdata(in: start..<(start + size)) }
            offset = start + size
        }
        return result
    }
}
