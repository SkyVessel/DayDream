import Foundation
import AppKit
import SwiftUI
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
            .importDocument, .exportDocument, .more,
        ])
    }

    @MainActor
    func testIconCatalogRendersAppleSystemSymbols() throws {
        let mappings: [(DayDreamIconName, String)] = [
            (.sidebar, "sidebar.left"),
            (.folder, "folder"),
            (.fileText, "doc.text"),
            (.chevronLeft, "chevron.left"),
            (.chevronRight, "chevron.right"),
            (.plus, "plus"),
            (.importDocument, "square.and.arrow.down"),
            (.exportDocument, "square.and.arrow.up"),
            (.more, "ellipsis"),
        ]

        for (icon, systemName) in mappings {
            let actual = try renderedPixels(
                DayDreamIcon(name: icon, color: .white, strokeWidth: 1.7)
                    .frame(width: 32, height: 32)
            )
            let expected = try renderedPixels(
                Image(systemName: systemName)
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.monochrome)
                    .fontWeight(.regular)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            )
            XCTAssertEqual(actual, expected, "\(icon) must use the matching SF Symbol")
        }
    }

    @MainActor
    func testKeyboardNavigationPreviewsTheHighlightedNoteWithoutLeavingSidebarFocus() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let note = directory.appending(path: "Preview.md")
        try "Preview body".write(to: note, atomically: true, encoding: .utf8)

        let store = WorkspaceStore(rootURL: directory)
        var openedURL: URL?
        let center = ShortcutCenter.shared
        center.isSidebarFocused = true
        center.sidebarNavigationURL = nil
        defer {
            center.isSidebarFocused = false
            center.sidebarNavigationURL = nil
        }

        let hostingView = NSHostingView(rootView: SidebarView(
            store: store,
            isFullScreen: false,
            onOpenNote: { openedURL = $0 }
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 250, height: 500)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        center.sidebarNavigationURL = note
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(openedURL, note)
        XCTAssertEqual(store.selectedURL, note)
        XCTAssertTrue(center.isSidebarFocused)
    }

    @MainActor
    func testDeleteShortcutRequiresConfirmationBeforeMovingTheSelectedNoteToTrash() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let note = directory.appending(path: "Delete me.md")
        try "Keep until confirmed".write(to: note, atomically: true, encoding: .utf8)

        let store = WorkspaceStore(rootURL: directory)
        store.select(note)
        let center = ShortcutCenter.shared
        center.isSidebarFocused = true
        center.sidebarNavigationURL = note
        center.deleteSelection = {}
        defer {
            center.isSidebarFocused = false
            center.sidebarNavigationURL = nil
            center.deleteSelection = {}
        }

        let hostingView = NSHostingView(rootView: SidebarView(store: store, isFullScreen: false))
        hostingView.frame = NSRect(x: 0, y: 0, width: 250, height: 500)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        center.deleteSelection()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertTrue(FileManager.default.fileExists(atPath: note.path))
        let sheet = try XCTUnwrap(window.attachedSheet)
        let enter = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: sheet.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))
        XCTAssertTrue(sheet.performKeyEquivalent(with: enter))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertFalse(FileManager.default.fileExists(atPath: note.path))
    }

    @MainActor
    func testFolderDisclosureHasAFullRowHeightHitTarget() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory.appending(path: "Folder", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        let hostingView = NSHostingView(rootView: SidebarView(
            store: WorkspaceStore(rootURL: directory),
            isFullScreen: false
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 250, height: 500)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let rowTargets = sidebarViewDescendants(of: hostingView).filter { view in
            String(describing: type(of: view)).contains("KeyViewProxy")
                && view.frame.maxY < 440
        }
        let disclosure = try XCTUnwrap(rowTargets.min { $0.frame.minX < $1.frame.minX })
        XCTAssertGreaterThanOrEqual(disclosure.frame.width, 28)
        XCTAssertGreaterThanOrEqual(disclosure.frame.height, 28)
    }
}

private func sidebarViewDescendants(of root: NSView) -> [NSView] {
    root.subviews + root.subviews.flatMap(sidebarViewDescendants(of:))
}

@MainActor
private func renderedPixels<V: View>(_ view: V) throws -> Data {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try XCTUnwrap(renderer.nsImage)
    var rect = NSRect(origin: .zero, size: image.size)
    let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
    let representation = NSBitmapImageRep(cgImage: cgImage)
    return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
}
