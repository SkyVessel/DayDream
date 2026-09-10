import AppKit
import Combine
import SwiftUI

enum ShortcutCommand: String, CaseIterable, Codable, Identifiable, Sendable {
    case historyBack, historyForward, focusLeftPane, focusRightPane
    case newNote, searchFiles
    case toggleSidebar = "focusSidebar"
    case closeWindow
    case renameSelection
    case copySelection
    case pasteSelection
    case deleteSelection
    case bold
    case italic
    case underline, strikethrough, toggleFocus
    case highlight
    case textColor
    case inlineCode
    case writingBarOne, writingBarTwo, resetWritingStyle, enterUltraFocus, exitUltraFocus, retype

    var id: String { rawValue }

    var defaultShortcut: AppShortcut {
        switch self {
        case .historyBack: AppShortcut(key: "\u{F702}", modifiers: [.control, .option])
        case .historyForward: AppShortcut(key: "\u{F703}", modifiers: [.control, .option])
        case .focusLeftPane: AppShortcut(key: "\u{F702}", modifiers: [.option, .command])
        case .focusRightPane: AppShortcut(key: "\u{F703}", modifiers: [.option, .command])
        case .searchFiles: AppShortcut(key: " ", modifiers: .option)
        case .newNote: AppShortcut(key: "n", modifiers: .command)
        case .toggleSidebar: AppShortcut(key: "o", modifiers: .command)
        case .closeWindow: AppShortcut(key: "w", modifiers: .command)
        case .renameSelection: AppShortcut(key: "r", modifiers: .command)
        case .copySelection: AppShortcut(key: "c", modifiers: .command)
        case .pasteSelection: AppShortcut(key: "v", modifiers: .command)
        case .deleteSelection: AppShortcut(key: "\u{7F}", modifiers: .command)
        case .bold: AppShortcut(key: "b", modifiers: .command)
        case .underline: AppShortcut(key: "u", modifiers: .command)
        case .strikethrough: AppShortcut(key: "x", modifiers: [.command, .shift])
        case .toggleFocus: AppShortcut(key: "f", modifiers: [.control, .option])
        case .italic: AppShortcut(key: "i", modifiers: .command)
        case .highlight: AppShortcut(key: "h", modifiers: [.command, .shift])
        case .textColor: AppShortcut(key: "c", modifiers: [.command, .shift])
        case .inlineCode: AppShortcut(key: "e", modifiers: .command)
        case .writingBarOne: AppShortcut(key: "1", modifiers: .command)
        case .writingBarTwo: AppShortcut(key: "2", modifiers: .command)
        case .resetWritingStyle: AppShortcut(key: "3", modifiers: .command)
        case .enterUltraFocus: AppShortcut(key: "\u{F700}", modifiers: [.option, .command])
        case .exitUltraFocus: AppShortcut(key: "\u{F701}", modifiers: [.option, .command])
        case .retype: AppShortcut(key: "r", modifiers: [.control, .option])
        }
    }
}

struct AppShortcut: Codable, Equatable, Hashable, Sendable {
    let key: String
    private let modifiersRawValue: UInt

    init(key: String, modifiers: NSEvent.ModifierFlags) {
        self.key = Self.normalizedKey(key)
        modifiersRawValue = Self.relevantModifiers(modifiers).rawValue
    }

    init?(event: NSEvent) {
        guard event.type == .keyDown,
              let characters = event.charactersIgnoringModifiers,
              characters.count == 1 else { return nil }
        let modifiers = Self.relevantModifiers(event.modifierFlags)
        guard !modifiers.intersection([.command, .control, .option]).isEmpty else {
            return nil
        }
        self.init(key: event.keyCode == 50 && !modifiers.contains(.shift) ? "`" : characters, modifiers: modifiers)
    }

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiersRawValue)
    }

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.command) { result.insert(.command) }
        return result
    }

    var keyEquivalent: KeyEquivalent {
        switch key {
        case "\u{F700}": .upArrow
        case "\u{F701}": .downArrow
        case "\u{F702}": .leftArrow
        case "\u{F703}": .rightArrow
        case "\r": .return
        case "\t": .tab
        case "\u{1B}": .escape
        case "\u{7F}": .delete
        case " ": .space
        default: KeyEquivalent(Character(key))
        }
    }

    var displayName: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        let keyName = switch key {
        case "\u{F700}": "↑"
        case "\u{F701}": "↓"
        case "\u{F702}": "←"
        case "\u{F703}": "→"
        case "\r": "↩"
        case "\t": "⇥"
        case "\u{1B}": "⎋"
        case "\u{7F}": "⌫"
        case " ": "Space"
        default: key.uppercased()
        }
        result += keyName
        return result
    }

    func matches(_ event: NSEvent) -> Bool {
        guard let eventShortcut = AppShortcut(event: event) else { return false }
        return eventShortcut == AppShortcut(key: key, modifiers: modifiers)
    }

    private static func normalizedKey(_ key: String) -> String {
        if key == "·" { return "`" }
        return key.count == 1 ? key.lowercased() : key
    }

    private static func relevantModifiers(
        _ modifiers: NSEvent.ModifierFlags
    ) -> NSEvent.ModifierFlags {
        modifiers.intersection([.command, .control, .option, .shift])
    }
}

@MainActor
final class ShortcutPreferences: ObservableObject {
    static let shared = ShortcutPreferences()

    @Published private(set) var assignments: [ShortcutCommand: AppShortcut]

    private let defaults: UserDefaults
    private static let defaultsKey = "app.shortcuts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored: [String: AppShortcut]
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: AppShortcut].self, from: data) {
            stored = decoded
        } else {
            stored = [:]
        }
        assignments = Dictionary(uniqueKeysWithValues: ShortcutCommand.allCases.map {
            ($0, stored[$0.rawValue] ?? $0.defaultShortcut)
        })
    }

    func shortcut(for command: ShortcutCommand) -> AppShortcut {
        assignments[command] ?? command.defaultShortcut
    }

    func set(_ shortcut: AppShortcut, for command: ShortcutCommand) {
        let previous = self.shortcut(for: command)
        guard previous != shortcut else { return }
        if let conflictingCommand = ShortcutCommand.allCases.first(where: {
            $0 != command && self.shortcut(for: $0) == shortcut
        }) {
            assignments[conflictingCommand] = previous
        }
        assignments[command] = shortcut
        persist()
    }

    func resetToDefaults() {
        assignments = Dictionary(uniqueKeysWithValues: ShortcutCommand.allCases.map {
            ($0, $0.defaultShortcut)
        })
        persist()
    }

    func command(matching event: NSEvent) -> ShortcutCommand? {
        ShortcutCommand.allCases.first { shortcut(for: $0).matches(event) }
    }

    private func persist() {
        let encoded = Dictionary(uniqueKeysWithValues: assignments.map {
            ($0.key.rawValue, $0.value)
        })
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
