import Foundation
import XCTest
@testable import DayDream

final class SidebarModelTests: XCTestCase {
    func testProjectionRespectsExpandedFoldersAndDepth() {
        let root = URL(fileURLWithPath: "/Library")
        let chapter = WorkspaceNode(
            url: root.appending(path: "Chapter", directoryHint: .isDirectory),
            kind: .folder,
            children: [
                WorkspaceNode(
                    url: root.appending(path: "Chapter/Section", directoryHint: .isDirectory),
                    kind: .folder,
                    children: [
                        WorkspaceNode(url: root.appending(path: "Chapter/Section/Note.md"), kind: .note, children: [])
                    ]
                ),
                WorkspaceNode(url: root.appending(path: "Chapter/Intro.md"), kind: .note, children: []),
            ]
        )

        let collapsed = SidebarTreeProjection.rows(from: [chapter], expandedFolders: [])
        XCTAssertEqual(collapsed.map(\.node.name), ["Chapter"])
        XCTAssertEqual(collapsed.map(\.depth), [0])

        let firstLevel = SidebarTreeProjection.rows(
            from: [chapter],
            expandedFolders: [chapter.url]
        )
        XCTAssertEqual(firstLevel.map(\.node.name), ["Chapter", "Section", "Intro"])
        XCTAssertEqual(firstLevel.map(\.depth), [0, 1, 1])

        let all = SidebarTreeProjection.rows(
            from: [chapter],
            expandedFolders: [chapter.url, chapter.children[0].url]
        )
        XCTAssertEqual(all.map(\.node.name), ["Chapter", "Section", "Note", "Intro"])
        XCTAssertEqual(all.map(\.depth), [0, 1, 2, 1])
    }

    func testIconCatalogUsesSimpleStrokeIcons() {
        XCTAssertEqual(Set(DayDreamIconName.allCases), [
            .sidebar, .folder, .fileText, .chevronLeft, .chevronRight, .plus,
        ])
    }
}
