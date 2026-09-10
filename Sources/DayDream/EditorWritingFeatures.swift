import AppKit
import SwiftUI

extension DayDreamTextView {
    func setOrderedStart(_ start: Int, at location: Int) {
        guard let storage = textStorage else { return }
        let range = (string as NSString).paragraphRange(for: NSRange(location: min(location, storage.length), length: 0))
        if range.length > 0 { storage.addAttribute(.dayDreamOrderedStart, value: start, range: range) }
        if location == storage.length && (storage.length == 0 || string.last?.isNewline == true) { trailingOrderedStart = start }
        typingAttributes[.dayDreamOrderedStart] = start
    }

    func writingAttributes(base: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        guard activeWritingStyle != nil || activeWritingColor != nil || activeWritingHighlight != nil else { return base }
        var clean = base
        if activeWritingStyle != nil {
            for key: NSAttributedString.Key in [.dayDreamBold, .dayDreamItalic, .dayDreamUnderline, .dayDreamStrikethrough, .dayDreamFontFamily, .dayDreamInlineCode] { clean[key] = nil }
        }
        return DayDreamTheme.inlineStyledAttributes(
            base: clean,
            bold: activeWritingStyle == .bold,
            italic: activeWritingStyle == .italic,
            inlineCode: activeWritingStyle == .inlineCode,
            linkDestination: nil,
            imageDestination: nil,
            textColorName: activeWritingColor?.rawValue,
            highlightName: activeWritingHighlight?.highlightColor,
            fontFamily: activeWritingStyle?.fontName,
            underline: activeWritingStyle == .underline,
            strikethrough: activeWritingStyle == .strikethrough,
            for: effectiveAppearance
        )
    }

    func cycleWritingBar(_ bar: Int) {
        let tools = EditorSettings.shared.writingBars[bar]
        guard !tools.isEmpty else { return }
        writingBarIndices[bar] = (writingBarIndices[bar] + 1) % tools.count
        let selected = tools[writingBarIndices[bar]]
        pendingWritingTool = selected
        showWritingBar(bar, tools: tools)
    }

    func commitWritingBarSelection() {
        guard let selected = pendingWritingTool else { return }
        let removed = writingToolIsAppliedToSelection(selected)
        if selectedRange().length > 0 || selected.blockKind != nil {
            applyWritingToolToSelection(selected)
        }
        if selected.blockKind != nil {
            // The paragraph style controls subsequent typing on this line.
        } else if selected == .plain {
            resetWritingStyle()
        } else if selected.isColor { activeWritingColor = removed ? nil : selected }
        else if selected.highlightColor != nil { activeWritingHighlight = removed ? nil : selected }
        else { activeWritingStyle = removed ? nil : selected }
        setTypingAttributes(for: currentBlockKind(at: selectedRange().location), listIndentation: currentListIndentation(at: selectedRange().location))
        pendingWritingTool = nil
        writingBarTrigger = nil
        dismissWritingBar()
        showWritingBadge(selected)
    }

    func resetWritingStyle() {
        pendingWritingTool = nil; writingBarTrigger = nil
        activeWritingColor = nil; activeWritingStyle = nil; activeWritingHighlight = nil
        writingBarIndices = [-1, -1]
        dismissWritingBar()
        setTypingAttributes(for: currentBlockKind(at: selectedRange().location), listIndentation: currentListIndentation(at: selectedRange().location))
    }

    private func showWritingBar(_ bar: Int, tools: [WritingTool]) {
        guard let window else { return }
        let panel = writingBarPanel ?? WritingBarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.level = .floating
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: TypingBarView(tools: tools, selected: writingBarIndices[bar], shortcut: ShortcutPreferences.shared.shortcut(for: bar == 0 ? .writingBarOne : .writingBarTwo).displayName))
        let size = NSSize(width: CGFloat(tools.count) * 88 + 60, height: 48)
        let anchor = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        let screen = (window.screen?.visibleFrame ?? window.frame).intersection(window.frame)
        panel.setFrame(NSRect(x: min(max(anchor.minX, screen.minX + 8), screen.maxX - size.width - 8), y: max(screen.minY + 8, anchor.minY - size.height - 10), width: size.width, height: size.height), display: true)
        if panel.parent !== window { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
        writingBarPanel = panel
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        requestDisplayCommit()
    }

