import Foundation
import NaturalLanguage

enum FocusSentenceResolver {
    static func range(in text: String, caretLocation: Int) -> NSRange? {
        let value = text as NSString
        guard value.length > 0,
              caretLocation >= 0,
              caretLocation <= value.length else { return nil }

        let probeLocation = min(caretLocation, value.length - 1)
        let paragraph = value.paragraphRange(for: NSRange(location: probeLocation, length: 0))
        let paragraphText = value.substring(with: paragraph)
        let localProbeLocation = probeLocation - paragraph.location
        let utf16Index = paragraphText.utf16.index(
            paragraphText.utf16.startIndex,
            offsetBy: localProbeLocation
        )
        guard let probe = String.Index(utf16Index, within: paragraphText) else { return paragraph }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = paragraphText
        var match: NSRange?
        tokenizer.enumerateTokens(in: paragraphText.startIndex..<paragraphText.endIndex) { range, _ in
            guard range.contains(probe) || probe == range.upperBound else { return true }
            let localRange = NSRange(range, in: paragraphText)
            match = NSRange(
                location: paragraph.location + localRange.location,
                length: localRange.length
            )
            return false
        }
        return match ?? paragraph
    }
}

enum WordCompletionResolver {
    struct PartialWord: Equatable {
        let word: String
        let range: NSRange
    }

    static func partialWord(in text: String, caretLocation: Int) -> PartialWord? {
        let value = text as NSString
        guard caretLocation > 0, caretLocation <= value.length else { return nil }
        var start = caretLocation
        while start > 0 {
            let range = value.rangeOfComposedCharacterSequence(at: start - 1)
            let character = value.substring(with: range)
            let isWordCharacter = character.unicodeScalars.allSatisfy {
                CharacterSet.letters.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
            }
            guard isWordCharacter else { break }
            start = range.location
        }
        guard start < caretLocation else { return nil }
        let range = NSRange(location: start, length: caretLocation - start)
        return PartialWord(word: value.substring(with: range), range: range)
    }

    static func suffix(partialWord: String, candidates: [String]) -> String? {
        guard !partialWord.isEmpty else { return nil }
        let foldedPartial = partialWord.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        for candidate in candidates where candidate.count > partialWord.count {
            let foldedCandidate = candidate.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard foldedCandidate.hasPrefix(foldedPartial) else { continue }
            return String(candidate.dropFirst(partialWord.count))
        }
        return nil
    }
}
