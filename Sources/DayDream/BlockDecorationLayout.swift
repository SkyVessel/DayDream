import AppKit

struct BlockDecoration: Equatable {
    let kind: MarkdownBlockKind
    let characterRange: NSRange
    let markerRect: NSRect
    let label: String?
}

enum TodoCheckmarkLayout {
    static func points(
        in box: NSRect,
        scale: CGFloat
    ) -> (start: NSPoint, middle: NSPoint, end: NSPoint) {
        (
            start: NSPoint(x: box.minX + 3.2 * scale, y: box.midY),
            middle: NSPoint(x: box.midX - 0.5 * scale, y: box.maxY - 3.6 * scale),
            end: NSPoint(x: box.maxX - 2.6 * scale, y: box.minY + 3.4 * scale)
        )
    }
}

enum BlockDecorationLayout {
    /// 列表 marker（序号 / 圆点）字体：跟随正文字号，不再使用偏小的固定字号。
    static func markerFont(scale: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: DayDreamTheme.font.pointSize * scale, weight: .medium)
    }
    static func numberedOrdinal(
        in storage: NSAttributedString,
        paragraphLocation: Int
    ) -> Int {
        guard storage.length > 0 else { return 1 }
        let value = storage.string as NSString
        let target = value.paragraphRange(
            for: NSRange(location: min(paragraphLocation, value.length), length: 0)
        ).location
        var ordinal = 1
        var location = target

        while location > 0 {
            let previousIndex = location - 1
            let previousRange = value.paragraphRange(
                for: NSRange(location: previousIndex, length: 0)
            )
            let previousLocation = previousRange.location
            let kind = storage.attribute(
                .dayDreamBlockKind,
                at: min(previousLocation, storage.length - 1),
                effectiveRange: nil
            ) as? MarkdownBlockKind ?? .body
            guard kind == .numbered, previousLocation < location else { break }
            ordinal += 1
            location = previousLocation
        }
        return ordinal
    }

    @MainActor
    static func decorations(
        in textView: NSTextView,
        textContainerOrigin: NSPoint,
        scale: CGFloat
    ) -> [BlockDecoration] {
        guard let storage = textView.textStorage,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return [] }

        layoutManager.ensureLayout(for: textContainer)
        let value = storage.string as NSString
        var decorations: [BlockDecoration] = []
        var location = 0

        while true {
            let paragraphRange = value.paragraphRange(
                for: NSRange(location: min(location, value.length), length: 0)
            )
            let kind: MarkdownBlockKind
            if let dayDreamView = textView as? DayDreamTextView {
                kind = dayDreamView.currentBlockKind(at: location)
            } else if storage.length > 0, location < storage.length {
                kind = storage.attribute(.dayDreamBlockKind, at: location, effectiveRange: nil)
                    as? MarkdownBlockKind ?? .body
            } else {
                kind = .body
            }

            if kind.isList {
                let lineRect: NSRect
                let baselineY: CGFloat
                if location < storage.length {
                    let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
                    lineRect = layoutManager.lineFragmentRect(
                        forGlyphAt: glyphIndex,
                        effectiveRange: nil
                    )
                    baselineY = textContainerOrigin.y + lineRect.minY
                        + layoutManager.location(forGlyphAt: glyphIndex).y
                } else {
                    lineRect = layoutManager.extraLineFragmentRect
                    let activeFont = textView.typingAttributes[.font] as? NSFont
                        ?? textView.font
                        ?? DayDreamTheme.font
                    baselineY = textContainerOrigin.y + lineRect.maxY + activeFont.descender
                }
                let markerSize = 18 * scale
                let markerFont = markerFont(scale: scale)
                let markerRect = NSRect(
                    x: textContainerOrigin.x + lineRect.minX + 9 * scale,
                    y: baselineY - markerFont.ascender,
                    width: markerSize,
                    height: markerSize
                )
                let label: String?
                switch kind {
                case .bullet:
                    label = "•"
                case .numbered:
                    label = "\(numberedOrdinal(in: storage, paragraphLocation: location))."
                case .todo:
                    label = nil
                case .body, .heading:
                    label = nil
                }
                decorations.append(BlockDecoration(
                    kind: kind,
                    characterRange: paragraphRange,
                    markerRect: markerRect,
                    label: label
                ))
            }

            guard location < value.length else { break }
            let next = NSMaxRange(paragraphRange)
            guard next > location else { break }
            location = next
            if location == value.length, !storage.string.hasSuffix("\n") { break }
        }
        return decorations
    }
}
