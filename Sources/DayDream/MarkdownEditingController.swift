import Foundation

struct MarkdownTriggerResult: Equatable {
    let replacementRange: NSRange
    let kind: MarkdownBlockKind
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
        case "#": kind = .heading(level: 1)
        case "##": kind = .heading(level: 2)
        case "###": kind = .heading(level: 3)
        case "####": kind = .heading(level: 4)
        case "-", "*": kind = .bullet
        case "1.": kind = .numbered
        case "[ ]", "[]": kind = .todo(checked: false)
        case "[x]", "[X]": kind = .todo(checked: true)
        default: return nil
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
        case .heading:
            return .body
        case .bullet:
            return currentText.isEmpty ? nil : .bullet
        case .numbered:
            return currentText.isEmpty ? nil : .numbered
        case .todo:
            return currentText.isEmpty ? nil : .todo(checked: false)
        }
    }
}