    func dismissWritingBar() {
        guard writingBarTrigger == nil, let panel = writingBarPanel, panel.isVisible else { return }
        panel.orderOut(nil)
        requestDisplayCommit()
    }

    func handleWritingBarRelease(_ event: NSEvent) {
        // Keep the bar open across digit releases so Command can stay held
        // while the user cycles. Commit only when the shortcut modifiers lift.
        let heldModifiers = writingBarModifiers.intersection([.command, .option, .control])
        let releasedModifiers = event.type == .flagsChanged && !event.modifierFlags.contains(heldModifiers)
        guard releasedModifiers, pendingWritingTool != nil else { return }
        commitWritingBarSelection()
    }

    func setUltraFocus(_ enabled: Bool) {
        defer { requestDisplayCommit() }
        isUltraFocus = enabled
        enclosingScrollView?.hasVerticalScroller = !enabled
        updatePageInsets()
        sizeToFit()
        if enabled { centerUltraFocusCaret() }
        else { ultraScrollTimer?.invalidate(); ultraScrollTimer = nil; scrollRangeToVisible(selectedRange()) }
    }

    /// Follow a user-scrolled viewport without starting another centering animation.
    func followUltraFocusViewport() {
        guard !isFollowingUltraViewport, let scroll = enclosingScrollView,
              let manager = layoutManager, let container = textContainer else { return }
        ultraScrollTimer?.invalidate(); ultraScrollTimer = nil
        guard retypeSession == nil, !hasMarkedText(), !string.isEmpty else { return }
        isFollowingUltraViewport = true
        defer { isFollowingUltraViewport = false }
        manager.ensureLayout(for: container)
        let point = NSPoint(x: max(0, (currentCaretRect()?.minX ?? textContainerOrigin.x) - textContainerOrigin.x),
                            y: scroll.contentView.bounds.midY - textContainerOrigin.y)
        let glyph = manager.glyphIndex(for: point, in: container)
        guard glyph < manager.numberOfGlyphs else { return }
        let location = manager.characterIndexForGlyph(at: glyph)
        setSelectedRange(NSRange(location: min(location, string.utf16.count), length: 0))
    }

