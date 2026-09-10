import Foundation

enum MarkdownBlockKind: Equatable, Hashable, Sendable {
    case body
    case divider
    case heading(level: Int)
    case bullet
    case numbered
    case todo(checked: Bool)
    case quote
    // Legacy on-disk block retained for lossless loading; no translation actions exist.
    case translation
    case code(language: String?)

    var isList: Bool {
        switch self {
        case .bullet, .numbered, .todo:
            return true
        case .body, .heading, .quote, .translation, .code, .divider:
            return false
        }
    }
}

struct MarkdownBlock: Equatable, Sendable {
    var kind: MarkdownBlockKind
    var text: String
    /// 列表 marker 前的原始空白。逐字保留，避免编辑正文时改写原有缩进风格。
    var orderedStart: Int
    var indentation: String

    init(kind: MarkdownBlockKind, text: String, indentation: String = "", orderedStart: Int = 1) {
        self.orderedStart = orderedStart
        self.kind = kind
        self.text = text
        self.indentation = indentation
    }
}

struct MarkdownDocument: Equatable, Sendable {
    var blocks: [MarkdownBlock]
}

enum MarkdownDocumentCodec {
    static func parse(_ source: String) -> MarkdownDocument {
        let lines = source.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            if let fence = fenceOpening(in: lines[index]),
               let closingIndex = closingFenceIndex(
                    in: lines,
                    after: index,
                    matching: fence
               ) {
                let content = lines[(index + 1)..<closingIndex]
                if content.isEmpty {
                    blocks.append(.init(kind: .code(language: fence.language), text: ""))
                } else {
                    blocks.append(contentsOf: content.map {
                        .init(kind: .code(language: fence.language), text: $0)
                    })
                }
                index = closingIndex + 1
                continue
            }

            blocks.append(parseLine(lines[index]))
            index += 1
        }

