import AppKit

/// 行内样式语义：粗体 / 斜体 / 文字颜色预设名 / 高亮颜色预设名。
struct InlineStyle: Equatable, Sendable {
    var bold = false
    var italic = false
    var textColor: String?
    var highlight: String?

    var isPlain: Bool { !bold && !italic && textColor == nil && highlight == nil }
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
            // 找最近的标记：span / ** / *
            guard let marker = nextMarker(in: rest) else {
                appendStyled(String(rest), style: style, plain: &plain, runs: &runs)
                return
            }
            if marker.range.lowerBound > rest.startIndex {
                appendStyled(String(rest[..<marker.range.lowerBound]), style: style, plain: &plain, runs: &runs)
            }

            switch marker.kind {
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
                    case "color": inner.textColor = pair[1]
                    case "background-color": inner.highlight = pair[1]
                    default: break
                    }
                }
                parseInto(String(rest[marker.range.upperBound..<close.lowerBound]),
                          style: inner, plain: &plain, runs: &runs)
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
        case span(css: String)
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

        if let spanOpen = text.range(of: "<span style=\""),
           let closeQuote = text.range(of: "\">", range: spanOpen.upperBound..<text.endIndex) {
            let css = String(text[spanOpen.upperBound..<closeQuote.lowerBound])
            candidates.append((spanOpen.lowerBound, {
                Marker(kind: .span(css: css), range: spanOpen.lowerBound..<closeQuote.upperBound)
            }))
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

        // 1) 按样式切段
        var segments: [(text: String, style: InlineStyle)] = []
        line.enumerateAttributes(
            in: NSRange(location: 0, length: line.length),
            options: []
        ) { attributes, range, _ in
            let text = line.attributedSubstring(from: range).string
            let style = InlineStyle(
                bold: attributes[.dayDreamBold] as? Bool ?? false,
                italic: attributes[.dayDreamItalic] as? Bool ?? false,
                textColor: attributes[.dayDreamTextColor] as? String,
                highlight: attributes[.dayDreamHighlight] as? String
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
            var inner = ""
            while index < segments.count,
                  segments[index].style.textColor == spanColor,
                  segments[index].style.highlight == spanHighlight {
                inner += wrapBoldItalic(segments[index].text, style: segments[index].style)
                index += 1
            }
            result += wrapSpan(inner, textColor: spanColor, highlight: spanHighlight)
        }
        return result
    }

    private static func wrapBoldItalic(_ text: String, style: InlineStyle) -> String {
        guard !text.isEmpty else { return "" }
        if style.bold, style.italic { return "***\(text)***" }
        if style.bold { return "**\(text)**" }
        if style.italic { return "*\(text)*" }
        return text
    }

    private static func wrapSpan(_ text: String, textColor: String?, highlight: String?) -> String {
        guard !text.isEmpty else { return "" }
        var css: [String] = []
        if let textColor { css.append("color:\(textColor)") }
        if let highlight { css.append("background-color:\(highlight)") }
        guard !css.isEmpty else { return text }
        return "<span style=\"\(css.joined(separator: ";"))\">\(text)</span>"
    }
}
