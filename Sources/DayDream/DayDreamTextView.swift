import AppKit

/// DayDream 编辑器核心：纯文本 NSTextView。
///
/// 默认的 macOS 光标是闪烁 + 闪现移动的。这里完全接管光标的绘制：
/// 隐藏系统光标，自己维护一个「显示位置」与「目标位置」，
/// 用 60fps 的缓动插值让光标平缓地滑向目标，永不瞬移、永不闪烁。
final class DayDreamTextView: NSTextView {

    var markdownDidChange: ((String) -> Void)?
    private var isLoadingDocument = false
    private lazy var slashPanel = SlashCommandPanel()
    private var selectedSlashCommandIndex = 0
    private(set) var isSlashCommandMenuOpen = false

    // MARK: - 光标状态

    private var caretWidth: CGFloat { 2.0 * zoomScale }
    /// 当前屏幕上实际绘制的光标位置（动画中间值）。
    private var caretRect: NSRect?
    /// 光标应该到达的位置。
    private var caretTarget: NSRect?
    /// 当前绘制的光标不透明度。
    private var caretAlpha: CGFloat = 0
    private var caretAlphaTarget: CGFloat = 0
    private var lastDrawnCaretRect: NSRect?
    private var animationTimer: Timer?

    // MARK: - 页面缩放

    private let minimumZoomScale: CGFloat = 0.5
    private let maximumZoomScale: CGFloat = 2.0
    private let zoomStep: CGFloat = 0.1
    private let minimumHorizontalInset: CGFloat = 32
    /// 一行有多长：由设置页调整，内容栏始终居中。
    private var maximumContentWidth: CGFloat { EditorSettings.shared.contentWidth }
    private let verticalInset: CGFloat = 40
    private var zoomScale: CGFloat = 1

    // MARK: - 初始化

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isRichText = false
        allowsUndo = true
        usesFontPanel = false
        usesRuler = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false

        // 隐藏系统光标的颜色（绘制也已在下方被禁用）。
        insertionPointColor = .clear

        applyTheme()

