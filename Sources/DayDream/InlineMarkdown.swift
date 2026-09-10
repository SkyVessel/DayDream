import AppKit

/// 行内样式语义：粗体 / 斜体 / 文字颜色预设名 / 高亮颜色预设名。
struct InlineStyle: Equatable, Sendable {
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var code = false
    var linkDestination: String?
    var imageDestination: String?
    var textColor: String?
    var highlight: String?
    var fontFamily: String?
    var media: MediaCard?

    var isPlain: Bool {
        !bold && !italic && !underline && !strikethrough && !code && linkDestination == nil && imageDestination == nil
            && textColor == nil && highlight == nil && fontFamily == nil && media == nil
    }
}

/// 一段带行内样式的文本（range 基于解析后的纯文本）。
struct InlineRun: Equatable, Sendable {
    let range: NSRange
    let style: InlineStyle
}

/// 行内 Markdown 的解析（读）与序列化（写）。
///
/// 语法约定（与 mdnotes 的无损往返设计一致）：
/// - 粗体 `**x**`、斜体 `*x*`、粗斜 `***x***`
/// - 文字颜色 / 高亮用 `<span style="color:yellow">` / `background-color:pink`，
///   颜色值是预设名（caret / yellow / green / blue / pink）
/// - 包裹顺序：粗斜体在内，span 在最外
enum InlineMarkdown {

    // MARK: - 解析（Markdown → 纯文本 + 样式段）

    static func parse(_ source: String) -> (plain: String, runs: [InlineRun]) {
        var plain = ""
        var runs: [InlineRun] = []
        parseInto(source, style: InlineStyle(), plain: &plain, runs: &runs)
        return (plain, runs)
    }

