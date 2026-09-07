import Foundation
import XCTest
@testable import DayDream

final class WritingToolsTests: XCTestCase {
    func testFocusResolverReturnsSentenceContainingCaret() {
        XCTAssertEqual(
            FocusSentenceResolver.range(
                in: "First sentence. Second sentence!",
                caretLocation: 20
            ),
            NSRange(location: 16, length: 16)
        )
    }

    func testFocusResolverUsesCurrentParagraphForUnfinishedSentence() {
        XCTAssertEqual(
            FocusSentenceResolver.range(in: "Finished.\nStill writing", caretLocation: 20),
            NSRange(location: 10, length: 13)
        )
    }

    func testCompletionReturnsOnlyUntypedSuffix() {
        XCTAssertEqual(
            WordCompletionResolver.suffix(
                partialWord: "hel",
                candidates: ["hel", "hello", "help"]
            ),
            "lo"
        )
    }

    func testCompletionRejectsUnrelatedAndCaseOnlyCandidates() {
        XCTAssertNil(WordCompletionResolver.suffix(
            partialWord: "Word",
            candidates: ["world", "WORD"]
        ))
    }

    func testCompletionFindsPartialWordImmediatelyBeforeCaret() {
        let result = WordCompletionResolver.partialWord(
            in: "Say hello wor",
            caretLocation: 13
        )
        XCTAssertEqual(result?.word, "wor")
        XCTAssertEqual(result?.range, NSRange(location: 10, length: 3))
    }

    func testCompletionDoesNotCrossWhitespaceOrPunctuation() {
        XCTAssertNil(WordCompletionResolver.partialWord(in: "hello ", caretLocation: 6))
        XCTAssertNil(WordCompletionResolver.partialWord(in: "hello.", caretLocation: 6))
    }
}

@MainActor
final class WritingToolSettingsTests: XCTestCase {
    func testWritingToolSettingsPersistAcrossInstances() throws {
        let suiteName = "DayDreamTests.WritingTools.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = EditorSettings(defaults: defaults)
        XCTAssertFalse(first.focusModeEnabled)
        XCTAssertTrue(first.wordCompletionEnabled)
        XCTAssertFalse(first.automaticSpellingCorrectionEnabled)

        first.focusModeEnabled = true
        first.wordCompletionEnabled = false
        first.automaticSpellingCorrectionEnabled = true

        let restored = EditorSettings(defaults: defaults)
        XCTAssertTrue(restored.focusModeEnabled)
        XCTAssertFalse(restored.wordCompletionEnabled)
        XCTAssertTrue(restored.automaticSpellingCorrectionEnabled)
    }
}
