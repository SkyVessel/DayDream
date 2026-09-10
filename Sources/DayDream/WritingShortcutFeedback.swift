import AppKit
import QuartzCore

final class WritingBarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

extension DayDreamTextView {
    /// Handle editor shortcuts before menu equivalents (including macOS window cycling).
    func handleEditorShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, !hasMarkedText() else { return false }
        let preferences = ShortcutPreferences.shared
        if preferences.shortcut(for: .toggleFocus).matches(event) {
            EditorSettings.shared.focusModeEnabled.toggle()
            return true
        }
        for command in [ShortcutCommand.underline, .strikethrough] where preferences.shortcut(for: command).matches(event) {
            toggleDecoration(command == .underline ? .underline : .strikethrough)
            return true
        }
        if preferences.shortcut(for: .resetWritingStyle).matches(event) {
            resetSelectedAndTypingStyle()
            writingBadgeTimer?.invalidate(); writingBadge?.removeFromSuperview(); writingBadge = nil
            requestDisplayCommit()
            return true
        }
        for (index, command) in [ShortcutCommand.writingBarOne, .writingBarTwo].enumerated() {
            if preferences.shortcut(for: command).matches(event) {
                writingBarTrigger = event.keyCode
                writingBarModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
                cycleWritingBar(index)
                return true
            }
        }
        // Route formatting to the actual editor, including Finder preview windows.
        for command in [ShortcutCommand.bold, .italic, .highlight, .textColor, .inlineCode] where preferences.shortcut(for: command).matches(event) {
            switch command {
            case .bold: toggleBold()
            case .italic: toggleItalic()
            case .highlight: toggleHighlight()
            case .textColor: toggleTextColor()
            case .inlineCode: toggleInlineCode()
            default: break
            }
            return true
        }
        guard event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c": copy(nil)
        case "x": if retypeSession == nil { cut(nil) }
        case "v": if retypeSession == nil { paste(nil) }
        default: return false
        }
        requestDisplayCommit()
        return true
    }

    func showWritingBadge(_ tool: WritingTool) {
        writingBadgeTimer?.invalidate()
        writingBadge?.removeFromSuperview()
        let badge = WritingToolBadge(tool: tool)
        badge.wantsLayer = true
        addSubview(badge)
        writingBadge = badge
        let started = CACurrentMediaTime()
        let update: () -> Void = { [weak self, weak badge] in
            guard let self, let badge else { return }
            let elapsed = CACurrentMediaTime() - started
            guard elapsed < 0.5 else {
                badge.removeFromSuperview(); self.writingBadge = nil
                self.writingBadgeTimer?.invalidate(); self.writingBadgeTimer = nil
                self.requestDisplayCommit()
                return
            }
            if let caret = self.currentCaretRect() {
                let bounce = elapsed < 0.2 ? 5 * exp(-elapsed * 18) * cos(elapsed * 38) : 0
                badge.frame = NSRect(x: caret.midX - 13, y: caret.minY - 31 + bounce, width: 26, height: 26)
            }
            badge.alphaValue = min(1, elapsed / 0.055, (0.5 - elapsed) / 0.12)
            self.requestDisplayCommit()
        }
        update()
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
            guard self != nil else { timer.invalidate(); return }
            update()
        }
        writingBadgeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}

private final class WritingToolBadge: NSView {
    let tool: WritingTool
    init(tool: WritingTool) { self.tool = tool; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let color = tool.isColor ? DayDreamTheme.inlineTextColor(tool.rawValue, for: effectiveAppearance) : DayDreamTheme.text(for: effectiveAppearance)
        color.setFill()
        if tool.isColor {
            NSBezierPath(ovalIn: bounds.insetBy(dx: 6, dy: 6)).fill()
        } else if let fontName = tool.fontName {
            let text = String(tool.title.prefix(1))
            (text as NSString).draw(at: NSPoint(x: 5, y: 2), withAttributes: [.font: NSFont(name: fontName, size: 19) ?? NSFont.systemFont(ofSize: 19), .foregroundColor: color])
        } else if let image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: tool.title) {
            image.draw(in: bounds.insetBy(dx: 5, dy: 5))
        }
    }
}
