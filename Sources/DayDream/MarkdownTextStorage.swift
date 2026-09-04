import AppKit

extension NSAttributedString.Key {
    static let dayDreamBlockKind = NSAttributedString.Key("DayDreamBlockKind")
    /// 行内样式语义键：粗体 / 斜体 / 文字颜色预设名 / 高亮颜色预设名。
    static let dayDreamBold = NSAttributedString.Key("DayDreamBold")
    static let dayDreamItalic = NSAttributedString.Key("DayDreamItalic")
    static let dayDreamTextColor = NSAttributedString.Key("DayDreamTextColor")
    static let dayDreamHighlight = NSAttributedString.Key("DayDreamHighlight")
}

enum MarkdownTextStorage {
    static func attributedString(
        from document: MarkdownDocument,
        appearance: NSAppearance,
        scale: CGFloat
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let blocks = document.blocks.isEmpty
            ? [MarkdownBlock(kind: .body, text: "")]
            : document.blocks

        for (index, block) in blocks.enumerated() {
            var attributes = DayDreamTheme.textAttributes(
                for: appearance,
                scale: scale,
                blockKind: block.kind
            )
            attributes[.dayDreamBlockKind] = block.kind

            // 行内样式：解析 **粗体** / *斜体* / <span style> 并叠加视觉属性。
            let inline = InlineMarkdown.parse(block.text)
            let content = NSMutableAttributedString(
                string: inline.plain + (index < blocks.count - 1 ? "\n" : ""),
                attributes: attributes
            )
            for run in inline.runs {
                content.addAttributes(
                    DayDreamTheme.inlineStyledAttributes(
                        base: attributes,
                        bold: run.style.bold,
                        italic: run.style.italic,
                        textColorName: run.style.textColor,
                        highlightName: run.style.highlight,
                        for: appearance
                    ),
                    range: run.range
                )
            }
            result.append(content)
        }
        return result
    }

    static func document(
        from storage: NSAttributedString,
        fallbackKind: MarkdownBlockKind
    ) -> MarkdownDocument {
        let value = storage.string as NSString
        var blocks: [MarkdownBlock] = []
        var location = 0

        while location < value.length {
            let paragraphRange = value.paragraphRange(
                for: NSRange(location: location, length: 0)
            )
            let kind = storage.attribute(
                .dayDreamBlockKind,
                at: location,
                effectiveRange: nil
            ) as? MarkdownBlockKind ?? .body

            // 去掉段落末尾换行，序列化行内样式（**粗体** / span 等）。
            var contentRange = paragraphRange
            if contentRange.length > 0,
               value.character(at: NSMaxRange(contentRange) - 1) == 10 { // "\n"
                contentRange.length -= 1
            }
            let line = contentRange.length > 0
                ? InlineMarkdown.serialize(storage.attributedSubstring(from: contentRange))
                : ""
            blocks.append(MarkdownBlock(kind: kind, text: line))

            let next = NSMaxRange(paragraphRange)
            guard next > location else { break }
            location = next
        }

        // 空文档或文末幻影行（字符串以换行结尾）→ 追加一个空块。
        if value.length == 0
            || value.character(at: value.length - 1) == 10 {
            blocks.append(MarkdownBlock(kind: fallbackKind, text: ""))
        }
        return MarkdownDocument(blocks: blocks)
    }
}
