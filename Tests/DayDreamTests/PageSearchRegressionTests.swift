import XCTest
@testable import DayDream

final class PageSearchRegressionTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Work"), withIntermediateDirectories: true)
        return root
    }

    func testSearchMatchesNamesWithSpacesUnicodeAndCase() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Work/Café 学习笔记.md")
        try "# Test".write(to: url, atomically: true, encoding: .utf8)
        for query in ["学习笔记", " CAFE\u{301}  ", "ＣＡＦＥ", "Work 学习", "café 学习笔记.md"] {
            XCTAssertEqual(LibrarySearchMatching.files(root: root, query: query), [url], query)
        }
    }

    func testExactNamesRankFirstAndLinkModeExcludesPDF() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let exact = root.appendingPathComponent("Daily.md")
        for name in ["Daily.md", "Daily Notes.md", "Daily.pdf"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        let results = LibrarySearchMatching.files(root: root, query: "daily", notesOnly: true)
        XCTAssertEqual(results.first, exact)
        XCTAssertEqual(results.count, 2)
    }

    @MainActor
    func testTypingQueryUpdatesModelWithoutViewOnChange() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let expected = root.appendingPathComponent("Target.md")
        try Data().write(to: expected)
        try Data().write(to: root.appendingPathComponent("Other.md"))
        let model = LibrarySearchModel(root: root)
        model.query = "Other"
        model.query = " Target "
        for _ in 0..<100 where model.searching { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(model.searching)
        XCTAssertEqual(model.results.map(\.url), [expected])
    }

    func testTitleUsesOnlyFirstHeading() {
        XCTAssertEqual(PageTitles.title(in: "# **New** / title\n\nBody"), "New - title")
        XCTAssertNil(PageTitles.title(in: "# \nBody"))
        XCTAssertNil(PageTitles.title(in: "Body\n# Other"))
    }

    @MainActor
    func testFilteringLetterAfterInitialPreviewKeepsCorrectResultAndOpenTarget() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let letter = root.appendingPathComponent("Letter.md")
        try "Letter preview".write(to: letter, atomically: true, encoding: .utf8)
        try "Ideas preview".write(to: root.appendingPathComponent("Ideas and DayDreaming.md"), atomically: true, encoding: .utf8)
        let model = LibrarySearchModel(root: root)
        func waitForPreview() async throws {
            for _ in 0..<200 {
                if !model.searching, let first = model.results.first, first.preview != "…" { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTFail("Search and preview did not finish")
        }
        model.search()
        try await waitForPreview()
        XCTAssertEqual(model.results.first?.title, "Ideas and DayDreaming")
        for query in ["l", "le", "let", "letter"] { model.query = query }
        try await waitForPreview()
        XCTAssertEqual(model.results.map(\.url), [letter])
        XCTAssertEqual(model.results.first?.preview, "Letter preview")
        var opened: URL?
        model.choose = { url, _ in opened = url }
        model.open(inReference: false)
        XCTAssertEqual(opened, letter)
        model.query = ""
        try await waitForPreview()
        XCTAssertEqual(model.results.count, 2)
        model.query = "LETTER"
        try await waitForPreview()
        XCTAssertEqual(model.results.map(\.url), [letter])
    }

    func testReferenceRewritePreservesCodeAndCustomAliases() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("Untitled.md")
        let new = root.appendingPathComponent("New Name.md")
        let source = root.appendingPathComponent("Source.md")
        let text = "[[Untitled]] [[Untitled|Custom]] `[[Untitled]]`\n```md\n[[Untitled]]\n```\n\\[[Untitled]]\n"
        let rewritten = PageTitles.replacingLinks(in: text, source: source, from: old, to: new, root: root, files: [old, source])
        XCTAssertEqual(rewritten, "[[New Name|New Name]] [[New Name|Custom]] `[[Untitled]]`\n```md\n[[Untitled]]\n```\n\\[[Untitled]]\n")
    }

    @MainActor
    func testSavingPageTitleRenamesFileAndUpdatesIncomingLinks() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("Untitled.md")
        let new = root.appendingPathComponent("New Page.md")
        let source = root.appendingPathComponent("Source.md")
        defer { PageTitles.unregister(old); PageTitles.unregister(new) }
        try "# Untitled\n\n".write(to: old, atomically: true, encoding: .utf8)
        try "[[Untitled]]".write(to: source, atomically: true, encoding: .utf8)
        PageTitles.register(old)
        let document = DocumentController()
        let store = WorkspaceStore(rootURL: root)
        let coordinator = WorkspaceCoordinator(center: ShortcutCenter())
        coordinator.configure(store: store, document: document)
        document.open(old)
        document.updateMarkdown("# New Page\n\nBody")
        XCTAssertTrue(document.flush())
        XCTAssertEqual(document.currentURL, new)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try String(contentsOf: new), "# New Page\n\nBody")
        XCTAssertEqual(try String(contentsOf: source), "[[New Page|New Page]]")
        XCTAssertTrue(PageTitles.contains(new))
        XCTAssertTrue(document.flush())
    }

    @MainActor
    func testTitleCollisionDoesNotOverwriteExistingNote() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("Untitled.md")
        let existing = root.appendingPathComponent("Existing.md")
        defer { PageTitles.unregister(old) }
        try "# Untitled".write(to: old, atomically: true, encoding: .utf8)
        try "Keep me".write(to: existing, atomically: true, encoding: .utf8)
        PageTitles.register(old)
        let document = DocumentController()
        let store = WorkspaceStore(rootURL: root)
        let coordinator = WorkspaceCoordinator(center: ShortcutCenter())
        coordinator.configure(store: store, document: document)
        document.open(old); document.updateMarkdown("# Existing")
        XCTAssertTrue(document.flush())
        XCTAssertEqual(document.currentURL, old)
        XCTAssertEqual(try String(contentsOf: existing), "Keep me")
        XCTAssertNotNil(store.errorMessage)
    }
}
