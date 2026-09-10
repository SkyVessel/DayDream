import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: AppShortcut
    let onChange: (AppShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl(shortcut: shortcut)
        control.onChange = onChange
        return control
    }

    func updateNSView(_ control: ShortcutRecorderControl, context: Context) {
        control.shortcut = shortcut
        control.onChange = onChange
    }
}

final class ShortcutRecorderControl: NSView {
    var shortcut: AppShortcut {
        didSet { needsDisplay = true }
    }
    var onChange: ((AppShortcut) -> Void)?
    var isRecording = false {
        didSet { needsDisplay = true }
    }

    init(shortcut: AppShortcut) {
        self.shortcut = shortcut
        super.init(frame: NSRect(x: 0, y: 0, width: 78, height: 26))
        toolTip = L10n.t("点击后按新的快捷键", "Click, then press a new shortcut")
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 78, height: 26) }

    override func becomeFirstResponder() -> Bool {
        isRecording = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        isRecording ? capture(event) : super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        _ = capture(event)
    }

    @discardableResult
    func capture(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 53, modifiers.isEmpty {
            isRecording = false
            window?.makeFirstResponder(nil)
            return true
        }
        guard let recorded = AppShortcut(event: event) else {
            NSSound.beep()
            return true
        }
        shortcut = recorded
        onChange?(recorded)
        isRecording = false
        window?.makeFirstResponder(nil)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.18)
            : NSColor.labelColor.withAlphaComponent(0.07)
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()

        if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.65).setStroke()
            let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
            border.lineWidth = 1
            border.stroke()
        }

        let label = isRecording ? L10n.t("请按键", "Type keys") : shortcut.displayName
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(isRecording ? 0.82 : 0.72),
        ]
        let size = (label as NSString).size(withAttributes: attributes)
        (label as NSString).draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}

@MainActor
enum ShortcutEventRouter {
    static func command(
        matching event: NSEvent,
        preferences: ShortcutPreferences,
        isSidebarFocused: Bool
    ) -> ShortcutCommand? {
        guard let command = preferences.command(matching: event) else { return nil }
        switch command {
        case .renameSelection, .copySelection, .pasteSelection, .deleteSelection:
            return isSidebarFocused ? command : nil
        case .bold, .italic, .underline, .strikethrough, .highlight, .textColor, .inlineCode:
            return isSidebarFocused ? nil : command
        default:
            return command
        }
    }
}

@MainActor
final class ShortcutEventMonitor {
    static let shared = ShortcutEventMonitor()
    private var monitor: Any?
    private weak var writingEditor: DayDreamTextView?

    private init() {}

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .leftMouseDown]) { event in
            if event.type == .leftMouseDown { PaneShortcutRouting.routeMouse(event); return event }
            if event.type != .keyDown {
                (self.writingEditor ?? NSApp.keyWindow?.firstResponder as? DayDreamTextView)?.handleWritingBarRelease(event)
                return event
            }
            if let recorder = NSApp.keyWindow?.firstResponder as? ShortcutRecorderControl,
               recorder.isRecording {
                recorder.capture(event)
                return nil
            }

            if let editor = NSApp.keyWindow?.firstResponder as? DayDreamTextView,
               editor.hasMarkedText() { return event }
            if let panel = event.window as? LibrarySearchPanel { return panel.routeKey(event) }
            let activeCenter = ShortcutCenter.shared
            if let editor = NSApp.keyWindow?.firstResponder as? DayDreamTextView,
               !activeCenter.isSidebarFocused,
               (activeCenter.documentResponder == nil || activeCenter.documentResponder === editor),
               editor.handleEditorShortcut(event) {
                if editor.writingBarTrigger != nil { self.writingEditor = editor }
                return nil
            }
            let zoomModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if zoomModifiers.subtracting(.shift) == .command,
               ["+", "=", "-", "_"].contains(event.charactersIgnoringModifiers ?? ""),
               let responder = activeCenter.documentResponder, responder.performKeyEquivalent(with: event) { return nil }
            let preferences = ShortcutPreferences.shared
            let center = activeCenter
            if let command = ShortcutEventRouter.command(
                matching: event,
                preferences: preferences,
                isSidebarFocused: center.isSidebarFocused
            ) {
                switch command {
                case .searchFiles: center.searchFiles()
                case .historyBack: center.historyBack()
                case .historyForward: center.historyForward()
                case .focusLeftPane: center.focusLeftPane()
                case .focusRightPane: center.focusRightPane()
                case .newNote:
                    center.newNote()
                case .toggleSidebar:
                    center.toggleSidebar()
                case .closeWindow:
                    center.closeNote()
                case .renameSelection:
                    center.renameSelection()
                case .copySelection:
                    center.copySelection()
                case .pasteSelection:
                    center.paste()
                case .deleteSelection:
                    center.deleteSelection()
                case .bold:
                    center.toggleBold()
                case .toggleFocus:
                    EditorSettings.shared.focusModeEnabled.toggle()
                case .underline, .strikethrough:
                    (NSApp.keyWindow?.firstResponder as? DayDreamTextView)?.toggleDecoration(command == .underline ? .underline : .strikethrough)
                case .italic:
                    center.toggleItalic()
                case .highlight:
                    center.toggleHighlight()
                case .textColor:
                    center.toggleTextColor()
                case .inlineCode:
                    center.toggleInlineCode()
                case .writingBarOne, .writingBarTwo, .resetWritingStyle, .enterUltraFocus, .exitUltraFocus, .retype:
                    guard NSApp.keyWindow === center.mainWindow else { return event }
                    center.writingCommand(command)
                    (center.mainWindow?.firstResponder as? DayDreamTextView)?.requestDisplayCommit()
                }
                return nil
            }

            let defaultClose = ShortcutCommand.closeWindow.defaultShortcut
            if defaultClose.matches(event),
               preferences.shortcut(for: .closeWindow) != defaultClose {
                // 修改关闭窗口快捷键后，旧的系统 ⌘W 不再继续生效。
                return nil
            }
            return event
        }
    }
}
