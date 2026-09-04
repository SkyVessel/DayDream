import Foundation

enum MarkdownBlockKind: Equatable, Hashable, Sendable {
    case body
    case heading(level: Int)
    case bullet
    case numbered
    case todo(checked: Bool)

    var isList: Bool {
        switch self {
        case .bullet, .numbered, .todo:
            return true
        case .body, .heading:
            return false
        }
    }
}

struct MarkdownBlock: Equatable, Sendable {
    var kind: MarkdownBlockKind
    var text: String
}

struct MarkdownDocument: Equatable, Sendable {
    var blocks: [MarkdownBlock]
}

enum MarkdownDocumentCodec {
    static func parse(_ source: String) -> MarkdownDocument {
        let lines = source.components(separatedBy: "\n")
        return MarkdownDocument(blocks: lines.map(parseLine))
    }

    static func serialize(_ document: MarkdownDocument) -> String {
        var orderedListIndex = 0
        return document.blocks.map { block in
            switch block.kind {
            case .body:
                orderedListIndex = 0
                return block.text
            case let .heading(level):
                orderedListIndex = 0
                return String(repeating: "#", count: min(max(level, 1), 4)) + " " + block.text
            case .bullet:
                orderedListIndex = 0
                return "- " + block.text
            case .numbered:
                orderedListIndex += 1
                return "\(orderedListIndex). " + block.text
            case let .todo(checked):
                orderedListIndex = 0
                return checked ? "- [x] " + block.text : "- [ ] " + block.text
            }
        }.joined(separator: "\n")
    }

    private static func parseLine(_ line: String) -> MarkdownBlock {
        for level in stride(from: 4, through: 1, by: -1) {
            let marker = String(repeating: "#", count: level) + " "
            if line.hasPrefix(marker) {
                return MarkdownBlock(kind: .heading(level: level), text: String(line.dropFirst(marker.count)))
            }
        }

        for (marker, checked) in [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true)] {
            if line.hasPrefix(marker) {
                return MarkdownBlock(kind: .todo(checked: checked), text: String(line.dropFirst(marker.count)))
            }
        }

        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return MarkdownBlock(kind: .bullet, text: String(line.dropFirst(2)))
        }

        if let markerEnd = numberedMarkerEnd(in: line) {
            return MarkdownBlock(kind: .numbered, text: String(line[markerEnd...]))
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
