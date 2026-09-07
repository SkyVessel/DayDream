import AppKit
import XCTest
@testable import DayDream

@MainActor
final class ShortcutSettingsTests: XCTestCase {
    func testDefaultsMatchCurrentApplicationShortcuts() {
        let preferences = makePreferences()

        XCTAssertEqual(preferences.shortcut(for: .newNote), AppShortcut(key: "n", modifiers: .command))
        XCTAssertEqual(preferences.shortcut(for: .toggleSidebar), AppShortcut(key: "o", modifiers: .command))
        XCTAssertEqual(preferences.shortcut(for: .closeWindow), AppShortcut(key: "w", modifiers: .command))
        XCTAssertEqual(preferences.shortcut(for: .renameSelection), AppShortcut(key: "r", modifiers: .command))
        XCTAssertEqual(preferences.shortcut(for: .copySelection), AppShortcut(key: "c", modifiers: .command))
        XCTAssertEqual(preferences.shortcut(for: .pasteSelection), AppShortcut(key: "v", modifiers: .command))
        XCTAssertEqual(preferences.shortcut(for: .bold), AppShortcut(key: "b", modifiers: .command))
        XCTAssertEqual(preferences.shortcut(for: .italic), AppShortcut(key: "i", modifiers: .command))
        XCTAssertEqual(preferences.shortcut(for: .highlight), AppShortcut(key: "h", modifiers: [.command, .shift]))
        XCTAssertEqual(preferences.shortcut(for: .textColor), AppShortcut(key: "c", modifiers: [.command, .shift]))
        XCTAssertEqual(preferences.shortcut(for: .inlineCode), AppShortcut(key: "e", modifiers: .command))
    }

    func testCommandBackspaceRoutesToSidebarDeletionOnlyWhileSidebarIsFocused() throws {
        let preferences = makePreferences()
        let commandBackspace = try makeKeyEvent(key: "\u{7F}", modifiers: .command)

        XCTAssertNil(ShortcutEventRouter.command(
            matching: commandBackspace,
            preferences: preferences,
            isSidebarFocused: false
        ))
        XCTAssertEqual(
            ShortcutEventRouter.command(
                matching: commandBackspace,
                preferences: preferences,
                isSidebarFocused: true
            )?.rawValue,
            "deleteSelection"
        )
    }

    func testChangedShortcutPersists() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let changed = AppShortcut(key: "k", modifiers: [.command, .shift])

        ShortcutPreferences(defaults: defaults).set(changed, for: .newNote)
        let reloaded = ShortcutPreferences(defaults: defaults)

        XCTAssertEqual(reloaded.shortcut(for: .newNote), changed)
    }

    func testAssigningUsedShortcutSwapsTheTwoCommands() {
        let preferences = makePreferences()
        let oldNewNote = preferences.shortcut(for: .newNote)
        let oldFocusSidebar = preferences.shortcut(for: .toggleSidebar)

        preferences.set(oldFocusSidebar, for: .newNote)

        XCTAssertEqual(preferences.shortcut(for: .newNote), oldFocusSidebar)
        XCTAssertEqual(preferences.shortcut(for: .toggleSidebar), oldNewNote)
    }

    func testCapturesAndMatchesAKeyEventWithModifiers() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "K",
            charactersIgnoringModifiers: "k",
            isARepeat: false,
            keyCode: 40
        ))

        let shortcut = try XCTUnwrap(AppShortcut(event: event))

        XCTAssertEqual(shortcut, AppShortcut(key: "k", modifiers: [.command, .option]))
        XCTAssertTrue(shortcut.matches(event))
        XCTAssertEqual(shortcut.displayName, "⌥⌘K")
    }

    func testRejectsShortcutWithoutCommandControlOrOption() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "K",
            charactersIgnoringModifiers: "k",
            isARepeat: false,
            keyCode: 40
        ))

        XCTAssertNil(AppShortcut(event: event))
    }

    func testRecorderCapturesShortcutAndEndsRecording() throws {
        let control = ShortcutRecorderControl(
            shortcut: AppShortcut(key: "n", modifiers: .command)
        )
        var recorded: AppShortcut?
        control.onChange = { recorded = $0 }
        control.isRecording = true
        let event = try makeKeyEvent(key: "k", modifiers: [.command, .shift])

        XCTAssertTrue(control.capture(event))
        XCTAssertEqual(recorded, AppShortcut(key: "k", modifiers: [.command, .shift]))
        XCTAssertFalse(control.isRecording)
    }

    func testRouterOnlyUsesSidebarCommandsWhileSidebarIsFocused() throws {
        let preferences = makePreferences()
        let copy = try makeKeyEvent(key: "c", modifiers: .command)

        XCTAssertNil(ShortcutEventRouter.command(
            matching: copy,
            preferences: preferences,
            isSidebarFocused: false
        ))
        XCTAssertEqual(
            ShortcutEventRouter.command(
                matching: copy,
                preferences: preferences,
                isSidebarFocused: true
            ),
            .copySelection
        )
    }

    func testRouterAllowsInlineFormattingCommandsWhileEditing() throws {
        let preferences = makePreferences()
        let bold = try makeKeyEvent(key: "b", modifiers: .command)

        XCTAssertEqual(
            ShortcutEventRouter.command(
                matching: bold,
                preferences: preferences,
                isSidebarFocused: false
            ),
            .bold
        )
    }

    func testSidebarShortcutClosesAnOpenSidebarAndOpensAClosedSidebar() {
        XCTAssertEqual(
            SidebarShortcutRouting.action(isSidebarVisible: true),
            .hideAndFocusEditor
        )
        XCTAssertEqual(
            SidebarShortcutRouting.action(isSidebarVisible: false),
            .showAndFocusSidebar
        )
    }

    private func makePreferences() -> ShortcutPreferences {
        let (defaults, suiteName) = makeDefaults()
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return ShortcutPreferences(defaults: defaults)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "DayDreamTests.Shortcuts.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func makeKeyEvent(
        key: String,
        modifiers: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: key.uppercased(),
            charactersIgnoringModifiers: key,
            isARepeat: false,
            keyCode: 40
        ))
    }
}