        // 设置页改动（行宽 / 行距）实时生效。
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsDidChange),
            name: EditorSettings.didChangeNotification, object: nil)
    }

    // MARK: - 主题

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyTheme()
        // 窗口焦点变化时光标淡入 / 淡出。
        if let window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowKeyChanged),
                name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowKeyChanged),
                name: NSWindow.didResignKeyNotification, object: window)
        }
    }

    private func applyTheme() {
        let appearance = effectiveAppearance
        let attributes = DayDreamTheme.textAttributes(for: appearance, scale: zoomScale)
        backgroundColor = DayDreamTheme.background(for: appearance)
        enclosingScrollView?.drawsBackground = true
        enclosingScrollView?.backgroundColor = DayDreamTheme.background(for: appearance)
        font = attributes[.font] as? NSFont
        updatePageInsets()
        selectedTextAttributes = [
            .backgroundColor: DayDreamTheme.selection(for: appearance),
            .foregroundColor: DayDreamTheme.text(for: appearance),
        ]
        typingAttributes = attributes.merging([.dayDreamBlockKind: MarkdownBlockKind.body]) { _, new in new }

        // 按段落类型重建视觉属性，同时保留块语义。
        if let storage = textStorage, storage.length > 0 {
            storage.beginEditing()
            var location = 0
            while location < storage.length {
                let paragraphRange = (storage.string as NSString).paragraphRange(
                    for: NSRange(location: location, length: 0)
                )
                let kind = storage.attribute(
                    .dayDreamBlockKind,
                    at: location,
                    effectiveRange: nil
                ) as? MarkdownBlockKind ?? .body
                storage.addAttributes(
                    DayDreamTheme.textAttributes(
                        for: appearance,
                        scale: zoomScale,
                        blockKind: kind
                    ),
                    range: paragraphRange
                )
                storage.addAttribute(.dayDreamBlockKind, value: kind, range: paragraphRange)
                location = NSMaxRange(paragraphRange)
            }
            storage.endEditing()
        }
        updateTypingAttributesForSelection()
        needsDisplay = true
    }

    func load(markdown: String) {
        closeSlashCommandMenu()
        isLoadingDocument = true
        let document = MarkdownDocumentCodec.parse(markdown)
        let value = MarkdownTextStorage.attributedString(
            from: document,
            appearance: effectiveAppearance,
            scale: zoomScale
        )
        textStorage?.setAttributedString(value)
        setSelectedRange(NSRange(location: value.length, length: 0))
        let lastKind = document.blocks.last?.kind ?? .body
        setTypingAttributes(for: lastKind)
        isLoadingDocument = false
        updateCaret(animated: false)
    }

    func exportMarkdown() -> String {
        guard let storage = textStorage else { return "" }
        return MarkdownDocumentCodec.serialize(
            MarkdownTextStorage.document(
                from: storage,
                fallbackKind: currentBlockKind(at: selectedRange.location)
            )
        )
    }

    func currentBlockKind(at location: Int) -> MarkdownBlockKind {
        guard let storage = textStorage, storage.length > 0 else {
            return typingAttributes[.dayDreamBlockKind] as? MarkdownBlockKind ?? .body
        }
        if location >= storage.length, storage.string.last?.isNewline == true {
            return typingAttributes[.dayDreamBlockKind] as? MarkdownBlockKind ?? .body
        }
        let index = min(max(location, 0), storage.length - 1)
        return storage.attribute(.dayDreamBlockKind, at: index, effectiveRange: nil)
            as? MarkdownBlockKind ?? .body
    }

    func setTypingAttributes(for kind: MarkdownBlockKind) {
        var attributes = DayDreamTheme.textAttributes(
            for: effectiveAppearance,
            scale: zoomScale,
            blockKind: kind
        )
        attributes[.dayDreamBlockKind] = kind
        typingAttributes = attributes
    }

    /// - Parameter updatesTypingAttributes: 是否同步更新打字属性。
    ///   只有「修改的段落就是光标所在段落」的调用者才应该传 true；
    ///   点击其他段落的 checkbox 这类跨段落修改必须传 false，
    ///   否则会把光标处（尤其是文末幻影空行）污染成被点击段落的类型。
    func applyBlockKind(
        _ kind: MarkdownBlockKind,
        at location: Int,
        updatesTypingAttributes: Bool = true
    ) {
        guard let storage = textStorage else { return }
        let value = storage.string as NSString
        let safeLocation = min(max(location, 0), value.length)
        let paragraphRange = value.paragraphRange(
            for: NSRange(location: safeLocation, length: 0)
        )
        let availableLength = max(storage.length - paragraphRange.location, 0)
        let attributedRange = NSRange(
            location: paragraphRange.location,
            length: min(paragraphRange.length, availableLength)
        )
        if attributedRange.length > 0 {
            storage.addAttributes(
                DayDreamTheme.textAttributes(
                    for: effectiveAppearance,
                    scale: zoomScale,
                    blockKind: kind
                ),
                range: attributedRange
            )
            storage.addAttribute(.dayDreamBlockKind, value: kind, range: attributedRange)
        }
        if updatesTypingAttributes {
            setTypingAttributes(for: kind)
        }
        needsDisplay = true
    }

    private func notifyMarkdownChange() {
        guard !isLoadingDocument else { return }
        markdownDidChange?(exportMarkdown())
    }

    private func updateTypingAttributesForSelection() {
        setTypingAttributes(for: currentBlockKind(at: selectedRange.location))
    }

    private func updatePageInsets() {
        let centeredInset = max((bounds.width - maximumContentWidth) / 2, 0)
        textContainerInset = NSSize(
            width: max(minimumHorizontalInset * zoomScale, centeredInset),
            height: verticalInset * zoomScale
        )
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.type == .keyDown,
              modifiers.subtracting(.shift) == .command else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.charactersIgnoringModifiers {
        case "+", "=":
            changeZoom(by: zoomStep)
            return true
        case "-", "_":
            changeZoom(by: -zoomStep)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let replacement = replacementRange.location == NSNotFound
            ? selectedRange
            : replacementRange
        if !hasMarkedText(),
           replacement.length == 0,
           (insertString as? String) == " ",
           let trigger = MarkdownEditingController.trigger(
               in: string,
               caretLocation: replacement.location
           ),
           shouldChangeText(in: trigger.replacementRange, replacementString: "") {
            textStorage?.replaceCharacters(in: trigger.replacementRange, with: "")
            setSelectedRange(NSRange(location: trigger.replacementRange.location, length: 0))
            applyBlockKind(trigger.kind, at: trigger.replacementRange.location)
            didChangeText()
            return
        }
        super.insertText(insertString, replacementRange: replacementRange)
        if !hasMarkedText(), (insertString as? String) == "/", currentParagraphText == "/" {
            openSlashCommandMenu()
        } else if isSlashCommandMenuOpen {
            closeSlashCommandMenu()
        }
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(NSResponder.deleteBackward(_:)),
           !hasMarkedText(),
           selectedRange.length == 0 {
            if isSlashCommandMenuOpen {
                closeSlashCommandMenu()
                super.doCommand(by: selector)
                return
            }

            let kind = currentBlockKind(at: selectedRange.location)
            if kind != .body, isAtStartOfCurrentParagraph {
                applyBlockKind(.body, at: selectedRange.location)
                notifyMarkdownChange()
                updateCaret(animated: true)
                return
            }
        }

        if isSlashCommandMenuOpen, !hasMarkedText() {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                moveSlashSelection(by: -1)
                return
            case #selector(NSResponder.moveDown(_:)):
                moveSlashSelection(by: 1)
                return
            case #selector(NSResponder.insertNewline(_:)):
                let commands = SlashCommandCatalog.all
                guard commands.indices.contains(selectedSlashCommandIndex) else { return }
                applySlashCommand(commands[selectedSlashCommandIndex].kind)
                return
            case #selector(NSResponder.cancelOperation(_:)):
                closeSlashCommandMenu()
                return
            default:
                break
            }
        }

        guard selector == #selector(NSResponder.insertNewline(_:)),
              !hasMarkedText(),
              selectedRange.length == 0,
              isAtEndOfCurrentParagraph else {
            super.doCommand(by: selector)
            return
        }

        let kind = currentBlockKind(at: selectedRange.location)
        guard kind != .body else {
            super.doCommand(by: selector)
            return
        }
        let currentText = currentParagraphText
        guard let nextKind = MarkdownEditingController.nextKind(
            after: kind,
            currentText: currentText
        ) else {
            applyBlockKind(.body, at: selectedRange.location)
            notifyMarkdownChange()
            return
        }

        super.doCommand(by: selector)
        applyBlockKind(nextKind, at: selectedRange.location)
        notifyMarkdownChange()
    }

    private func openSlashCommandMenu() {
        selectedSlashCommandIndex = 0
        isSlashCommandMenuOpen = true
        guard window != nil else { return }
        let anchor = firstRect(forCharacterRange: selectedRange, actualRange: nil)
        slashPanel.show(
            commands: SlashCommandCatalog.all,
            selectedIndex: selectedSlashCommandIndex,
            screenAnchor: anchor,
            onDismiss: { [weak self] in
                self?.isSlashCommandMenuOpen = false
            }
        ) { [weak self] kind in
            self?.applySlashCommand(kind)
        }
    }

    private func moveSlashSelection(by delta: Int) {
        selectedSlashCommandIndex = SlashCommandNavigation.moved(
            from: selectedSlashCommandIndex,
            by: delta,
            count: SlashCommandCatalog.all.count
        )
        slashPanel.updateSelection(selectedSlashCommandIndex)
    }

    func applySlashCommand(_ kind: MarkdownBlockKind) {
        guard isSlashCommandMenuOpen else { return }
        let value = string as NSString
        let location = min(selectedRange.location, value.length)
        let paragraphRange = value.paragraphRange(
            for: NSRange(location: location, length: 0)
        )
        let paragraph = value.substring(with: paragraphRange).trimmingCharacters(in: .newlines)
        guard paragraph == "/" else {
            closeSlashCommandMenu()
            return
        }
        let slashRange = NSRange(location: paragraphRange.location, length: 1)
        closeSlashCommandMenu()
        guard shouldChangeText(in: slashRange, replacementString: "") else { return }
        textStorage?.replaceCharacters(in: slashRange, with: "")
        setSelectedRange(NSRange(location: slashRange.location, length: 0))
        applyBlockKind(kind, at: slashRange.location)
        didChangeText()
    }

    private func closeSlashCommandMenu() {
        guard isSlashCommandMenuOpen || slashPanel.isVisible else { return }
        isSlashCommandMenuOpen = false
        slashPanel.closePanel()
    }

    private var currentParagraphText: String {
        let value = string as NSString
        let location = min(selectedRange.location, value.length)
        let paragraphRange = value.paragraphRange(
            for: NSRange(location: location, length: 0)
        )
        return value.substring(with: paragraphRange)
            .trimmingCharacters(in: .newlines)
    }

    private var isAtEndOfCurrentParagraph: Bool {
        let value = string as NSString
        let location = min(selectedRange.location, value.length)
        let paragraphRange = value.paragraphRange(
            for: NSRange(location: location, length: 0)
        )
        let content = value.substring(with: paragraphRange) as NSString
        var contentLength = content.length
        while contentLength > 0 {
            let scalar = content.character(at: contentLength - 1)
            guard scalar == 10 || scalar == 13 else { break }
            contentLength -= 1
        }
        return selectedRange.location == paragraphRange.location + contentLength
    }

    private var isAtStartOfCurrentParagraph: Bool {
        let value = string as NSString
        let location = min(selectedRange.location, value.length)
        let paragraphRange = value.paragraphRange(
            for: NSRange(location: location, length: 0)
        )
        return selectedRange.location == paragraphRange.location
    }

    // MARK: - Cmd+Backspace 连续向上删行

    /// 原生 deleteToBeginningOfLine 在行首时是空操作（不删换行符），
    /// 导致空行上第二次 Cmd+Backspace 卡住。这里在行首时退化为普通退格，
    /// 删掉上一行的换行符，让连续 Cmd+Backspace 可以一路向上吃行。
    override func deleteToBeginningOfLine(_ sender: Any?) {
        guard !hasMarkedText(), selectedRange.length == 0 else {
            super.deleteToBeginningOfLine(sender)
            return
        }
        if isAtBeginningOfVisualLine {
            deleteBackward(sender)
        } else {
            super.deleteToBeginningOfLine(sender)
        }
    }

    override func deleteToBeginningOfParagraph(_ sender: Any?) {
        guard !hasMarkedText(), selectedRange.length == 0 else {
            super.deleteToBeginningOfParagraph(sender)
            return
        }
        if isAtStartOfCurrentParagraph {
            deleteBackward(sender)
        } else {
            super.deleteToBeginningOfParagraph(sender)
        }
    }

    /// 光标是否位于视觉行行首（含文末换行后的幻影行）。
    private var isAtBeginningOfVisualLine: Bool {
        guard let storage = textStorage, storage.length > 0 else { return true }
        let location = selectedRange.location

        // 文末幻影行（字符串以换行结尾、光标在末尾）：必然是新行行首。
        if location >= storage.length, storage.string.last?.isNewline == true {
            return true
        }

        guard let layoutManager, let textContainer else {
            return isAtStartOfCurrentParagraph
        }
        layoutManager.ensureLayout(for: textContainer)
        let glyphIndex = layoutManager.glyphIndexForCharacter(
            at: min(location, storage.length - 1)
        )
        var lineGlyphRange = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
        let lineStart = layoutManager.characterIndexForGlyph(at: lineGlyphRange.location)
        return location <= lineStart
    }

    private func changeZoom(by delta: CGFloat) {
        let steppedScale = ((zoomScale + delta) * 10).rounded() / 10
        let newScale = min(max(steppedScale, minimumZoomScale), maximumZoomScale)
        guard newScale != zoomScale else { return }

        zoomScale = newScale
        applyTheme()
        if let textContainer {
            layoutManager?.ensureLayout(for: textContainer)
        }
        updateCaret(animated: false)
    }

    // MARK: - 禁用系统光标

    /// 系统光标的绘制入口——留空，彻底接管。
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        // 什么都不画。
    }

    /// 系统更新光标状态（闪烁计时器）的入口——改为驱动我们自己的平滑光标。
    override func updateInsertionPointStateAndRestartTimer(_ restartTimer: Bool) {
        // 故意不调用 super：不启动闪烁计时器。
        updateCaret(animated: true)
    }

    // MARK: - 光标定位

    /// 计算插入点在视图坐标系中的位置。
    private func currentCaretRect() -> NSRect? {
        guard selectedRange.length == 0,
              let window,
              window.firstResponder == self else { return nil }

        let screen = firstRect(forCharacterRange: selectedRange, actualRange: nil)
        guard !screen.isNull, screen.size.height > 0 else { return nil }

        let activeFont = typingAttributes[.font] as? NSFont ?? font ?? DayDreamTheme.font
        let inWindow = window.convertFromScreen(screen)
        var rect = convert(inWindow, from: nil)
        rect.origin.x -= caretWidth / 2
        rect.size.width = caretWidth

        if let layoutManager, let textContainer, let storage = textStorage {
            layoutManager.ensureLayout(for: textContainer)
            let location = selectedRange.location
            let endsWithLineBreak = storage.length > 0
                && location == storage.length
                && storage.string.last?.isNewline == true

            if storage.length == 0 || endsWithLineBreak {
                let lineRect = layoutManager.extraLineFragmentRect
                rect.origin.y = textContainerOrigin.y + lineRect.maxY
                    - activeFont.ascender + activeFont.descender
            } else {
                let characterIndex = min(location, storage.length - 1)
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
                let lineRect = layoutManager.lineFragmentRect(
                    forGlyphAt: glyphIndex,
                    effectiveRange: nil
                )
                let glyphLocation = layoutManager.location(forGlyphAt: glyphIndex)
                let baseline = textContainerOrigin.y + lineRect.minY + glyphLocation.y
                rect.origin.y = baseline - activeFont.ascender
            }
        } else {
            rect.origin.y = rect.midY - (activeFont.ascender - activeFont.descender) / 2
        }
        rect.size.height = activeFont.ascender - activeFont.descender
        return rect
    }

    private func updateCaret(animated: Bool) {
        let target = currentCaretRect()
        caretTarget = target
        caretAlphaTarget = target != nil ? 1 : 0

        guard animated else {
            caretRect = target
            caretAlpha = caretAlphaTarget
            invalidateCaretArea()
            return
        }
        // 如果光标还没出现过，先落位再淡入，不做长距离滑动。
        if caretRect == nil, let target {
            caretRect = target
        }
        startAnimationIfNeeded()
    }

    // MARK: - 平滑动画（60fps 缓动插值）

    private func startAnimationIfNeeded() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0,
                          target: self,
                          selector: #selector(animationTick),
                          userInfo: nil,
                          repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    @objc private func animationTick() {
        var settled = true
        let ease: CGFloat = 0.3 // 指数缓动系数：越大越快

        // 位置插值
        if let target = caretTarget, let current = caretRect {
            var next = current
            next.origin.x += (target.origin.x - current.origin.x) * ease
            next.origin.y += (target.origin.y - current.origin.y) * ease
            next.size.width = target.size.width
            next.size.height += (target.size.height - current.size.height) * ease

            let closeEnough = abs(target.origin.x - next.origin.x) < 0.3
                && abs(target.origin.y - next.origin.y) < 0.3
                && abs(target.size.height - next.size.height) < 0.3
            if closeEnough {
                caretRect = target
            } else {
                caretRect = next
                settled = false
            }
        }

        // 透明度插值（淡入 / 淡出）
        caretAlpha += (caretAlphaTarget - caretAlpha) * 0.28
        if abs(caretAlphaTarget - caretAlpha) < 0.03 {
            caretAlpha = caretAlphaTarget
        } else {
            settled = false
        }

        if caretTarget == nil && caretAlpha == 0 {
            caretRect = nil
        }

        invalidateCaretArea()
        if settled { stopAnimation() }
    }

    private func invalidateCaretArea() {
        if let rect = caretRect { setNeedsDisplay(rect.insetBy(dx: -2, dy: -2)) }
        if let rect = lastDrawnCaretRect { setNeedsDisplay(rect.insetBy(dx: -2, dy: -2)) }
        lastDrawnCaretRect = caretRect
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBlockDecorations(in: dirtyRect)
        drawHeadingPlaceholder(in: dirtyRect)
        guard let rect = caretRect, caretAlpha > 0 else { return }
        DayDreamTheme.caret(for: effectiveAppearance)
            .withAlphaComponent(caretAlpha)
            .setFill()
        NSBezierPath(roundedRect: rect,
                     xRadius: rect.width / 2,
                     yRadius: rect.width / 2).fill()
    }

    private func drawBlockDecorations(in dirtyRect: NSRect) {
        let decorations = BlockDecorationLayout.decorations(
            in: self,
            textContainerOrigin: textContainerOrigin,
            scale: zoomScale
        )
        let color = DayDreamTheme.text(for: effectiveAppearance).withAlphaComponent(0.72)

        for decoration in decorations where decoration.markerRect.intersects(dirtyRect) {
            if let label = decoration.label {
                let paragraph = NSMutableParagraphStyle()
                // 序号右对齐贴近文字（长序号向左侧缩进区溢出），圆点居中。
                paragraph.alignment = decoration.kind == .numbered ? .right : .center
                (label as NSString).draw(
                    in: decoration.markerRect,
                    withAttributes: [
                        .font: BlockDecorationLayout.markerFont(scale: zoomScale),
                        .foregroundColor: color,
                        .paragraphStyle: paragraph,
                    ]
                )
                continue
            }

            guard case let .todo(checked) = decoration.kind else { continue }
            let box = decoration.markerRect.insetBy(dx: 1.5 * zoomScale, dy: 1.5 * zoomScale)
            let path = NSBezierPath(roundedRect: box, xRadius: 3 * zoomScale, yRadius: 3 * zoomScale)
            path.lineWidth = 1.6 * zoomScale
            if checked {
                DayDreamTheme.caret(for: effectiveAppearance).withAlphaComponent(0.82).setFill()
                path.fill()
                let points = TodoCheckmarkLayout.points(in: box, scale: zoomScale)
                let check = NSBezierPath()
                check.move(to: points.start)
                check.line(to: points.middle)
                check.line(to: points.end)
                check.lineWidth = 1.7 * zoomScale
                check.lineCapStyle = .round
                DayDreamTheme.background(for: effectiveAppearance).setStroke()
                check.stroke()
            } else {
                color.setStroke()
                path.stroke()
            }
        }
    }

    func headingPlaceholder(at location: Int) -> String? {
        guard case let .heading(level) = currentBlockKind(at: location) else { return nil }
        let value = string as NSString
        let safeLocation = min(max(location, 0), value.length)
        let range = value.paragraphRange(for: NSRange(location: safeLocation, length: 0))
        guard value.substring(with: range).trimmingCharacters(in: .newlines).isEmpty else {
            return nil
        }
        return "Heading \(min(max(level, 1), 4))"
    }

    private func drawHeadingPlaceholder(in dirtyRect: NSRect) {
        guard selectedRange.length == 0,
              let placeholder = headingPlaceholder(at: selectedRange.location),
              let rect = headingPlaceholderRect(at: selectedRange.location) else { return }
        guard rect.intersects(dirtyRect) else { return }
        let kind = currentBlockKind(at: selectedRange.location)
        let attributes = DayDreamTheme.textAttributes(
            for: effectiveAppearance,
            scale: zoomScale,
            blockKind: kind
        )
        let font = attributes[.font] as? NSFont ?? DayDreamTheme.font
        (placeholder as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: DayDreamTheme.text(for: effectiveAppearance).withAlphaComponent(0.28),
            .kern: DayDreamTheme.letterSpacing * zoomScale,
        ])
    }

    func headingPlaceholderRect(at location: Int) -> NSRect? {
        guard headingPlaceholder(at: location) != nil,
              let layoutManager,
              let textContainer else { return nil }
        let kind = currentBlockKind(at: location)
        let attributes = DayDreamTheme.textAttributes(
            for: effectiveAppearance,
            scale: zoomScale,
            blockKind: kind
        )
        let font = attributes[.font] as? NSFont ?? DayDreamTheme.font
        layoutManager.ensureLayout(for: textContainer)

        let safeLocation = min(max(location, 0), textStorage?.length ?? 0)
        let lineRect: NSRect
        let originY: CGFloat
        if safeLocation < (textStorage?.length ?? 0) {
            let glyph = layoutManager.glyphIndexForCharacter(at: safeLocation)
            lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let glyphLocation = layoutManager.location(forGlyphAt: glyph)
            originY = textContainerOrigin.y + lineRect.minY
                + glyphLocation.y - font.ascender
        } else {
            lineRect = layoutManager.extraLineFragmentRect
            originY = textContainerOrigin.y + lineRect.maxY
                + font.descender - font.ascender
        }

        return NSRect(
            x: textContainerOrigin.x + lineRect.minX,
            y: originY,
            width: max(bounds.width - textContainerOrigin.x, 1),
            height: max(lineRect.height, font.pointSize * 1.3)
        )
    }

    @discardableResult
    func toggleTodo(at point: NSPoint) -> Bool {
        guard let decoration = BlockDecorationLayout.decorations(
            in: self,
            textContainerOrigin: textContainerOrigin,
            scale: zoomScale
        ).first(where: { $0.markerRect.contains(point) }),
              case let .todo(checked) = decoration.kind else { return false }

        let location = decoration.characterRange.location
        undoManager?.registerUndo(withTarget: self) { textView in
            textView.setTodoChecked(checked, at: location)
        }
        setTodoChecked(!checked, at: location)
        return true
    }

    private func setTodoChecked(_ checked: Bool, at location: Int) {
        // 跨段落修改：不动光标处的打字属性，避免幻影行被污染。
        applyBlockKind(.todo(checked: checked), at: location, updatesTypingAttributes: false)
        updateTypingAttributesForSelection()
        notifyMarkdownChange()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        closeSlashCommandMenu()
        let point = convert(event.locationInWindow, from: nil)
        if toggleTodo(at: point) { return }
        super.mouseDown(with: event)
    }

    // MARK: - 光标需要更新的时机

    override func didChangeText() {
        super.didChangeText()
        notifyMarkdownChange()
        updateCaret(animated: true)
    }

    override func setSelectedRange(_ charRange: NSRange,
                                   affinity: NSSelectionAffinity,
                                   stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelectingFlag)
        updateTypingAttributesForSelection()
        updateCaret(animated: !stillSelectingFlag)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updatePageInsets()
        // 窗口缩放导致文字重排，光标直接落位。
        updateCaret(animated: false)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { updateCaret(animated: true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { updateCaret(animated: true) }
        return ok
    }

    @objc private func settingsDidChange() {
        applyTheme()
        if let textContainer {
            layoutManager?.ensureLayout(for: textContainer)
        }
        updateCaret(animated: false)
    }

    @objc private func windowKeyChanged() {
        if window?.isKeyWindow != true {
            closeSlashCommandMenu()
        }
        updateCaret(animated: true)
    }

    deinit {
        slashPanel.closePanel()
        stopAnimation()
        NotificationCenter.default.removeObserver(self)
    }
}
