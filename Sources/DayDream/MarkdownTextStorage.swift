import AppKit

extension NSAttributedString.Key {
    static let dayDreamBlockKind = NSAttributedString.Key("DayDreamBlockKind")
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
            let content = block.text + (index < blocks.count - 1 ? "\n" : "")
            result.append(NSAttributedString(string: content, attributes: attributes))
        }
        return result
    }

    static func document(
        from storage: NSAttributedString,
        fallbackKind: MarkdownBlockKind
    ) -> MarkdownDocument {
        let lines = storage.string.components(separatedBy: "\n")
        var location = 0
        let blocks = lines.map { line -> MarkdownBlock in
            let kind: MarkdownBlockKind
            if storage.length > 0, location < storage.length {
                kind = storage.attribute(
                    .dayDreamBlockKind,
                    at: location,
                    effectiveRange: nil
                ) as? MarkdownBlockKind ?? .body
            } else {
                kind = fallbackKind
            }
            location += (line as NSString).length + 1
            return MarkdownBlock(kind: kind, text: line)
        }
        return MarkdownDocument(blocks: blocks)
    }
}