    func centerUltraFocusCaret() {
        guard isUltraFocus, !isFollowingUltraViewport, ultraScrollTimer == nil, enclosingScrollView != nil else { return }
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            guard let self, self.isUltraFocus, let scroll = self.enclosingScrollView,
                  let manager = self.layoutManager, let container = self.textContainer else { return }
            manager.ensureLayout(for: container)
            self.sizeToFit()
            let location = self.selectedRange().location
            let line: NSRect
            if location >= self.string.utf16.count && (self.string.isEmpty || self.string.hasSuffix("\n")) {
                line = manager.extraLineFragmentRect
            } else {
                let glyph = manager.glyphIndexForCharacter(at: min(location, max(self.string.utf16.count - 1, 0)))
                guard glyph < manager.numberOfGlyphs else { return }
                line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            let desired = max(0, min(self.bounds.height - scroll.contentSize.height, self.textContainerOrigin.y + line.midY - scroll.contentSize.height / 2))
            let clip = scroll.contentView
            let delta = desired - clip.bounds.minY
            let next = abs(delta) < 0.4 ? desired : clip.bounds.minY + delta * 0.19
            self.isScrollingUltraCaret = true
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: next))
            scroll.reflectScrolledClipView(clip)
            self.isScrollingUltraCaret = false
            if abs(delta) < 0.4 { self.ultraScrollTimer?.invalidate(); self.ultraScrollTimer = nil }
        }
        ultraScrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func toggleRetype() {
        if retypeSession != nil { stopRetype(); return }
        guard !hasMarkedText() else { return }
        let session = RetypeSession(text: string, selection: selectedRange())
        guard !session.isComplete else { return }
        closeSlashCommandMenu(); hideFormatPanel()
        resetFocusAppearance()
        retypeSession = session
        isEditable = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        retypeStateDidChange?(true)
        window?.makeFirstResponder(self)
        updateRetypeAppearance()
    }

    func handleRetypeInput(_ input: String) {
        guard var session = retypeSession else { return }
        retypeMarkedText = ""
        let before = session.cursor
        session.type(input)
        retypeSession = session
        updateRetypeAppearance()
        for index in before..<session.cursor {
            (layoutManager as? TypingLayoutManager)?.reveal(session.targets[index].range)
        }
        if session.isComplete { stopRetype(restoreSelection: false) }
    }

    func updateRetypeAppearance() {
        defer { requestDisplayCommit() }
        guard let session = retypeSession else { return }
        setSelectedRange(NSRange(location: session.location, length: 0))
        applyRetypeColors()
        if isUltraFocus { centerUltraFocusCaret() } else { scrollRangeToVisible(selectedRange()) }
    }

    func applyRetypeColors() {
        guard let session = retypeSession, let layoutManager, let storage = textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        layoutManager.addTemporaryAttribute(.foregroundColor, value: DayDreamTheme.text(for: effectiveAppearance).withAlphaComponent(0.22), forCharacterRange: full)
        for (index, correct) in session.results {
            let range = session.targets[index].range
            if correct { layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range) }
            else { layoutManager.addTemporaryAttribute(.foregroundColor, value: NSColor(srgbRed: 0.86, green: 0.60, blue: 0.66, alpha: 0.7), forCharacterRange: range) }
        }
        needsDisplay = true
    }

    func stopRetype(restoreSelection: Bool = true) {
        defer { requestDisplayCommit() }
        guard let session = retypeSession else { return }
        retypeSession = nil
        retypeMarkedText = ""
        isEditable = true
        isAutomaticSpellingCorrectionEnabled = EditorSettings.shared.automaticSpellingCorrectionEnabled
        isContinuousSpellCheckingEnabled = EditorSettings.shared.automaticSpellingCorrectionEnabled
        layoutManager?.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: string.utf16.count))
        (layoutManager as? TypingLayoutManager)?.clearReveals()
        if restoreSelection { setSelectedRange(session.originalSelection) }
        resetFocusAppearance(); updateFocusAppearance()
        retypeStateDidChange?(false)
        needsDisplay = true
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if retypeSession != nil {
            retypeMarkedText = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
            return
        }
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    override func hasMarkedText() -> Bool {
        retypeSession != nil ? !retypeMarkedText.isEmpty : super.hasMarkedText()
    }

    override func markedRange() -> NSRange {
        if let session = retypeSession {
            return retypeMarkedText.isEmpty ? NSRange(location: NSNotFound, length: 0) : NSRange(location: session.location, length: 0)
        }
        return super.markedRange()
    }

    override func unmarkText() {
        if retypeSession != nil { retypeMarkedText = ""; return }
        super.unmarkText()
    }

    override func keyDown(with event: NSEvent) {
        if retypeSession != nil {
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            if hasMarkedText() { interpretKeyEvents([event]); return }
            if event.keyCode == 53 { stopRetype() }
            else if event.keyCode == 51 { retypeSession?.backspace(); updateRetypeAppearance() }
            else if modifiers.isEmpty { interpretKeyEvents([event]) }
            return
        }
        super.keyDown(with: event)
    }
}

private struct TypingBarView: View {
    let tools: [WritingTool]
    let selected: Int
    let shortcut: String
    var body: some View {
        HStack(spacing: 4) {
            Text(shortcut).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 44)
            ForEach(Array(tools.enumerated()), id: \.offset) { index, tool in
                HStack(spacing: 5) {
                    Image(systemName: tool.symbol)
                        .foregroundStyle(tool.isColor ? Color(nsColor: DayDreamTheme.inlineTextColor(tool.rawValue, for: NSApp.effectiveAppearance)) : Color.primary)
                    Text(tool.title)
                }
                .font(.system(size: 12, weight: index == selected ? .semibold : .regular))
                .frame(width: 84, height: 34)
                .background(index == selected ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
    }
}
