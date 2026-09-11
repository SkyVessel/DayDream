import AppKit

/// Editable runs with explicit visual line breaks, plus page-positioned images.
/// Word and TextKit use different wrapping engines; recording the resolved line
/// fragments avoids asking Word to invent a second, conflicting wrap layout.
@MainActor
enum WordDocumentExporter {
    private struct Fragment {
        let rect: NSRect
        let range: NSRange
    }

    static func data(layout: DocumentExportLayout) throws -> Data {
        // Keep custom pages within Word's 22-inch size limit, scaling the
        // entire composition uniformly rather than changing its wrapping.
        let outputScale = min(1, 1584 / max(layout.pageSize.width, layout.pageSize.height))
        func twips(_ value: CGFloat) -> Int { Int((value * outputScale * 20).rounded()) }
        let editor = layout.editor
        guard let manager = editor.layoutManager, let storage = editor.textStorage else {
            throw DocumentTransferError.destinationUnavailable
        }
        var fragments: [Fragment] = []
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { rect, used, _, glyphs, _ in
            fragments.append(Fragment(rect: NSRect(x: used.minX, y: rect.minY, width: used.width, height: rect.height), range: manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)))
        }
        let decorations = BlockDecorationLayout.decorations(in: editor, textContainerOrigin: editor.textContainerOrigin, scale: editor.zoomScale)
        var entries: [(String, Data)] = []
        var relationships = ""
        var links: [String: String] = [:]
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let value else { return }
            let url = (value as? URL)?.absoluteString ?? String(describing: value)
            if links[url] == nil {
                let id = "link\(links.count + 1)"
                links[url] = id
                relationships += "<Relationship Id=\"\(id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(escape(url))\" TargetMode=\"External\"/>"
            }
        }
        var body = ""
        var imageID = 0
        for (pageIndex, page) in layout.pages.enumerated() {
            let pageFragments = fragments.filter { $0.rect.minY >= page.lowerBound - 0.01 && $0.rect.minY < page.upperBound - 0.01 }
            var drawings = ""
            for media in editor.mediaViews.values.sorted(by: { $0.card.id.uuidString < $1.card.id.uuidString }) {
                let rect = media.frame.offsetBy(dx: 0, dy: -layout.margin)
                guard rect.maxY > page.lowerBound, rect.minY < page.upperBound else { continue }
                imageID += 1
                let visible = rect.intersection(NSRect(x: 0, y: page.lowerBound, width: layout.pageSize.width, height: page.upperBound - page.lowerBound))
                let image: NSImage
                if media.card.kind == .image, let preview = media.exportPreview {
                    image = preview
                } else {
                    // Preserve video/link cards as their visible cover, never silently drop them.
                    image = NSImage(size: media.bounds.size, flipped: true) { _ in
                        media.draw(media.bounds)
                        return true
                    }
                }
                guard let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw DocumentTransferError.destinationUnavailable
                }
                entries.append(("word/media/image\(imageID).png", png))
                relationships += "<Relationship Id=\"img\(imageID)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/image\(imageID).png\"/>"
                let topCrop = Int(max(0, visible.minY - rect.minY) / rect.height * 100000)
                let bottomCrop = Int(max(0, rect.maxY - visible.maxY) / rect.height * 100000)
                drawings += drawing(id: imageID, title: media.card.title, rect: NSRect(x: visible.minX * outputScale, y: (layout.margin + visible.minY - page.lowerBound) * outputScale, width: visible.width * outputScale, height: visible.height * outputScale), topCrop: topCrop, bottomCrop: bottomCrop)
            }
            var cursor: CGFloat = 0
            var index = 0
            var first = true
            while index < pageFragments.count {
                let y = pageFragments[index].rect.minY
                var line: [Fragment] = []
                while index < pageFragments.count && abs(pageFragments[index].rect.minY - y) < 0.5 {
                    line.append(pageFragments[index]); index += 1
                }
                line.sort { $0.rect.minX < $1.rect.minX }
                let height = line.map(\.rect.height).max() ?? 20
                let before = max(0, y - page.lowerBound - cursor)
                let nextY = index < pageFragments.count ? pageFragments[index].rect.minY : y + height
                let advance = max(height, nextY - y)
                var stops: [(CGFloat, String)] = []
                for fragment in line {
                    if let marker = decorations.first(where: { $0.characterRange.location == fragment.range.location }) {
                        var label = marker.label
                        if case let .todo(checked) = marker.kind { label = checked ? "☒" : "☐" }
                        if marker.kind == .quote { label = "│" }
                        if marker.kind == .divider { label = "────────────────" }
                        if let label {
                            stops.append((marker.markerRect.minX, run(NSAttributedString(string: label, attributes: [.font: BlockDecorationLayout.markerFont(scale: editor.zoomScale)]), scale: outputScale)))
                        }
                    }
                    let text = storage.attributedSubstring(from: fragment.range)
                    stops.append((editor.textContainerOrigin.x + fragment.rect.minX, run(text, links: links, scale: outputScale)))
                }
                stops.sort { $0.0 < $1.0 }
                let tabs = stops.map { "<w:tab w:val=\"left\" w:pos=\"\(twips($0.0))\"/>" }.joined()
                let content = stops.enumerated().map { ($0.offset == 0 ? "" : "<w:r><w:tab/></w:r>") + $0.element.1 }.joined()
                var properties = "<w:ind w:left=\"\(twips(stops.first?.0 ?? 0))\"/><w:tabs>\(tabs)</w:tabs><w:spacing w:before=\"\(twips(before))\" w:after=\"0\" w:line=\"\(twips(advance))\" w:lineRule=\"exact\"/><w:contextualSpacing w:val=\"0\"/><w:widowControl w:val=\"0\"/>"
                if first && pageIndex > 0 { properties += "<w:pageBreakBefore/>" }
                // Preserve semantic heading levels so importing does not classify large body fonts as headings.
                if let firstRange = line.first?.range, firstRange.location < storage.length,
                   case let .heading(level) = storage.attribute(.dayDreamBlockKind, at: firstRange.location, effectiveRange: nil) as? MarkdownBlockKind {
                    properties += "<w:outlineLvl w:val=\"\(max(0, level - 1))\"/>"
                }
                body += "<w:p><w:pPr>\(properties)</w:pPr>\(first ? drawings : "")\(content)</w:p>"
                first = false
                cursor = y - page.lowerBound + advance
            }
            if first {
                body += "<w:p><w:pPr>\(pageIndex > 0 ? "<w:pageBreakBefore/>" : "")<w:spacing w:line=\"20\" w:lineRule=\"exact\"/></w:pPr>\(drawings)</w:p>"
            }
        }
        body += "<w:sectPr><w:pgSz w:w=\"\(twips(layout.pageSize.width))\" w:h=\"\(twips(layout.pageSize.height))\"/><w:pgMar w:top=\"\(twips(layout.margin))\" w:bottom=\"\(twips(layout.margin))\" w:left=\"0\" w:right=\"0\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr>"
        let document = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><w:body>\(body)</w:body></w:document>"
        entries += [
            ("word/document.xml", Data(document.utf8)),
            ("word/_rels/document.xml.rels", Data("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(relationships)</Relationships>".utf8)),
            ("_rels/.rels", Data("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"document\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>".utf8)),
            ("[Content_Types].xml", Data("<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"png\" ContentType=\"image/png\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>".utf8))
        ]
        return ExportZIP.data(entries: entries)
    }

    private static func twips(_ value: CGFloat) -> Int { Int((value * 20).rounded()) }
    private static func emu(_ value: CGFloat) -> Int { Int((value * 12700).rounded()) }
    private static func escape(_ value: String) -> String {
        String(value.unicodeScalars.filter { $0.value >= 32 || $0 == "\t" || $0 == "\n" || $0 == "\r" })
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    private static func run(_ text: NSAttributedString, links: [String: String] = [:], scale: CGFloat = 1) -> String {
        var xml = ""
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
            let value = (text.string as NSString).substring(with: range).replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\u{FFFC}", with: "")
            guard !value.isEmpty else { return }
            let font = attrs[.font] as? NSFont ?? DayDreamTheme.font
            let traits = NSFontManager.shared.traits(of: font)
            let name = font.familyName ?? font.fontName
            let family = escape(name.hasPrefix(".") ? "Helvetica Neue" : name)
            var props = "<w:rFonts w:ascii=\"\(family)\" w:hAnsi=\"\(family)\" w:eastAsia=\"\(family)\"/><w:sz w:val=\"\(Int((font.pointSize * scale * 2).rounded()))\"/>"
            if traits.contains(.boldFontMask) { props += "<w:b/>" }
            if traits.contains(.italicFontMask) { props += "<w:i/>" }
            if (attrs[.underlineStyle] as? Int ?? 0) != 0 { props += "<w:u w:val=\"single\"/>" }
            if (attrs[.strikethroughStyle] as? Int ?? 0) != 0 { props += "<w:strike/>" }
            if let kern = attrs[.kern] as? CGFloat { props += "<w:spacing w:val=\"\(twips(kern * scale))\"/>" }
            if let color = (attrs[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB) {
                let hex = String(format: "%02X%02X%02X", Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255))
                props += "<w:color w:val=\"\(hex)\"/>"
            }
            if let highlight = attrs[.dayDreamHighlight] as? String,
               let color = DayDreamTheme.inlineHighlightColor(highlight, for: DocumentAppearance.light.appearance).usingColorSpace(.sRGB) {
                let channels = [color.redComponent, color.greenComponent, color.blueComponent].map { Int(($0 * color.alphaComponent + 1 - color.alphaComponent) * 255) }
                props += "<w:shd w:val=\"clear\" w:fill=\"\(String(format: "%02X%02X%02X", channels[0], channels[1], channels[2]))\"/>"
            }
            var content = "<w:r><w:rPr>\(props)</w:rPr><w:t xml:space=\"preserve\">\(escape(value))</w:t></w:r>"
            if let link = attrs[.link] {
                let url = (link as? URL)?.absoluteString ?? String(describing: link)
                if let id = links[url] { content = "<w:hyperlink r:id=\"\(id)\">\(content)</w:hyperlink>" }
            }
            xml += content
        }
        return xml
    }
    private static func drawing(id: Int, title: String, rect: NSRect, topCrop: Int, bottomCrop: Int) -> String {
        """
        <w:r><w:drawing><wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="\(id)" behindDoc="0" locked="0" layoutInCell="1" allowOverlap="1"><wp:simplePos x="0" y="0"/><wp:positionH relativeFrom="page"><wp:posOffset>\(emu(rect.minX))</wp:posOffset></wp:positionH><wp:positionV relativeFrom="page"><wp:posOffset>\(emu(rect.minY))</wp:posOffset></wp:positionV><wp:extent cx="\(emu(rect.width))" cy="\(emu(rect.height))"/><wp:wrapNone/><wp:docPr id="\(id)" name="Image \(id)" descr="\(escape(title))"/><wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="\(id)" name="\(escape(title))"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="img\(id)"/><a:srcRect t="\(topCrop)" b="\(bottomCrop)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(emu(rect.width))" cy="\(emu(rect.height))"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r>
        """
    }
}

