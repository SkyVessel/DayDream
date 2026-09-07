import AppKit
import NaturalLanguage

/// Numeric Markdown remains portable; alternating marker styles are presentation only.
enum OrderedListMarker {
    static func label(ordinal: Int, indentation: String) -> String {
        let depth = DayDreamTheme.indentationColumns(indentation) / 2
        guard depth % 2 == 1 else { return "\(ordinal)." }
        var value = max(ordinal, 1)
        var letters = ""
        while value > 0 {
            value -= 1
            letters = String(UnicodeScalar(97 + value % 26)!) + letters
            value /= 26
        }
        return letters + "."
    }
}

struct WritingTool: RawRepresentable, Codable, Hashable, Identifiable {
    let rawValue: String
    init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }
    private init(_ value: String) { rawValue = value }
    init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(rawValue) }
    static let bold = Self("bold"), italic = Self("italic"), georgia = Self("georgia"), menlo = Self("menlo")
    static let pink = Self("pink"), blue = Self("blue"), green = Self("green"), yellow = Self("yellow")
    static let highlight = Self("highlight"), inlineCode = Self("inlineCode"), plain = Self("plain")
    static func font(_ name: String) -> Self { Self("font:" + name) }
    var id: String { rawValue }
    var isColor: Bool { [Self.pink, .blue, .green, .yellow].contains(self) }
    var highlightColor: String? {
        // Older saved highlight:color tools also follow the single Settings palette.
        rawValue == "highlight" || rawValue.hasPrefix("highlight:") ? EditorSettings.shared.highlightPreset : nil
    }
    var fontName: String? {
        if self == .georgia { return "Georgia" }
        if self == .menlo { return "Menlo" }
        return rawValue.hasPrefix("font:") ? String(rawValue.dropFirst(5)) : nil
    }
    var blockKind: MarkdownBlockKind? {
        switch rawValue {
        case "block:body": .body
        case "block:h1": .heading(level: 1)
        case "block:h2": .heading(level: 2)
        case "block:h3": .heading(level: 3)
        case "block:h4": .heading(level: 4)
        case "block:bullet": .bullet
        case "block:numbered": .numbered
        case "block:todo": .todo(checked: false)
        case "block:quote": .quote
        case "block:code": .code(language: nil)
        case "block:divider": .divider
        default: nil
        }
    }
    var category: String {
        if fontName != nil { return L10n.t("字体", "Fonts") }
        if isColor { return L10n.t("颜色", "Colors") }
        if highlightColor != nil { return L10n.t("高光", "Highlights") }
        if blockKind != nil { return L10n.t("段落", "Paragraphs") }
        return L10n.t("文字样式", "Text styles")
    }
    var title: String {
        if let fontName { return EditorSettings.fontChoices.first(where: { $0.id == fontName })?.displayName ?? FontLibrary.shared.fonts.first(where: { $0.postScriptName == fontName })?.displayName ?? fontName }
        if let blockKind { return SlashCommand(syntax: "", kind: blockKind).title }
        if highlightColor != nil { return L10n.t("高光（跟随设置）", "Highlight (from Settings)") }
        switch self {
        case .bold: return L10n.t("粗体", "Bold")
        case .italic: return L10n.t("斜体", "Italic")
        case .pink: return L10n.t("粉色", "Pink")
        case .blue: return L10n.t("蓝色", "Blue")
        case .green: return L10n.t("绿色", "Green")
        case .yellow: return L10n.t("黄色", "Yellow")
        case .inlineCode: return L10n.t("行内代码", "Inline code")
        case .plain: return L10n.t("恢复默认", "Reset style")
        default: return rawValue
        }
    }
    var symbol: String {
        if fontName != nil { return "textformat" }
        if highlightColor != nil { return "highlighter" }
        if blockKind != nil { return "text.alignleft" }
        switch self {
        case .bold: return "bold"
        case .italic: return "italic"
        case .inlineCode: return "chevron.left.forwardslash.chevron.right"
        case .plain: return "arrow.uturn.backward"
        default: return "circle.fill"
        }
    }
    static var allCases: [Self] {
        let styles: [Self] = [.bold, .italic, .inlineCode, .plain, .pink, .blue, .green, .yellow]
        let highlights: [Self] = [.highlight]
        let blocks = ["body", "h1", "h2", "h3", "h4", "bullet", "numbered", "todo", "quote", "code", "divider"].map { Self("block:" + $0) }
        let fonts = NSFontManager.shared.availableFontFamilies.sorted().map(Self.font) + EditorSettings.fontChoices.map { Self.font($0.id) }
        let imported = FontLibrary.shared.fonts.map { Self.font($0.postScriptName) }
        return styles + highlights + blocks + [.georgia, .menlo] + Array(Set(fonts + imported)).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    static let defaultBars: [[WritingTool]] = [[.bold, .italic, .georgia, .menlo], [.pink, .blue, .green, .yellow]]
}

enum WordCounter {
    static func count(_ source: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = source
        var count = 0
        tokenizer.enumerateTokens(in: source.startIndex..<source.endIndex) { range, _ in
            if source[range].unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) { count += 1 }
            return true
        }
        return count
    }
}

/// Practice state indexes extended grapheme clusters; all display ranges are UTF-16.
/// Punctuation and media are not targets and never enter the document's undo stack.
struct RetypeSession {
    struct Target {
        let character: Character
        let range: NSRange
        let word: Int
    }
    let targets: [Target]
    let originalSelection: NSRange
    private(set) var cursor = 0
    private(set) var results: [Int: Bool] = [:]
    private var history: [(cursor: Int, results: [Int: Bool])] = []
    var isComplete: Bool { cursor >= targets.count }
    var location: Int { isComplete ? (targets.last.map { NSMaxRange($0.range) } ?? 0) : targets[cursor].range.location }

    init(text: String, selection: NSRange) {
        originalSelection = selection
        var targets: [Target] = []
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var word = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            word += 1
            var index = range.lowerBound
            while index < range.upperBound {
                let next = text.index(after: index)
                let character = text[index]
                if character.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) {
                    targets.append(Target(character: character, range: NSRange(index..<next, in: text), word: word))
                }
                index = next
            }
            return true
        }
        self.targets = targets
    }

    mutating func type(_ text: String) {
        for character in text where !isComplete {
            if character.isWhitespace {
                // After finishing a word the cursor already points to the next word.
                // Space only skips an unfinished word; it never skips that next word.
                guard cursor == 0 || targets[cursor - 1].word == targets[cursor].word else { continue }
                history.append((cursor, results))
                let word = targets[cursor].word
                while !isComplete && targets[cursor].word == word {
                    results[cursor] = false
                    cursor += 1
                }
            } else if character.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) {
                history.append((cursor, results))
                results[cursor] = character == targets[cursor].character
                cursor += 1
            }
        }
    }

    mutating func backspace() {
        guard let previous = history.popLast() else { return }
        cursor = previous.cursor
        results = previous.results
    }
}
