import Foundation

struct MarkdownTriggerResult: Equatable {
    let replacementRange: NSRange
    let kind: MarkdownBlockKind
    var orderedStart: Int = 1
}

enum MarkdownEditingController {
    static func trigger(in source: String, caretLocation: Int) -> MarkdownTriggerResult? {
        let value = source as NSString
        guard caretLocation >= 0, caretLocation <= value.length else { return nil }
        let paragraphRange = value.paragraphRange(
            for: NSRange(location: caretLocation, length: 0)
        )
        let prefixRange = NSRange(
            location: paragraphRange.location,
            length: caretLocation - paragraphRange.location
        )
        let prefix = value.substring(with: prefixRange)

        let kind: MarkdownBlockKind
        switch prefix {
        case "---", "***", "___": kind = .divider
        case "#": kind = .heading(level: 1)
        case "##": kind = .heading(level: 2)
        case "###": kind = .heading(level: 3)
        case "####": kind = .heading(level: 4)
        case "-", "*": kind = .bullet
        case "1.": kind = .numbered
        case "[ ]", "[]": kind = .todo(checked: false)
        case "[x]", "[X]": kind = .todo(checked: true)
        case ">": kind = .quote
        case "```": kind = .code(language: nil)
        default:
            guard prefix.hasSuffix("."), !prefix.dropLast().isEmpty,
                  prefix.dropLast().allSatisfy({ $0.isASCII && $0.isNumber }),
                  let start = Int(prefix.dropLast()), start < Int.max else { return nil }
            return MarkdownTriggerResult(replacementRange: prefixRange, kind: .numbered, orderedStart: start)
        }
        return MarkdownTriggerResult(replacementRange: prefixRange, kind: kind)
    }

    static func nextKind(
        after currentKind: MarkdownBlockKind,
        currentText: String
    ) -> MarkdownBlockKind? {
        switch currentKind {
        case .body:
            return .body
        case .heading, .divider:
            return .body
        case .bullet:
            return currentText.isEmpty ? nil : .bullet
        case .numbered:
            return currentText.isEmpty ? nil : .numbered
        case .todo:
            return currentText.isEmpty ? nil : .todo(checked: false)
        case .quote:
            return currentText.isEmpty ? nil : .quote
        case let .code(language):
            return currentText.isEmpty ? nil : .code(language: language)
        }
    }
}
