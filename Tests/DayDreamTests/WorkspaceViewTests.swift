import AppKit
import SwiftUI
import XCTest
@testable import DayDream

@MainActor
final class WorkspaceViewTests: XCTestCase {
    func testConfirmingKeyboardNavigationHidesTheSidebar() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let note = directory.appending(path: "Focused.md")
        try "Body".write(to: note, atomically: true, encoding: .utf8)

        let center = ShortcutCenter.shared
        center.isSidebarFocused = false
        center.sidebarNavigationURL = nil
        defer {
            center.isSidebarFocused = false
            center.sidebarNavigationURL = nil
        }

        let hostingView = NSHostingView(rootView: WorkspaceView(store: WorkspaceStore(rootURL: directory)))
        hostingView.frame = NSRect(x: 0, y: 0, width: 720, height: 880)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        center.isSidebarFocused = true
        center.sidebarNavigationURL = note
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let enter = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))

        XCTAssertTrue(window.performKeyEquivalent(with: enter))
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let hasSidebar = viewDescendants(of: hostingView).contains { view in
            String(describing: type(of: view)).contains("DraggingDestinationView")
                && view.frame.width == 250
        }
        XCTAssertFalse(hasSidebar)
        XCTAssertFalse(center.isSidebarFocused)
    }

    func testEditorToolbarMenusStayInsideUsableWindowContent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WorkspaceStore(rootURL: directory)
        let hostingView = NSHostingView(rootView: WorkspaceView(store: store))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 880),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let toolbarTargets = viewDescendants(of: hostingView).filter { view in
            String(describing: type(of: view)).contains("KeyViewProxy")
                && view.frame.minX >= 250
        }
        XCTAssertEqual(toolbarTargets.count, 2)

        for target in toolbarTargets {
            XCTAssertGreaterThanOrEqual(
                target.frame.width,
                30,
                "Toolbar control must provide a visible hit target: \(target.frame)"
            )
            XCTAssertGreaterThanOrEqual(target.frame.height, 30)
            let frame = target.convert(target.bounds, to: hostingView)
            XCTAssertTrue(hostingView.bounds.contains(frame))
        }
    }

    func testEditorBridgeLoadsMarkdownAndPublishesSerializedChanges() throws {
        let noteURL = URL(fileURLWithPath: "/tmp/First.md")
        var changes: [String] = []
        let hostingView = NSHostingView(rootView: EditorView(
            markdown: "# Title",
            documentURL: noteURL,
            onMarkdownChange: { changes.append($0) }
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 720, height: 880)
        hostingView.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(hostingView.firstMarkdownTextView)

        XCTAssertEqual(textView.string, "Title")
        textView.insertText("!", replacementRange: textView.selectedRange())
        let deadline = Date().addingTimeInterval(0.5)
        while changes.isEmpty, RunLoop.main.run(mode: .default, before: deadline) {}

        XCTAssertEqual(changes.last, "# Title!")
    }

    func testChangingDocumentURLReplacesEditorContent() throws {
        let firstURL = URL(fileURLWithPath: "/tmp/First.md")
        let secondURL = URL(fileURLWithPath: "/tmp/Second.md")
        let hostingView = NSHostingView(rootView: EditorView(
            markdown: "# First",
            documentURL: firstURL,
            onMarkdownChange: { _ in }
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 720, height: 880)
        hostingView.layoutSubtreeIfNeeded()

        hostingView.rootView = EditorView(
            markdown: "- Second",
            documentURL: secondURL,
            onMarkdownChange: { _ in }
        )
        hostingView.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(hostingView.firstMarkdownTextView)
        XCTAssertEqual(textView.string, "Second")
        XCTAssertEqual(textView.exportMarkdown(), "- Second")
    }

    func testReloadRevisionReplacesContentForTheSameDocumentURL() throws {
        let noteURL = URL(fileURLWithPath: "/tmp/First.md")
        let hostingView = NSHostingView(rootView: EditorView(
            markdown: "# First",
            documentURL: noteURL,
            reloadRevision: 0,
            onMarkdownChange: { _ in }
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 720, height: 880)
        hostingView.layoutSubtreeIfNeeded()

        hostingView.rootView = EditorView(
            markdown: "# External",
            documentURL: noteURL,
            reloadRevision: 1,
            onMarkdownChange: { _ in }
        )
        hostingView.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(hostingView.firstMarkdownTextView)
        XCTAssertEqual(textView.string, "External")
        XCTAssertEqual(textView.exportMarkdown(), "# External")
    }

    func testCoordinatorFlushPublishesPendingEditBeforeWritingDisk() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let note = directory.appending(path: "Note.md")
        try "before".write(to: note, atomically: true, encoding: .utf8)

        let document = DocumentController(autosaveDelay: 10)
        document.open(note)
        let store = WorkspaceStore(rootURL: directory)
        let coordinator = WorkspaceCoordinator()
        let hostingView = NSHostingView(rootView: EditorView(
            markdown: "before",
            documentURL: note,
            autofocus: false,
            onMarkdownChange: { document.updateMarkdown($0) }
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 720, height: 880)
        hostingView.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(hostingView.firstMarkdownTextView)
        coordinator.textView = textView
        coordinator.configure(store: store, document: document)

        textView.insertText(" after", replacementRange: textView.selectedRange())
        XCTAssertEqual(document.markdown, "before")
        coordinator.flushDocument()

        XCTAssertEqual(try String(contentsOf: note, encoding: .utf8), "before after")
    }
}

private func viewDescendants(of root: NSView) -> [NSView] {
    root.subviews + root.subviews.flatMap(viewDescendants(of:))
}

private extension NSView {
    var firstMarkdownTextView: DayDreamTextView? {
        if let textView = self as? DayDreamTextView { return textView }
        return subviews.lazy.compactMap(\.firstMarkdownTextView).first
    }
}
