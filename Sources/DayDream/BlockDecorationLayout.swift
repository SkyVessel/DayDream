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
        paragraphLocation: Int,
        trailingIndentation: String? = nil,
        trailingStart: Int = 1
    ) -> Int {
        guard storage.length > 0 else { return trailingStart }
        let value = storage.string as NSString
        let target = value.paragraphRange(
            for: NSRange(location: min(paragraphLocation, value.length), length: 0)
        ).location
        let targetIndentation = (target == storage.length ? trailingIndentation : nil) ?? (storage.attribute(
            .dayDreamListIndentation,
            at: min(target, storage.length - 1),
            effectiveRange: nil
        ) as? String ?? "")
        let targetColumns = DayDreamTheme.indentationColumns(targetIndentation)
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
            guard kind.isList, previousLocation < location else { break }
            let previousIndentation = storage.attribute(
                .dayDreamListIndentation,
                at: min(previousLocation, storage.length - 1),
                effectiveRange: nil
            ) as? String ?? ""
            let previousColumns = DayDreamTheme.indentationColumns(previousIndentation)
            if previousColumns < targetColumns { break }
            if previousColumns == targetColumns {
                guard kind == .numbered else { break }
                ordinal += 1
            }
            location = previousLocation
        }
        let start = location == storage.length ? trailingStart : (storage.attribute(.dayDreamOrderedStart, at: location, effectiveRange: nil) as? Int ?? 1)
        return ordinal + start - 1
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

        let resolvedVisibleRect = textView.visibleRect
        let drawingRect = resolvedVisibleRect.width.isFinite
            && resolvedVisibleRect.height.isFinite
            && resolvedVisibleRect.width <= max(textView.bounds.width * 4, 1)
            && resolvedVisibleRect.height <= max(textView.bounds.height * 4, 1)
            ? resolvedVisibleRect
            : textView.bounds
        let visibleRect = drawingRect.offsetBy(
            dx: -textContainerOrigin.x,
            dy: -textContainerOrigin.y
        )
        layoutManager.ensureLayout(forBoundingRect: visibleRect, in: textContainer)
        let value = storage.string as NSString
        let glyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleRect,
            in: textContainer
        )
        let visibleCharacterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        let scanRange = value.paragraphRange(for: visibleCharacterRange)
        var decorations: [BlockDecoration] = []
        var location = min(scanRange.location, value.length)
        let scanLimit = min(NSMaxRange(scanRange), value.length)

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

            let indentation: String
            if let editor = textView as? DayDreamTextView { indentation = editor.currentListIndentation(at: location) }
            else if location < storage.length { indentation = storage.attribute(.dayDreamListIndentation, at: location, effectiveRange: nil) as? String ?? "" }
            else { indentation = "" }

            if kind.isList || kind == .quote || kind == .divider {
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
                let markerRect: NSRect
                if kind == .divider {
                    markerRect = NSRect(x: textContainerOrigin.x, y: textContainerOrigin.y + lineRect.midY, width: textContainer.size.width, height: 1)
                } else if kind == .quote {
                    let availableRange = NSIntersectionRange(
                        paragraphRange,
                        NSRange(location: 0, length: storage.length)
                    )
                    let paragraphBounds: NSRect
                    if availableRange.length > 0 {
                        let glyphRange = layoutManager.glyphRange(
                            forCharacterRange: availableRange,
                            actualCharacterRange: nil
                        )
                        paragraphBounds = layoutManager.boundingRect(
                            forGlyphRange: glyphRange,
                            in: textContainer
                        )
                    } else {
                        paragraphBounds = lineRect
                    }
                    markerRect = NSRect(
                        x: textContainerOrigin.x + lineRect.minX + 4 * scale,
                        y: textContainerOrigin.y + paragraphBounds.minY,
                        width: 2.5 * scale,
                        height: max(paragraphBounds.height, 18 * scale)
                    )
                } else {
                    let markerSize = 18 * scale
                    let markerFont = markerFont(scale: scale)
                    markerRect = NSRect(
                        x: textContainerOrigin.x + lineRect.minX + (9 + CGFloat(DayDreamTheme.indentationColumns(indentation)) * 12) * scale,
                        y: baselineY - markerFont.ascender,
                        width: markerSize,
                        height: markerSize
                    )
                }
                let label: String?
                switch kind {
                case .bullet:
                    label = "•"
                case .numbered:
                    let ordinal = numberedOrdinal(
                        in: storage, paragraphLocation: location,
                        trailingIndentation: indentation,
                        trailingStart: (textView as? DayDreamTextView)?.trailingOrderedStart ?? 1
                    )
                    label = OrderedListMarker.label(ordinal: ordinal, indentation: indentation)
                case .todo:
                    label = nil
                case .quote:
                    label = nil
                case .body, .heading, .translation, .code, .divider:
                    label = nil
                }
                decorations.append(BlockDecoration(
                    kind: kind,
                    characterRange: paragraphRange,
                    markerRect: markerRect,
                    label: label
                ))
            }

            guard location < value.length, location < scanLimit else { break }
            let next = NSMaxRange(paragraphRange)
            guard next > location else { break }
            location = next
            if location >= scanLimit,
               !(location == value.length && storage.string.hasSuffix("\n")) { break }
        }
        var joined: [BlockDecoration] = []
        for decoration in decorations {
            if decoration.kind == .quote, let previous = joined.last, previous.kind == .quote,
               NSMaxRange(previous.characterRange) == decoration.characterRange.location {
                joined.removeLast()
                joined.append(BlockDecoration(kind: .quote,
                    characterRange: NSUnionRange(previous.characterRange, decoration.characterRange),
                    markerRect: previous.markerRect.union(decoration.markerRect), label: nil))
            } else { joined.append(decoration) }
        }
        return joined
    }
}