        return MarkdownDocument(blocks: blocks)
    }

    static func serialize(_ document: MarkdownDocument) -> String {
        var lines: [String] = []
        var orderedCounts: [Int: Int] = [:]
        var index = 0

        while index < document.blocks.count {
            let block = document.blocks[index]
            switch block.kind {
            case .body:
                orderedCounts.removeAll()
                lines.append(block.text)
            case let .heading(level):
                orderedCounts.removeAll()
                lines.append(String(repeating: "#", count: min(max(level, 1), 4)) + " " + block.text)
            case .bullet:
                resetOrderedCountsForUnorderedBlock(block, counts: &orderedCounts)
                lines.append(block.indentation + "- " + block.text)
            case .numbered:
                let columns = indentationColumns(block.indentation)
                let previous = index > 0 ? document.blocks[index - 1] : nil
                let previousColumns = previous.map { indentationColumns($0.indentation) }
                let continuesLevel = previous?.kind.isList == true
                    && previousColumns.map { $0 >= columns } == true
                    && !(previousColumns == columns && previous?.kind != .numbered)
                let ordinal = continuesLevel ? (orderedCounts[columns].map { $0 + 1 } ?? block.orderedStart) : block.orderedStart
                orderedCounts[columns] = ordinal
                orderedCounts = orderedCounts.filter { $0.key <= columns }
                lines.append(block.indentation + "\(ordinal). " + block.text)
            case let .todo(checked):
                resetOrderedCountsForUnorderedBlock(block, counts: &orderedCounts)
                lines.append(block.indentation + (checked ? "- [x] " + block.text : "- [ ] " + block.text))
            case .divider:
                orderedCounts.removeAll()
                lines.append("---")
            case .translation:
                orderedCounts.removeAll()
                lines.append("!! " + block.text)
            case .quote:
                orderedCounts.removeAll()
                lines.append("> " + block.text)
            case let .code(language):
                orderedCounts.removeAll()
                var codeLines: [String] = []
                while index < document.blocks.count,
                      document.blocks[index].kind == .code(language: language) {
                    codeLines.append(document.blocks[index].text)
                    index += 1
                }
                let fenceLength = max(3, longestBacktickRun(in: codeLines) + 1)
                let fence = String(repeating: "`", count: fenceLength)
                lines.append(fence + (language ?? ""))
                lines.append(contentsOf: codeLines)
                lines.append(fence)
                continue
            }
            index += 1
        }
        return lines.joined(separator: "\n")
    }

    private static func resetOrderedCountsForUnorderedBlock(
        _ block: MarkdownBlock,
        counts: inout [Int: Int]
    ) {
        let columns = indentationColumns(block.indentation)
        counts[columns] = nil
        counts = counts.filter { $0.key <= columns }
    }

    private static func indentationColumns(_ indentation: String) -> Int {
        indentation.reduce(0) { columns, character in
            columns + (character == "\t" ? 2 : 1)
        }
    }

    private struct Fence {
        let character: Character
        let length: Int
        let language: String?
    }

    private static func fenceOpening(in line: String) -> Fence? {
        let candidate = fenceCandidate(in: line)
        guard let character = candidate.first, character == "`" || character == "~" else {
            return nil
        }
        let length = candidate.prefix(while: { $0 == character }).count
        guard length >= 3 else { return nil }
        let remainder = candidate.dropFirst(length)
        if character == "`", remainder.contains("`") { return nil }
        let info = String(remainder).trimmingCharacters(in: .whitespacesAndNewlines)
        return Fence(character: character, length: length, language: info.isEmpty ? nil : info)
    }

    private static func closingFenceIndex(
        in lines: [String],
        after openingIndex: Int,
        matching fence: Fence
    ) -> Int? {
        guard openingIndex + 1 < lines.count else { return nil }
        for index in (openingIndex + 1)..<lines.count {
            let candidate = fenceCandidate(in: lines[index])
            let runLength = candidate.prefix(while: { $0 == fence.character }).count
            guard runLength >= fence.length else { continue }
            if candidate.dropFirst(runLength).allSatisfy({ $0.isWhitespace }) {
                return index
            }
        }
        return nil
    }

    private static func longestBacktickRun(in lines: [String]) -> Int {
        lines.reduce(0) { longest, line in
            var current = 0
            var lineLongest = 0
            for character in line {
                if character == "`" {
                    current += 1
                    lineLongest = max(lineLongest, current)
                } else {
                    current = 0
                }
            }
            return max(longest, lineLongest)
        }
    }

    private static func fenceCandidate(in line: String) -> Substring {
        var candidate = line[...]
        var count = 0
        while count < 3, candidate.first == " " {
            candidate = candidate.dropFirst()
            count += 1
        }
        return candidate
    }

    private static func parseLine(_ line: String) -> MarkdownBlock {
        if line == "!!" || line.hasPrefix("!! ") { return .init(kind: .translation, text: String(line.dropFirst(min(3, line.count)))) }
        let thematic = line.trimmingCharacters(in: .whitespaces).filter { !$0.isWhitespace }
        if thematic.count >= 3, let first = thematic.first, "-*_".contains(first), thematic.allSatisfy({ $0 == first }) {
            return MarkdownBlock(kind: .divider, text: "")
        }
        for level in stride(from: 4, through: 1, by: -1) {
            let marker = String(repeating: "#", count: level) + " "
            if line.hasPrefix(marker) {
                return MarkdownBlock(kind: .heading(level: level), text: String(line.dropFirst(marker.count)))
            }
        }

        let indentation = line.prefix(while: { $0 == " " || $0 == "\t" })
        let listLine = line.dropFirst(indentation.count)
        let listString = String(listLine)

        for (marker, checked) in [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true)] {
            if listLine.hasPrefix(marker) {
                return MarkdownBlock(
                    kind: .todo(checked: checked),
                    text: String(listLine.dropFirst(marker.count)),
                    indentation: String(indentation)
                )
            }
        }

        if line.hasPrefix("> ") {
            return MarkdownBlock(kind: .quote, text: String(line.dropFirst(2)))
        }
        if line == ">" {
            return MarkdownBlock(kind: .quote, text: "")
        }

        if listLine.hasPrefix("- ") || listLine.hasPrefix("* ") {
            return MarkdownBlock(
                kind: .bullet,
                text: String(listLine.dropFirst(2)),
                indentation: String(indentation)
            )
        }

        if let markerEnd = numberedMarkerEnd(in: listString) {
            return MarkdownBlock(
                kind: .numbered,
                text: String(listString[markerEnd...]),
                indentation: String(indentation),
                orderedStart: Int(listString.prefix(while: { $0.isNumber })) ?? 1
            )
        }

        return MarkdownBlock(kind: .body, text: line)
    }

    private static func numberedMarkerEnd(in line: String) -> String.Index? {
        var index = line.startIndex
        var foundDigit = false
        while index < line.endIndex, line[index].isNumber {
            foundDigit = true
            index = line.index(after: index)
        }
        guard foundDigit,
              index < line.endIndex,
              line[index] == "." else { return nil }
        index = line.index(after: index)
        guard index < line.endIndex, line[index] == " " else { return nil }
        return line.index(after: index)
    }
}