    private static func parseInto(
        _ source: String,
        style: InlineStyle,
        plain: inout String,
        runs: inout [InlineRun]
    ) {
        var rest = Substring(source)
        while !rest.isEmpty {
            // 找最近的标记：span / ` / ** / *
            guard let marker = nextMarker(in: rest) else {
                appendStyled(String(rest), style: style, plain: &plain, runs: &runs)
                return
            }
            if marker.range.lowerBound > rest.startIndex {
                appendStyled(String(rest[..<marker.range.lowerBound]), style: style, plain: &plain, runs: &runs)
            }

            switch marker.kind {
            case let .media(card):
                var inner = style
                inner.media = card
                appendStyled("\u{FFFC}", style: inner, plain: &plain, runs: &runs)
                rest = rest[marker.range.upperBound...]

            case let .link(label, destination):
                var inner = style
                inner.linkDestination = destination
                parseInto(label, style: inner, plain: &plain, runs: &runs)
                rest = rest[marker.range.upperBound...]

            case let .image(label, destination):
                var inner = style
                inner.imageDestination = destination
                appendStyled(label, style: inner, plain: &plain, runs: &runs)
                rest = rest[marker.range.upperBound...]

            case let .code(delimiter):
                guard let close = matchingBacktickClose(
                    delimiter: delimiter,
                    in: rest,
                    after: marker.range.upperBound
                ) else {
                    appendStyled(String(rest[marker.range]), style: style, plain: &plain, runs: &runs)
                    rest = rest[marker.range.upperBound...]
                    continue
                }
                var inner = style
                inner.code = true
                // 代码跨度里的 Markdown 标记是字面量，不再递归解析。
                var code = String(rest[marker.range.upperBound..<close.lowerBound])
                if code.first == " ", code.last == " ", code.contains(where: { !$0.isWhitespace }) {
                    code.removeFirst()
                    code.removeLast()
                }
                appendStyled(
                    code,
                    style: inner,
                    plain: &plain,
                    runs: &runs
                )
                rest = rest[close.upperBound...]

            case .span(let css):
                guard let close = rest.range(of: "</span>", range: marker.range.upperBound..<rest.endIndex) else {
                    appendStyled(String(rest[marker.range]), style: style, plain: &plain, runs: &runs)
                    rest = rest[marker.range.upperBound...]
                    continue
                }
                var inner = style
                for declaration in css.split(separator: ";") {
                    let pair = declaration.split(separator: ":").map {
                        $0.trimmingCharacters(in: .whitespaces)
                    }
                    guard pair.count == 2 else { continue }
                    switch pair[0] {
                    case "color":
                        inner.textColor = PortableInlineColor.presetName(
                            forCSSValue: pair[1],
                            property: .text
                        )
                    case "font-family":
                        inner.fontFamily = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "'"))
                    case "background-color":
                        inner.highlight = PortableInlineColor.presetName(
                            forCSSValue: pair[1],
                            property: .highlight
                        )
                    default: break
                    }
                }
                parseInto(String(rest[marker.range.upperBound..<close.lowerBound]),
                          style: inner, plain: &plain, runs: &runs)
                rest = rest[close.upperBound...]

            case .underline, .strikethrough:
                let token = marker.kind == .underline ? "</u>" : "~~"
                guard let close = rest.range(of: token, range: marker.range.upperBound..<rest.endIndex) else {
                    appendStyled(String(rest[marker.range]), style: style, plain: &plain, runs: &runs)
                    rest = rest[marker.range.upperBound...]
                    continue
                }
                var inner = style
                if marker.kind == .underline { inner.underline = true } else { inner.strikethrough = true }
                parseInto(String(rest[marker.range.upperBound..<close.lowerBound]), style: inner, plain: &plain, runs: &runs)
                rest = rest[close.upperBound...]

            case .boldItalic, .bold, .italic:
                let token: String
                switch marker.kind {
                case .boldItalic: token = "***"
                case .bold: token = "**"
                default: token = "*"
                }
                guard let close = rest.range(
                    of: token,
                    range: marker.range.upperBound..<rest.endIndex
                ) else {
                    appendStyled(String(rest[marker.range]), style: style, plain: &plain, runs: &runs)
                    rest = rest[marker.range.upperBound...]
                    continue
                }
                var inner = style
                switch marker.kind {
                case .boldItalic: inner.bold = true; inner.italic = true
                case .bold: inner.bold = true
                default: inner.italic = true
                }
                parseInto(String(rest[marker.range.upperBound..<close.lowerBound]),
                          style: inner, plain: &plain, runs: &runs)
                rest = rest[close.upperBound...]
            }
        }
    }

    private enum MarkerKind: Equatable {
        case media(MediaCard)
        case code(delimiter: String)
        case link(label: String, destination: String)
        case image(label: String, destination: String)
        case span(css: String)
        case underline, strikethrough
        case boldItalic
        case bold
        case italic
    }

    private struct Marker {
        let kind: MarkerKind
        let range: Range<String.Index>
    }

    /// 找到最近的一个标记（span 开标签 / ** / *），返回其种类与范围。
    private static func nextMarker(in text: Substring) -> Marker? {
        var candidates: [(index: String.Index, make: () -> Marker)] = []

        if let opening = text.range(of: "<figure data-daydream=\""),
           let closing = text.range(of: "</figure>", range: opening.upperBound..<text.endIndex),
           let card = MediaCard.parse(String(text[opening.lowerBound..<closing.upperBound])) {
            candidates.append((opening.lowerBound, { Marker(kind: .media(card), range: opening.lowerBound..<closing.upperBound) }))
        }
        if let opening = text.range(of: "[["),
           let closing = text.range(of: "]]", range: opening.upperBound..<text.endIndex) {
            let body = String(text[opening.upperBound..<closing.lowerBound])
            let parts = body.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            if let target = parts.first, !target.isEmpty, !body.contains("\n") {
                let label = parts.count == 2 ? parts[1] : target
                candidates.append((opening.lowerBound, { Marker(kind: .link(label: label, destination: NoteLinks.destination(target)), range: opening.lowerBound..<closing.upperBound) }))
            }
        }
        if let link = firstLinkOrImageMarker(in: text) {
            candidates.append((link.range.lowerBound, { link }))
        }

        if let backtick = text.firstIndex(of: "`") {
            var after = text.index(after: backtick)
            while after < text.endIndex, text[after] == "`" {
                after = text.index(after: after)
            }
            let delimiter = String(text[backtick..<after])
            candidates.append((backtick, {
                Marker(kind: .code(delimiter: delimiter), range: backtick..<after)
            }))
        }

        if let spanOpen = text.range(of: "<span style=\""),
           let closeQuote = text.range(of: "\">", range: spanOpen.upperBound..<text.endIndex) {
            let css = String(text[spanOpen.upperBound..<closeQuote.lowerBound])
            candidates.append((spanOpen.lowerBound, {
                Marker(kind: .span(css: css), range: spanOpen.lowerBound..<closeQuote.upperBound)
            }))
        }
        for (token, kind) in [("<u>", MarkerKind.underline), ("~~", MarkerKind.strikethrough)] {
            if let range = text.range(of: token) {
                candidates.append((range.lowerBound, { Marker(kind: kind, range: range) }))
            }
        }
        if let triple = text.range(of: "***") {
            candidates.append((triple.lowerBound, {
                Marker(kind: .boldItalic, range: triple.lowerBound..<triple.upperBound)
            }))
        }
        // ** 不能是 *** 的一部分
        if let bold = text.range(of: "**") {
            let after = bold.upperBound
            let isTriple = after < text.endIndex && text[after] == "*"
            if !isTriple {
                candidates.append((bold.lowerBound, {
                    Marker(kind: .bold, range: bold.lowerBound..<bold.upperBound)
                }))
            }
        }
        // 单个 * 不能是 ** 或 *** 的一部分
        if let star = text.firstIndex(of: "*") {
            let after = text.index(after: star)
            if after == text.endIndex || text[after] != "*" {
                candidates.append((star, {
                    Marker(kind: .italic, range: star..<after)
                }))
            }
        }

        guard let earliest = candidates.min(by: { $0.index < $1.index }) else { return nil }
        return earliest.make()
    }

    private static func firstLinkOrImageMarker(in text: Substring) -> Marker? {
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let open = text[searchStart...].firstIndex(of: "[") {
            let isImage = open > text.startIndex && text[text.index(before: open)] == "!"
            let labelStart = text.index(after: open)
            guard let separator = text.range(of: "](", range: labelStart..<text.endIndex),
                  let close = text[separator.upperBound...].firstIndex(of: ")") else {
                return nil
            }
            let label = String(text[labelStart..<separator.lowerBound])
            let destination = String(text[separator.upperBound..<close])
            guard !label.isEmpty, !destination.isEmpty else {
                searchStart = text.index(after: open)
                continue
            }
            let start = isImage ? text.index(before: open) : open
            return Marker(
                kind: isImage
                    ? .image(label: label, destination: destination)
                    : .link(label: label, destination: destination),
                range: start..<text.index(after: close)
            )
        }
        return nil
    }

    private static func matchingBacktickClose(
        delimiter: String,
        in text: Substring,
        after start: String.Index
    ) -> Range<String.Index>? {
        var searchStart = start
        while let candidate = text.range(of: delimiter, range: searchStart..<text.endIndex) {
            let hasBacktickBefore = candidate.lowerBound > text.startIndex
                && text[text.index(before: candidate.lowerBound)] == "`"
            let hasBacktickAfter = candidate.upperBound < text.endIndex
                && text[candidate.upperBound] == "`"
            if !hasBacktickBefore, !hasBacktickAfter {
                return candidate
            }
            searchStart = candidate.upperBound
        }
        return nil
    }

    private static func appendStyled(
        _ text: String,
        style: InlineStyle,
        plain: inout String,
        runs: inout [InlineRun]
    ) {
        guard !text.isEmpty else { return }
        let start = (plain as NSString).length
        plain += text
        guard !style.isPlain else { return }
        runs.append(InlineRun(
            range: NSRange(location: start, length: (text as NSString).length),
            style: style
        ))
    }

    // MARK: - 序列化（带属性的行 → Markdown）

    /// 把一行 NSAttributedString 序列化为行内 Markdown。
    /// 读取自定义语义键（.dayDreamBold / .dayDreamItalic / .dayDreamTextColor / .dayDreamHighlight），
    /// 相邻且样式相同的片段会合并，避免词距等无关属性把样式切碎。
    static func serialize(_ line: NSAttributedString) -> String {
        guard line.length > 0 else { return "" }
        var mediaRange: NSRange?
        var mediaCard: MediaCard?
        line.enumerateAttribute(.dayDreamMedia, in: NSRange(location: 0, length: line.length)) { value, range, stop in
            if let card = value as? MediaCard { mediaRange = range; mediaCard = card; stop.pointee = true }
        }
        if let range = mediaRange, let card = mediaCard {
            let before = serialize(line.attributedSubstring(from: NSRange(location: 0, length: range.location)))
            let after = serialize(line.attributedSubstring(from: NSRange(location: NSMaxRange(range), length: line.length - NSMaxRange(range))))
            return before + card.markdown + after
        }

        // 1) 按样式切段
        var segments: [(text: String, style: InlineStyle)] = []
        line.enumerateAttributes(
            in: NSRange(location: 0, length: line.length),
            options: []
        ) { attributes, range, _ in
            guard attributes[.dayDreamLinkIcon] == nil else { return }
            let text = line.attributedSubstring(from: range).string
            let style = InlineStyle(
                bold: attributes[.dayDreamBold] as? Bool ?? false,
                italic: attributes[.dayDreamItalic] as? Bool ?? false,
                underline: attributes[.dayDreamUnderline] as? Bool ?? false,
                strikethrough: attributes[.dayDreamStrikethrough] as? Bool ?? false,
                code: attributes[.dayDreamInlineCode] as? Bool ?? false,
                linkDestination: attributes[.dayDreamLink] as? String,
                imageDestination: attributes[.dayDreamImage] as? String,
                textColor: attributes[.dayDreamTextColor] as? String,
                highlight: attributes[.dayDreamHighlight] as? String,
                fontFamily: attributes[.dayDreamFontFamily] as? String
            )
            if let last = segments.last, last.style == style {
                segments[segments.count - 1].text += text
            } else {
                segments.append((text, style))
            }
        }

        // 2) 按 span 颜色分组：颜色相同的连续片段合并在一个 span 内，粗斜体包在最里层。
        var result = ""
        var index = 0
        while index < segments.count {
            let spanColor = segments[index].style.textColor
            let spanHighlight = segments[index].style.highlight
            let spanFont = segments[index].style.fontFamily
            let linkDestination = segments[index].style.linkDestination
            let imageDestination = segments[index].style.imageDestination
            var inner = ""
            while index < segments.count,
                  segments[index].style.textColor == spanColor,
                  segments[index].style.highlight == spanHighlight,
                  segments[index].style.fontFamily == spanFont,
                  segments[index].style.linkDestination == linkDestination,
                  segments[index].style.imageDestination == imageDestination {
                inner += wrapInline(segments[index].text, style: segments[index].style)
                index += 1
            }
            if let linkDestination {
                if let target = NoteLinks.target(linkDestination) {
                    inner = inner == target ? "[[\(target)]]" : "[[\(target)|\(inner)]]"
                } else { inner = "[\(inner)](\(linkDestination))" }
            } else if let imageDestination {
                inner = "![\(inner)](\(imageDestination))"
            }
            result += wrapSpan(inner, textColor: spanColor, highlight: spanHighlight, fontFamily: spanFont)
        }
        return result
    }

    private static func wrapInline(_ text: String, style: InlineStyle) -> String {
        guard !text.isEmpty else { return "" }
        if style.underline || style.strikethrough {
            var inner = style
            inner.underline = false; inner.strikethrough = false
            var result = wrapInline(text, style: inner)
            if style.strikethrough { result = "~~" + result + "~~" }
            if style.underline { result = "<u>" + result + "</u>" }
            return result
        }
        if style.code {
            let delimiter = String(
                repeating: "`",
                count: longestBacktickRun(in: text) + 1
            )
            let needsPadding = text.first == "`" || text.last == "`"
            let content = needsPadding ? " \(text) " : text
            return delimiter + content + delimiter
        }
        if style.bold || style.italic {
            let leading = String(text.prefix(while: \.isWhitespace))
            let trailing = String(text.reversed().prefix(while: \.isWhitespace).reversed())
            guard leading.count < text.count else { return text }
            let content = String(text.dropFirst(leading.count).dropLast(trailing.count))
            let marker = style.bold && style.italic ? "***" : style.bold ? "**" : "*"
            return leading + marker + content + marker + trailing
        }
        return text
    }

    private static func longestBacktickRun(in text: String) -> Int {
        var longest = 0
        var current = 0
        for character in text {
            if character == "`" {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }

    private static func wrapSpan(_ text: String, textColor: String?, highlight: String?, fontFamily: String?) -> String {
        guard !text.isEmpty else { return "" }
        var css: [String] = []
        if let fontFamily {
            let cssFamily = ["": "-apple-system", "mono": "monospace", "rounded": "SF Pro Rounded"][fontFamily] ?? fontFamily
            css.append("font-family:\(cssFamily.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" })")
        }
        if let textColor {
            css.append("color:\(PortableInlineColor.cssValue(for: textColor, property: .text))")
        }
        if let highlight {
            css.append("background-color:\(PortableInlineColor.cssValue(for: highlight, property: .highlight))")
        }
        guard !css.isEmpty else { return text }
        return "<span style=\"\(css.joined(separator: ";"))\">\(text)</span>"
    }
}

enum PortableInlineColor {
    enum Property {
        case text
        case highlight
    }

    private static let textValues: [StyleColorPreset: String] = [
        .caret: "#C48E9C",
        .yellow: "#8A7A48",
        .green: "#5F7F68",
        .blue: "#5B7FA6",
        .pink: "#9A6E7B",
    ]
    private static let highlightValues: [StyleColorPreset: String] = [
        .caret: "#E8C0C8",
        .yellow: "#D8C88F",
        .green: "#A8C7AF",
        .blue: "#A8BED5",
        .pink: "#D8B0B8",
    ]

    static func cssValue(for presetName: String, property: Property) -> String {
        guard let preset = StyleColorPreset(rawValue: presetName) else { return presetName }
        return values(for: property)[preset] ?? presetName
    }

    static func presetName(forCSSValue value: String, property: Property) -> String {
        if let preset = StyleColorPreset(rawValue: value.lowercased()) {
            return preset.rawValue
        }
        let normalized = value.uppercased()
        return values(for: property).first(where: { $0.value.uppercased() == normalized })?.key.rawValue
            ?? value
    }

    private static func values(for property: Property) -> [StyleColorPreset: String] {
        switch property {
        case .text: textValues
        case .highlight: highlightValues
        }
    }
}
