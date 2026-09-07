import XCTest
@testable import DayDream

final class SourcePreservingMarkdownTests: XCTestCase {
    func testUnchangedCanonicalDocumentRestoresOriginalLinesExactly() {
        let source = "* item\n5. first\n6. second\n- [X] task\n"
        let baseline = "- item\n1. first\n2. second\n- [x] task\n"
        let snapshot = SourcePreservingMarkdown(
            original: source,
            canonicalBaseline: baseline
        )

        XCTAssertEqual(snapshot.merge(canonicalCurrent: baseline), source)
    }

    func testChangedLineIsCanonicalWhileUnchangedNeighborsRemainOriginal() {
        let snapshot = SourcePreservingMarkdown(
            original: "* item\n5. first\n> untouched",
            canonicalBaseline: "- item\n1. first\n> untouched"
        )

        XCTAssertEqual(
            snapshot.merge(canonicalCurrent: "- item\n1. changed\n> untouched"),
            "* item\n1. changed\n> untouched"
        )
    }

    func testInsertedAndDeletedLinesDoNotRewriteFollowingSource() {
        let snapshot = SourcePreservingMarkdown(
            original: "* first\n* remove\n7. last",
            canonicalBaseline: "- first\n- remove\n1. last"
        )

        XCTAssertEqual(
            snapshot.merge(canonicalCurrent: "New\n- first\n1. last"),
            "New\n* first\n7. last"
        )
    }

    func testDuplicateAndTrailingEmptyLinesRemainStable() {
        let source = "* same\n- same\n\n"
        let baseline = "- same\n- same\n\n"
        let snapshot = SourcePreservingMarkdown(
            original: source,
            canonicalBaseline: baseline
        )

        XCTAssertEqual(snapshot.merge(canonicalCurrent: baseline), source)
    }

    func testMismatchedSnapshotFallsBackToCanonicalOutput() {
        let snapshot = SourcePreservingMarkdown(
            original: "one line",
            canonicalBaseline: "one\ntwo"
        )

        XCTAssertEqual(snapshot.merge(canonicalCurrent: "changed"), "changed")
    }

    func testUnchangedDocumentIsExactEvenWhenCanonicalLineCountDiffers() {
        let snapshot = SourcePreservingMarkdown(
            original: "```\n```",
            canonicalBaseline: "```\n\n```"
        )

        XCTAssertEqual(
            snapshot.merge(canonicalCurrent: "```\n\n```"),
            "```\n```"
        )
    }

    func testChangedLinesKeepTheDocumentsCRLFLineEndings() {
        let snapshot = SourcePreservingMarkdown(
            original: "Title\r\nBody\r\n",
            canonicalBaseline: "Title\nBody\n"
        )

        XCTAssertEqual(
            snapshot.merge(canonicalCurrent: "Title\nChanged\n"),
            "Title\r\nChanged\r\n"
        )
    }

    func testLargeDocumentChangesOneLineWithoutRewritingItsNeighbors() {
        let originalLines = (0..<10_000).map { index in
            index.isMultiple(of: 2) ? "* item \(index)" : "line \(index)  "
        }
        let baselineLines = originalLines.map { line in
            line.hasPrefix("* ") ? "- " + line.dropFirst(2) : line
        }
        var currentLines = baselineLines
        currentLines[5_000] = "- changed"
        let snapshot = SourcePreservingMarkdown(
            original: originalLines.joined(separator: "\n"),
            canonicalBaseline: baselineLines.joined(separator: "\n")
        )

        let merged = snapshot.merge(canonicalCurrent: currentLines.joined(separator: "\n"))
            .components(separatedBy: "\n")
        XCTAssertEqual(merged[4_998], originalLines[4_998])
        XCTAssertEqual(merged[4_999], originalLines[4_999])
        XCTAssertEqual(merged[5_000], "- changed")
        XCTAssertEqual(merged[5_001], originalLines[5_001])
    }
}
