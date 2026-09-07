import AppKit

extension NSAttributedString.Key {
    static let dayDreamOrderedStart = NSAttributedString.Key("DayDreamOrderedStart")
    static let dayDreamFontFamily = NSAttributedString.Key("DayDreamFontFamily")
    static let dayDreamBlockKind = NSAttributedString.Key("DayDreamBlockKind")
    static let dayDreamListIndentation = NSAttributedString.Key("DayDreamListIndentation")
    /// 行内样式语义键：粗体 / 斜体 / 文字颜色预设名 / 高亮颜色预设名。
    static let dayDreamBold = NSAttributedString.Key("DayDreamBold")
    static let dayDreamItalic = NSAttributedString.Key("DayDreamItalic")
    static let dayDreamInlineCode = NSAttributedString.Key("DayDreamInlineCode")
    static let dayDreamLink = NSAttributedString.Key("DayDreamLink")
    static let dayDreamImage = NSAttributedString.Key("DayDreamImage")
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
                blockKind: block.kind,
                listIndentation: block.indentation
            )
            attributes[.dayDreamBlockKind] = block.kind
            attributes[.dayDreamListIndentation] = block.indentation
            attributes[.dayDreamOrderedStart] = block.orderedStart

            if block.kind == .body, let card = MediaCard.parse(block.text) {
                let media = NSMutableAttributedString(string: "\u{FFFC}", attributes: attributes)
                media.addAttributes(DayDreamTextView.mediaAnchorAttributes(card), range: NSRange(location: 0, length: 1))
                if index < blocks.count - 1 { media.append(NSAttributedString(string: "\n", attributes: attributes)) }
                result.append(media)
                continue
            }

            // 代码块内容必须逐字显示；其他段落再解析行内 Markdown。
            let inline = if case .code = block.kind {
                (plain: block.text, runs: [InlineRun]())
            } else {
                InlineMarkdown.parse(block.text)
            }
            let content = NSMutableAttributedString(
                string: inline.plain + (index < blocks.count - 1 ? "\n" : ""),
                attributes: attributes
            )
            for run in inline.runs {
                if let card = run.style.media {
                    content.addAttributes(DayDreamTextView.mediaAnchorAttributes(card), range: run.range)
                    continue
                }
                content.addAttributes(
                    DayDreamTheme.inlineStyledAttributes(
                        base: attributes,
                        bold: run.style.bold,
                        italic: run.style.italic,
                        inlineCode: run.style.code,
                        linkDestination: run.style.linkDestination,
                        imageDestination: run.style.imageDestination,
                        textColorName: run.style.textColor,
                        highlightName: run.style.highlight,
                        fontFamily: run.style.fontFamily,
                        for: appearance
                    ),
                    range: run.range
                )
            }
            InlineLinkPresentation.addIcons(to: content)
            result.append(content)
        }
        return result
    }

    static func document(
        from storage: NSAttributedString,
        fallbackKind: MarkdownBlockKind,
        fallbackIndentation: String = "",
        fallbackOrderedStart: Int = 1
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
            let indentation = storage.attribute(
                .dayDreamListIndentation,
                at: location,
                effectiveRange: nil
            ) as? String ?? ""

            // 去掉段落末尾换行，序列化行内样式（**粗体** / span 等）。
            var contentRange = paragraphRange
            if contentRange.length > 0,
               value.character(at: NSMaxRange(contentRange) - 1) == 10 { // "\n"
                contentRange.length -= 1
            }
            let line: String
            if contentRange.length == 0 {
                line = ""
            } else if case .code = kind {
                line = storage.attributedSubstring(from: contentRange).string
            } else {
                line = InlineMarkdown.serialize(storage.attributedSubstring(from: contentRange))
            }
            blocks.append(MarkdownBlock(kind: kind, text: line, indentation: indentation, orderedStart: storage.attribute(.dayDreamOrderedStart, at: location, effectiveRange: nil) as? Int ?? 1))

            let next = NSMaxRange(paragraphRange)
            guard next > location else { break }
            location = next
        }

        // 空文档或文末幻影行（字符串以换行结尾）→ 追加一个空块。
        if value.length == 0
            || value.character(at: value.length - 1) == 10 {
            blocks.append(MarkdownBlock(
                kind: fallbackKind,
                text: "",
                indentation: fallbackKind.isList ? fallbackIndentation : "",
                orderedStart: fallbackOrderedStart
            ))
        }
        return MarkdownDocument(blocks: blocks)
    }
}