/// Small, uncompressed ZIP writer for OOXML. PNG payloads are already compressed;
/// no shell process, external dependency or sandbox escape is needed.
enum ExportZIP {
    static func data(entries: [(String, Data)]) -> Data {
        var result = Data(), directory = Data()
        func u16(_ n: Int) -> Data { var v = UInt16(n).littleEndian; return Data(bytes: &v, count: 2) }
        func u32(_ n: UInt32) -> Data { var v = n.littleEndian; return Data(bytes: &v, count: 4) }
        for (path, data) in entries {
            let name = Data(path.utf8), offset = UInt32(result.count), size = UInt32(data.count)
            var crc: UInt32 = 0xffffffff
            for byte in data {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) }
            }
            crc ^= 0xffffffff
            result += u32(0x04034b50)
            result += u16(20)
            result += u16(0)
            result += u16(0)
            result += u16(0)
            result += u16(33)
            result += u32(crc)
            result += u32(size)
            result += u32(size)
            result += u16(name.count)
            result += u16(0)
            result += name
            result += data
            directory += u32(0x02014b50)
            directory += u16(20)
            directory += u16(20)
            directory += u16(0)
            directory += u16(0)
            directory += u16(0)
            directory += u16(33)
            directory += u32(crc)
            directory += u32(size)
            directory += u32(size)
            directory += u16(name.count)
            directory += u16(0)
            directory += u16(0)
            directory += u16(0)
            directory += u16(0)
            directory += u32(0)
            directory += u32(offset)
            directory += name
        }
        let offset = UInt32(result.count)
        result += directory
        result += u32(0x06054b50)
        result += u16(0)
        result += u16(0)
        result += u16(entries.count)
        result += u16(entries.count)
        result += u32(UInt32(directory.count))
        result += u32(offset)
        result += u16(0)
        return result
    }
}
