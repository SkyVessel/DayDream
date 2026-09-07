import AppKit

/// DayDream 编辑器核心：纯文本 NSTextView。
///
/// 默认的 macOS 光标是闪烁 + 闪现移动的。这里完全接管光标的绘制：
/// 隐藏系统光标，自己维护一个「显示位置」与「目标位置」，
/// 用 60fps 的缓动插值让光标平缓地滑向目标，永不瞬移、永不闪烁。
final class DayDreamTextView: NSTextView {

    // The final empty paragraph has no character to carry semantic attributes.
    // Its state belongs to the document, never to the current selection.
    var trailingBlockKind: MarkdownBlockKind = .body
    var trailingListIndentation = ""
    var trailingOrderedStart = 1
    var documentURL: URL?
    var wordCountDidChange: ((Int) -> Void)?
    var retypeStateDidChange: ((Bool) -> Void)?
    var retypeSession: RetypeSession?
    var retypeMarkedText = ""
    var activeWritingStyle: WritingTool?
    var activeWritingColor: WritingTool?
    var activeWritingHighlight: WritingTool?
    var writingBarIndices = [-1, -1]
    var writingBarPanel: NSPanel?
    var writingBarTrigger: UInt16?
    var writingBarModifiers: NSEvent.ModifierFlags = .command
    var pendingWritingTool: WritingTool?
    var writingBadge: NSView?
    var writingBadgeTimer: Timer?
    var isDisplayCommitScheduled = false
    var ultraScrollTimer: Timer?
    var isUltraFocus = false
    var mediaViews: [UUID: MediaCardView] = [:]
    var isLayingOutMedia = false
    var markdownDidChange: ((String) -> Void)?
    /// 获得键盘焦点时回调（退出侧栏焦点）。
    var onBecameFirstResponder: (() -> Void)?
    private var isLoadingDocument = false
    private lazy var slashPanel = SlashCommandPanel()
    private var selectedSlashCommandIndex = 0
    private(set) var isSlashCommandMenuOpen = false
    private var isApplyingSpaceWidth = false
    private var mostRecentEditChangedCharacters = false
    private var sourcePreservation: SourcePreservingMarkdown?
    private var completionSuffix: String?
    private var pendingMarkdownNotification: DispatchWorkItem?
    private var markdownNotificationGeneration = 0
    private let markdownNotificationDelay: TimeInterval = 0.075
    private var focusedSentenceRange: NSRange?
    private var isFocusAppearanceApplied = false
    private var focusTextRevision = 0
    private var resolvedFocusTextRevision = -1

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
        registerForDraggedTypes([.fileURL, .URL, .png, .tiff])
        linkTextAttributes = [.foregroundColor: DayDreamTheme.inlineTextColor("blue", for: effectiveAppearance), .underlineStyle: 0]
        NotificationCenter.default.addObserver(self, selector: #selector(siteIconLoaded(_:)), name: .siteIconDidLoad, object: nil)
        isRichText = false
        allowsUndo = true
        usesFontPanel = false
        usesRuler = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = retypeSession == nil && EditorSettings.shared.automaticSpellingCorrectionEnabled
        isContinuousSpellCheckingEnabled = retypeSession == nil && EditorSettings.shared.automaticSpellingCorrectionEnabled
        isGrammarCheckingEnabled = false

        // 隐藏系统光标的颜色（绘制也已在下方被禁用）。
        insertionPointColor = .clear
        textStorage?.delegate = self

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
            // 滚动时隐藏样式工具条。
            enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(clipBoundsChanged),
                name: NSView.boundsDidChangeNotification,
                object: enclosingScrollView?.contentView)
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
                let indentation = storage.attribute(
                    .dayDreamListIndentation,
                    at: location,
                    effectiveRange: nil
                ) as? String ?? ""
                storage.addAttributes(
                    DayDreamTheme.textAttributes(
                        for: appearance,
                        scale: zoomScale,
                        blockKind: kind,
                        listIndentation: indentation
                    ),
                    range: paragraphRange
                )
                storage.addAttribute(.dayDreamBlockKind, value: kind, range: paragraphRange)
                storage.addAttribute(.dayDreamListIndentation, value: indentation, range: paragraphRange)
                location = NSMaxRange(paragraphRange)
            }
            storage.endEditing()
        }
        // 行内样式视觉（加粗/斜体/颜色）与空格宽度在基础属性之上重建。
        if let storage = textStorage, storage.length > 0 {
            let full = NSRange(location: 0, length: storage.length)
            refreshInlineVisuals(in: full)
            applySpaceWidth(in: full)
        }
        updateTypingAttributesForSelection()
        resetFocusAppearance()
        updateFocusAppearance()
        updateWordCompletion()
        needsDisplay = true
    }

    // MARK: - 行内样式与空格宽度

    /// 根据保留的语义键（.dayDreamBold 等）重建行内样式的视觉表现。
    /// 先收集再应用，避免在枚举过程中修改属性。
    private func refreshInlineVisuals(in range: NSRange) {
        guard let storage = textStorage, range.length > 0 else { return }
        let appearance = effectiveAppearance
        var styled: [(range: NSRange, style: InlineStyle, kind: MarkdownBlockKind, indentation: String)] = []
        // 高亮由 drawBackground 自定义绘制，避免系统整行高、直角背景。
        storage.removeAttribute(.backgroundColor, range: range)
        storage.enumerateAttributes(in: range, options: []) { attributes, subrange, _ in
            let style = InlineStyle(
                bold: attributes[.dayDreamBold] as? Bool ?? false,
                italic: attributes[.dayDreamItalic] as? Bool ?? false,
                code: attributes[.dayDreamInlineCode] as? Bool ?? false,
                linkDestination: attributes[.dayDreamLink] as? String,
                imageDestination: attributes[.dayDreamImage] as? String,
                textColor: attributes[.dayDreamTextColor] as? String,
                highlight: attributes[.dayDreamHighlight] as? String,
                fontFamily: attributes[.dayDreamFontFamily] as? String
            )
            guard !style.isPlain else { return }
            let kind = attributes[.dayDreamBlockKind] as? MarkdownBlockKind ?? .body
            let indentation = attributes[.dayDreamListIndentation] as? String ?? ""
            styled.append((subrange, style, kind, indentation))
        }
        for item in styled {
            let base = DayDreamTheme.textAttributes(
                for: appearance,
                scale: zoomScale,
                blockKind: item.kind,
                listIndentation: item.indentation
            )
            storage.addAttributes(
                DayDreamTheme.inlineStyledAttributes(
                    base: base,
                    bold: item.style.bold,
                    italic: item.style.italic,
                    inlineCode: item.style.code,
                    linkDestination: item.style.linkDestination,
                    imageDestination: item.style.imageDestination,
                    textColorName: item.style.textColor,
                    highlightName: item.style.highlight,
                    fontFamily: item.style.fontFamily,
                    for: appearance
                ),
                range: item.range
            )
        }
    }

    /// 空格宽度：在基础词距之上为空格字符额外加宽（设置页可调）。
    private func applySpaceWidth(in range: NSRange) {
        guard let storage = textStorage, range.length > 0 else { return }
        let extra = EditorSettings.shared.spaceWidth * zoomScale
        guard extra != 0 else { return }
        let widened = DayDreamTheme.letterSpacing * zoomScale + extra
        let value = storage.string as NSString
        let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: value.length))
        guard safeRange.length > 0 else { return }
        isApplyingSpaceWidth = true
        defer { isApplyingSpaceWidth = false }
        storage.beginEditing()
        for index in safeRange.location..<NSMaxRange(safeRange) {
            if value.character(at: index) == 32 { // 空格
                storage.addAttribute(.kern, value: widened, range: NSRange(location: index, length: 1))
            }
        }
        storage.endEditing()
    }

    /// 重建指定范围的段落基础属性 + 行内样式 + 空格宽度（工具条改动后调用）。
    func rebuildAttributes(in range: NSRange) {
        guard let storage = textStorage, storage.length > 0 else { return }
        let value = storage.string as NSString
        let paragraphs = value.paragraphRange(for: range)
        var location = paragraphs.location
        while location < NSMaxRange(paragraphs), location < storage.length {
            let paragraph = value.paragraphRange(for: NSRange(location: location, length: 0))
            let kind = currentBlockKind(at: location)
            let indentation = currentListIndentation(at: location)
            for key: NSAttributedString.Key in [.underlineStyle, .underlineColor, .strokeWidth, .obliqueness] {
                storage.removeAttribute(key, range: paragraph)
                layoutManager?.removeTemporaryAttribute(key, forCharacterRange: paragraph)
            }
            storage.addAttributes(DayDreamTheme.textAttributes(for: effectiveAppearance, scale: zoomScale,
                blockKind: kind, listIndentation: indentation), range: paragraph)
            refreshInlineVisuals(in: paragraph)
            applySpaceWidth(in: paragraph)
            location = NSMaxRange(paragraph)
        }
        needsDisplay = true
    }

    // MARK: - 悬浮样式工具条

    private lazy var formatPanel = FormatPanel()
    var isFormatPanelVisible: Bool { formatPanel.isVisible }

    func toggleBold() { toggleInlineFlag(.dayDreamBold) }
    func toggleItalic() { toggleInlineFlag(.dayDreamItalic) }
    func toggleInlineCode() { toggleInlineFlag(.dayDreamInlineCode) }
    func toggleHighlight() {
        toggleInlineValue(.dayDreamHighlight, value: EditorSettings.shared.highlightPreset)
    }
    func toggleTextColor() {
        toggleInlineValue(.dayDreamTextColor, value: EditorSettings.shared.textColorPreset)
    }

    private func toggleInlineFlag(_ key: NSAttributedString.Key) {
        guard let storage = textStorage, selectedRange.length > 0 else { return }
        registerStyleUndo()
        let changedRange = selectedRange
        let previousHighlightRects = highlightInvalidationRects(in: changedRange)
        let isAppliedToWholeSelection = selectedRangeFullyMatches(key) { value in
            value as? Bool == true
        }
        if isAppliedToWholeSelection {
            storage.removeAttribute(key, range: selectedRange)
        } else {
            storage.addAttribute(key, value: true, range: selectedRange)
        }
        afterInlineStyleChange(
            in: changedRange,
            previousHighlightRects: previousHighlightRects
        )
    }

    private func toggleInlineValue(_ key: NSAttributedString.Key, value: String) {
        guard let storage = textStorage, selectedRange.length > 0 else { return }
        registerStyleUndo()
        let changedRange = selectedRange
        let previousHighlightRects = highlightInvalidationRects(in: changedRange)
        let isAppliedToWholeSelection = selectedRangeFullyMatches(key) { current in
            current as? String == value
        }
        if isAppliedToWholeSelection {
            storage.removeAttribute(key, range: selectedRange)
        } else {
            storage.addAttribute(key, value: value, range: selectedRange)
        }
        afterInlineStyleChange(
            in: changedRange,
            previousHighlightRects: previousHighlightRects
        )
    }

    private func selectedRangeFullyMatches(
        _ key: NSAttributedString.Key,
        predicate: (Any?) -> Bool
    ) -> Bool {
        guard let storage = textStorage, selectedRange.length > 0 else { return false }
        var matches = true
        storage.enumerateAttribute(key, in: selectedRange) { value, _, stop in
            guard !predicate(value) else { return }
            matches = false
            stop.pointee = true
        }
        return matches
    }

    private func afterInlineStyleChange(
        in changedRange: NSRange,
        previousHighlightRects: [NSRect]
    ) {
        rebuildAttributes(in: changedRange)
        layoutManager?.invalidateDisplay(forCharacterRange: changedRange)
        let currentHighlightRects = highlightInvalidationRects(in: changedRange)
        for rect in previousHighlightRects + currentHighlightRects {
            setNeedsDisplay(rect)
        }
        // 工具条位于独立的非激活面板，不能依赖下一次编辑器事件触发刷新。
        // 立即提交本轮无效区域，避免取消高亮后留下底部的一条旧像素。
        if window?.isVisible == true {
            displayIfNeeded()
        }
        notifyMarkdownChange()
        hideFormatPanel()
    }

    private func highlightInvalidationRects(in range: NSRange) -> [NSRect] {
        InlineHighlightLayout.invalidationRects(
            for: inlineHighlightFragments(),
            intersecting: range
        )
    }


    func hideFormatPanel() {
        formatPanel.hide()
    }

    func load(markdown: String) {
        stopRetype(restoreSelection: false)
        resetWritingStyle()
        (layoutManager as? TypingLayoutManager)?.clearReveals()
        mediaViews.values.forEach { $0.removeFromSuperview() }
        mediaViews.removeAll()
        textContainer?.exclusionPaths = []
        closeSlashCommandMenu()
        pendingMarkdownNotification?.cancel()
        pendingMarkdownNotification = nil
        markdownNotificationGeneration += 1
        isLoadingDocument = true
        sourcePreservation = nil
        let document = MarkdownDocumentCodec.parse(markdown)
        trailingBlockKind = document.blocks.last?.kind ?? .body
        trailingListIndentation = document.blocks.last?.indentation ?? ""
        trailingOrderedStart = document.blocks.last?.orderedStart ?? 1
        let value = MarkdownTextStorage.attributedString(
            from: document,
            appearance: effectiveAppearance,
            scale: zoomScale
        )
        textStorage?.setAttributedString(value)
        focusTextRevision += 1
        focusedSentenceRange = nil
        isFocusAppearanceApplied = false
        if let storage = textStorage, storage.length > 0 {
            applySpaceWidth(in: NSRange(location: 0, length: storage.length))
        }
        setSelectedRange(NSRange(location: value.length, length: 0))
        let lastKind = document.blocks.last?.kind ?? .body
        setTypingAttributes(for: lastKind, listIndentation: document.blocks.last?.indentation ?? "")
        typingAttributes[.dayDreamOrderedStart] = document.blocks.last?.orderedStart ?? 1
        sourcePreservation = SourcePreservingMarkdown(
            original: markdown,
            canonicalBaseline: canonicalMarkdown()
        )
        isLoadingDocument = false
        mostRecentEditChangedCharacters = false
        updateFocusAppearance()
        updateWordCompletion()
        updateCaret(animated: false)
        wordCountDidChange?(WordCounter.count(string))
        refreshMediaCards()
    }

    func exportMarkdown() -> String {
        let canonical = canonicalMarkdown()
        return sourcePreservation?.merge(canonicalCurrent: canonical) ?? canonical
    }

    private func canonicalMarkdown() -> String {
        guard let storage = textStorage else { return "" }
        return MarkdownDocumentCodec.serialize(
            MarkdownTextStorage.document(
                from: storage,
                fallbackKind: trailingBlockKind,
                fallbackIndentation: trailingListIndentation,
                fallbackOrderedStart: trailingOrderedStart
            )
        )
    }

    func currentBlockKind(at location: Int) -> MarkdownBlockKind {
        guard let storage = textStorage, storage.length > 0 else {
            return trailingBlockKind
        }
        if location >= storage.length, storage.string.last?.isNewline == true {
            return trailingBlockKind
        }
        let index = min(max(location, 0), storage.length - 1)
        return storage.attribute(.dayDreamBlockKind, at: index, effectiveRange: nil)
            as? MarkdownBlockKind ?? .body
    }

    func currentListIndentation(at location: Int) -> String {
        guard let storage = textStorage, storage.length > 0 else {
            return trailingListIndentation
        }
        if location >= storage.length, storage.string.last?.isNewline == true {
            return trailingListIndentation
        }
        let index = min(max(location, 0), storage.length - 1)
        return storage.attribute(.dayDreamListIndentation, at: index, effectiveRange: nil) as? String ?? ""
    }

    func setTypingAttributes(for kind: MarkdownBlockKind, listIndentation: String = "") {
        let indentation = kind.isList ? listIndentation : ""
        var attributes = DayDreamTheme.textAttributes(
            for: effectiveAppearance,
            scale: zoomScale,
            blockKind: kind,
            listIndentation: indentation
        )
        attributes[.dayDreamBlockKind] = kind
        attributes[.dayDreamListIndentation] = indentation
        let location = selectedRange.location
        if let storage = textStorage, location < storage.length {
            attributes[.dayDreamOrderedStart] = storage.attribute(.dayDreamOrderedStart, at: location, effectiveRange: nil) as? Int ?? 1
        } else { attributes[.dayDreamOrderedStart] = typingAttributes[.dayDreamOrderedStart] ?? 1 }
        typingAttributes = writingAttributes(base: attributes)
    }

    /// - Parameter updatesTypingAttributes: 是否同步更新打字属性。
    ///   只有「修改的段落就是光标所在段落」的调用者才应该传 true；
    ///   点击其他段落的 checkbox 这类跨段落修改必须传 false，
    ///   否则会把光标处（尤其是文末幻影空行）污染成被点击段落的类型。
    func applyBlockKind(
        _ kind: MarkdownBlockKind,
        at location: Int,
        updatesTypingAttributes: Bool = true,
        listIndentation: String? = nil
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
        let indentation = kind.isList
            ? (listIndentation ?? currentListIndentation(at: safeLocation))
            : ""
        if attributedRange.length > 0 {
            storage.addAttributes(
                DayDreamTheme.textAttributes(
                    for: effectiveAppearance,
                    scale: zoomScale,
                    blockKind: kind,
                    listIndentation: indentation
                ),
                range: attributedRange
            )
            storage.addAttribute(.dayDreamBlockKind, value: kind, range: attributedRange)
            storage.addAttribute(.dayDreamListIndentation, value: indentation, range: attributedRange)
        }
        if safeLocation == storage.length && (storage.length == 0 || string.last?.isNewline == true) {
            trailingBlockKind = kind
            trailingListIndentation = indentation
        }
        if updatesTypingAttributes {
            setTypingAttributes(for: kind, listIndentation: indentation)
        }
        requestDisplayCommit()
    }

    func notifyMarkdownChange() {
        guard !isLoadingDocument else { return }
        pendingMarkdownNotification?.cancel()
        markdownNotificationGeneration += 1
        let generation = markdownNotificationGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  generation == self.markdownNotificationGeneration else { return }
            self.pendingMarkdownNotification = nil
            self.markdownDidChange?(self.exportMarkdown())
        }
        pendingMarkdownNotification = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + markdownNotificationDelay,
            execute: workItem
        )
    }

    /// 在切换文档、退出或显式保存前同步提交尚未触发的防抖通知。
    func flushPendingMarkdownChange() {
        guard pendingMarkdownNotification != nil else { return }
        pendingMarkdownNotification?.cancel()
        pendingMarkdownNotification = nil
        markdownNotificationGeneration += 1
        markdownDidChange?(exportMarkdown())
    }

    private func updateTypingAttributesForSelection() {
        setTypingAttributes(
            for: currentBlockKind(at: selectedRange.location),
            listIndentation: currentListIndentation(at: selectedRange.location)
        )
    }

    func updatePageInsets() {
        let centeredInset = max((bounds.width - maximumContentWidth) / 2, 0)
        textContainerInset = NSSize(
            width: max(minimumHorizontalInset * zoomScale, centeredInset),
            height: isUltraFocus ? max(verticalInset * zoomScale, (enclosingScrollView?.contentSize.height ?? 0) / 2 - 20) : verticalInset * zoomScale
        )
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleEditorShortcut(event) { return true }
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

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let kind = currentBlockKind(at: affectedCharRange.location)
        let indentation = currentListIndentation(at: affectedCharRange.location)
        let start = typingAttributes[.dayDreamOrderedStart] as? Int ?? 1
        guard super.shouldChangeText(in: affectedCharRange, replacementString: replacementString) else { return false }
        if let replacementString, NSMaxRange(affectedCharRange) == string.utf16.count,
           replacementString.isEmpty || replacementString.last?.isNewline == true {
            trailingBlockKind = kind
            trailingListIndentation = indentation
            trailingOrderedStart = start
        }
        return true
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        dismissWritingBar()
        defer { requestDisplayCommit() }
        if retypeSession != nil {
            handleRetypeInput((insertString as? String) ?? (insertString as? NSAttributedString)?.string ?? "")
            return
        }
        if selectedRange.length == 0, currentBlockKind(at: selectedRange.location) == .divider,
           (insertString as? String) != "\n", !hasMarkedText() {
            doCommand(by: #selector(NSResponder.insertNewline(_:)))
            insertText(insertString, replacementRange: selectedRange)
            return
        }
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
            setOrderedStart(trigger.orderedStart, at: trigger.replacementRange.location)
            didChangeText()
            return
        }
        let input = (insertString as? String) ?? (insertString as? NSAttributedString)?.string ?? ""
        let wasMarked = hasMarkedText()
        let actualReplacement = wasMarked ? markedRange() : replacement
        (layoutManager as? TypingLayoutManager)?.prepareForEdit(actualReplacement, insertedLength: input.utf16.count)
        typingAttributes = writingAttributes(base: typingAttributes)
        super.insertText(insertString, replacementRange: replacementRange)
        if !hasMarkedText(), input.utf16.count < 80 {
            let end = selectedRange.location
            let start = max(0, end - input.utf16.count)
            (layoutManager as? TypingLayoutManager)?.reveal(NSRange(location: start, length: end - start))
        }
        if !hasMarkedText(), (insertString as? String) == "/", currentParagraphText == "/" {
            openSlashCommandMenu()
        } else if isSlashCommandMenuOpen, !hasMarkedText() {
            refreshSlashCommandMenu()
        }
    }

    override func doCommand(by selector: Selector) {
        dismissWritingBar()
        defer { requestDisplayCommit() }
        if retypeSession != nil {
            if selector == #selector(NSResponder.cancelOperation(_:)) { stopRetype() }
            else if selector == #selector(NSResponder.deleteBackward(_:)) { retypeSession?.backspace(); updateRetypeAppearance() }
            else if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.insertTab(_:)) { handleRetypeInput(" ") }
            return
        }
        (layoutManager as? TypingLayoutManager)?.clearReveals()
        if !hasMarkedText(), currentBlockKind(at: selectedRange.location).isList,
           selector == #selector(NSResponder.insertTab(_:)) || selector == #selector(NSResponder.insertBacktab(_:)) {
            let backwards = selector == #selector(NSResponder.insertBacktab(_:))
            if selectedRange.length == 0, isAtStartOfCurrentParagraph,
               changeCurrentListIndentation(by: backwards ? -1 : 1) { return }
            if !backwards { super.insertText("\t", replacementRange: selectedRange) }
            else if selectedRange.location > 0,
                    (string as NSString).substring(with: NSRange(location: selectedRange.location - 1, length: 1)) == "\t" {
                super.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
            }
            return
        }
        if selector == #selector(NSResponder.insertTab(_:)),
           !hasMarkedText(), selectedRange.length == 0,
           let suffix = completionSuffix {
            completionSuffix = nil
            super.insertText(suffix, replacementRange: selectedRange)
            return
        }

        if selector == #selector(NSResponder.deleteBackward(_:)),
           !hasMarkedText(),
           selectedRange.length == 0 {
            if isSlashCommandMenuOpen {
                super.doCommand(by: selector)
                refreshSlashCommandMenu()
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
                let commands = filteredSlashCommands
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
        let indentation = currentListIndentation(at: selectedRange.location)
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

        let nextOrdinal = kind == .numbered ? BlockDecorationLayout.numberedOrdinal(in: textStorage ?? NSTextStorage(), paragraphLocation: selectedRange.location) + 1 : 1
        super.doCommand(by: selector)
        applyBlockKind(nextKind, at: selectedRange.location, listIndentation: indentation)
        setOrderedStart(nextOrdinal, at: selectedRange.location)
        notifyMarkdownChange()
    }

    private func changeCurrentListIndentation(by delta: Int) -> Bool {
        let location = selectedRange.location
        let kind = currentBlockKind(at: location)
        guard kind == .numbered, isAtStartOfCurrentParagraph else { return false }

        var indentation = currentListIndentation(at: location)
        if delta > 0 {
            indentation += "  "
        } else if indentation.hasSuffix("  ") {
            indentation.removeLast(2)
        } else if !indentation.isEmpty {
            indentation.removeLast()
        } else {
            return true
        }
        applyBlockKind(kind, at: location, listIndentation: indentation)
        setOrderedStart(1, at: location)
        notifyMarkdownChange()
        return true
    }

    var filteredSlashCommands: [SlashCommand] {
        SlashCommandCatalog.matching(String(currentParagraphText.dropFirst()))
    }

    private func refreshSlashCommandMenu() {
        guard currentParagraphText.hasPrefix("/") else { closeSlashCommandMenu(); return }
        openSlashCommandMenu()
    }

    private func openSlashCommandMenu() {
        selectedSlashCommandIndex = 0
        isSlashCommandMenuOpen = true
        guard window != nil else { return }
        let anchor = firstRect(forCharacterRange: selectedRange, actualRange: nil)
        slashPanel.show(
            commands: filteredSlashCommands,
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
            count: filteredSlashCommands.count
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
        guard paragraph.hasPrefix("/") else {
            closeSlashCommandMenu()
            return
        }
        let slashRange = NSRange(location: paragraphRange.location, length: paragraph.utf16.count)
        closeSlashCommandMenu()
        guard shouldChangeText(in: slashRange, replacementString: "") else { return }
        textStorage?.replaceCharacters(in: slashRange, with: "")
        setSelectedRange(NSRange(location: slashRange.location, length: 0))
        applyBlockKind(kind, at: slashRange.location)
        didChangeText()
    }

    func closeSlashCommandMenu() {
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
    func currentCaretRect() -> NSRect? {
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

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawInlineHighlights(in: rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        (layoutManager as? TypingLayoutManager)?.drawFallingCopies(at: textContainerOrigin)
        drawBlockDecorations(in: dirtyRect)
        drawHeadingPlaceholder(in: dirtyRect)
        drawWordCompletion(in: dirtyRect)
        guard let rect = caretRect, caretAlpha > 0 else { return }
        DayDreamTheme.caret(for: effectiveAppearance)
            .withAlphaComponent(caretAlpha)
            .setFill()
        NSBezierPath(roundedRect: rect,
                     xRadius: rect.width / 2,
                     yRadius: rect.width / 2).fill()
    }

    func inlineHighlightFragments() -> [InlineHighlightFragment] {
        guard let storage = textStorage,
              storage.length > 0,
              let layoutManager,
              let textContainer else { return [] }
        let resolvedVisibleRect = visibleRect
        let drawingRect = resolvedVisibleRect.width.isFinite
            && resolvedVisibleRect.height.isFinite
            && resolvedVisibleRect.width <= max(bounds.width * 4, 1)
            && resolvedVisibleRect.height <= max(bounds.height * 4, 1)
            ? resolvedVisibleRect
            : bounds
        let containerRect = drawingRect.offsetBy(
            dx: -textContainerOrigin.x,
            dy: -textContainerOrigin.y
        )
        layoutManager.ensureLayout(forBoundingRect: containerRect, in: textContainer)

        var fragments: [InlineHighlightFragment] = []
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: containerRect,
            in: textContainer
        )
        let visibleCharacterRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange,
            actualGlyphRange: nil
        )
        let safeRange = NSIntersectionRange(
            visibleCharacterRange,
            NSRange(location: 0, length: storage.length)
        )
        guard safeRange.length > 0 else { return [] }
        storage.enumerateAttribute(.dayDreamHighlight, in: safeRange) { value, characterRange, _ in
            guard let preset = value as? String, characterRange.length > 0 else { return }
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: characterRange,
                actualCharacterRange: nil
            )
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) {
                lineRect, _, container, lineGlyphRange, _ in
                let fragmentGlyphRange = NSIntersectionRange(glyphRange, lineGlyphRange)
                guard fragmentGlyphRange.length > 0 else { return }
                let characterIndex = layoutManager.characterIndexForGlyph(
                    at: fragmentGlyphRange.location
                )
                let font = storage.attribute(
                    .font,
                    at: min(characterIndex, storage.length - 1),
                    effectiveRange: nil
                ) as? NSFont ?? DayDreamTheme.font
                let glyphBounds = layoutManager.boundingRect(
                    forGlyphRange: fragmentGlyphRange,
                    in: container
                )
                let glyphLocation = layoutManager.location(forGlyphAt: fragmentGlyphRange.location)
                let baseline = self.textContainerOrigin.y + lineRect.minY + glyphLocation.y
                let fragmentCharacterRange = layoutManager.characterRange(
                    forGlyphRange: fragmentGlyphRange,
                    actualGlyphRange: nil
                )
                fragments.append(InlineHighlightFragment(
                    preset: preset,
                    characterRange: fragmentCharacterRange,
                    rect: NSRect(
                        x: self.textContainerOrigin.x + glyphBounds.minX,
                        y: baseline - font.ascender,
                        width: glyphBounds.width,
                        height: font.ascender - font.descender
                    )
                ))
            }
        }

        let maximumJoinGap = DayDreamTheme.baseFontSize * zoomScale * 0.8
        return InlineHighlightLayout.join(
            fragments,
            maximumGap: maximumJoinGap,
            text: storage.string as NSString
        )
    }

    private func drawInlineHighlights(in dirtyRect: NSRect) {
        for fragment in inlineHighlightFragments() where fragment.rect.intersects(dirtyRect) {
            DayDreamTheme.inlineHighlightColor(fragment.preset, for: effectiveAppearance).setFill()
            let radius = min(4 * zoomScale, fragment.rect.height / 4)
            NSBezierPath(
                roundedRect: fragment.rect,
                xRadius: radius,
                yRadius: radius
            ).fill()
        }
    }

    private func drawBlockDecorations(in dirtyRect: NSRect) {
        let decorations = BlockDecorationLayout.decorations(
            in: self,
            textContainerOrigin: textContainerOrigin,
            scale: zoomScale
        )
        let color = DayDreamTheme.text(for: effectiveAppearance).withAlphaComponent(0.72)

        for decoration in decorations where decoration.markerRect.intersects(dirtyRect) {
            if decoration.kind == .divider {
                NSColor.separatorColor.setFill()
                NSBezierPath(rect: decoration.markerRect).fill()
                continue
            }
            if decoration.kind == .quote {
                DayDreamTheme.caret(for: effectiveAppearance)
                    .withAlphaComponent(0.42)
                    .setFill()
                NSBezierPath(
                    roundedRect: decoration.markerRect,
                    xRadius: decoration.markerRect.width / 2,
                    yRadius: decoration.markerRect.width / 2
                ).fill()
                continue
            }
            if let label = decoration.label {
                let paragraph = NSMutableParagraphStyle()
                // 序号右对齐贴近文字（长序号向左侧缩进区溢出），圆点居中。
                paragraph.alignment = decoration.kind == .numbered ? .right : .center
                var markerRect = decoration.markerRect
                let width = (label as NSString).size(withAttributes: [.font: BlockDecorationLayout.markerFont(scale: zoomScale)]).width + 2
                if decoration.kind == .numbered && width > markerRect.width {
                    markerRect.origin.x -= width - markerRect.width
                    markerRect.size.width = width
                }
                (label as NSString).draw(
                    in: markerRect,
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
        let clamped = min(max(level, 1), 4)
        return L10n.t("标题 \(clamped)", "Heading \(clamped)")
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
        dismissWritingBar()
        defer { requestDisplayCommit() }
        if retypeSession != nil { window?.makeFirstResponder(self); return }
        closeSlashCommandMenu()
        hideFormatPanel()
        let point = convert(event.locationInWindow, from: nil)
        if toggleTodo(at: point) { return }
        super.mouseDown(with: event)
    }

    // MARK: - 光标需要更新的时机

    override func didChangeText() {
        defer { requestDisplayCommit() }
        super.didChangeText()
        focusTextRevision += 1
        wordCountDidChange?(WordCounter.count(string))
        refreshMediaCards()
        centerUltraFocusCaret()
        notifyMarkdownChange()
        if mostRecentEditChangedCharacters {
            hideFormatPanel()
        }
        mostRecentEditChangedCharacters = false
        updateFocusAppearance()
        updateWordCompletion()
        updateCaret(animated: true)
    }

    override func setSelectedRange(_ charRange: NSRange,
                                   affinity: NSSelectionAffinity,
                                   stillSelecting stillSelectingFlag: Bool) {
        let range = retypeSession.map { NSRange(location: $0.location, length: 0) } ?? charRange
        super.setSelectedRange(range, affinity: affinity, stillSelecting: stillSelectingFlag)
        updateTypingAttributesForSelection()
        updateFocusAppearance()
        updateWordCompletion()
        requestDisplayCommit()
        updateCaret(animated: !stillSelectingFlag)
        centerUltraFocusCaret()
        // 拖选完成后浮现样式工具条；开始拖选或取消选区时隐藏。
        if stillSelectingFlag || selectedRange.length == 0 {
            hideFormatPanel()
        } else {
            hideFormatPanel()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updatePageInsets()
        refreshMediaCards()
        centerUltraFocusCaret()
        // 窗口缩放导致文字重排，光标直接落位。
        updateCaret(animated: false)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            updateCaret(animated: true)
            updateFocusAppearance()
            updateWordCompletion()
            onBecameFirstResponder?()
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        dismissWritingBar()
        let ok = super.resignFirstResponder()
        if ok {
            completionSuffix = nil
            updateCaret(animated: true)
            needsDisplay = true
        }
        return ok
    }

    @objc private func settingsDidChange() {
        defer { requestDisplayCommit() }
        isAutomaticSpellingCorrectionEnabled = retypeSession == nil && EditorSettings.shared.automaticSpellingCorrectionEnabled
        isContinuousSpellCheckingEnabled = retypeSession == nil && EditorSettings.shared.automaticSpellingCorrectionEnabled
        applyTheme()
        if !EditorSettings.shared.typingAnimationEnabled { (layoutManager as? TypingLayoutManager)?.clearReveals() }
        updateFocusAppearance()
        updateWordCompletion()
        if let textContainer {
            layoutManager?.ensureLayout(for: textContainer)
        }
        updateCaret(animated: false)
    }

    // MARK: - 专注模式与单词补全

    func updateFocusAppearance() {
        if retypeSession != nil { applyRetypeColors(); return }
        guard let storage = textStorage, let layoutManager else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        if EditorSettings.shared.focusModeEnabled,
           isFocusAppearanceApplied,
           resolvedFocusTextRevision == focusTextRevision,
           let focusedSentenceRange,
           NSLocationInRange(selectedRange.location, focusedSentenceRange)
            || selectedRange.location == NSMaxRange(focusedSentenceRange) {
            return
        }
        guard EditorSettings.shared.focusModeEnabled,
              storage.length > 0,
              let activeRange = FocusSentenceResolver.range(
                  in: storage.string,
                  caretLocation: selectedRange.location
              ) else {
            if isFocusAppearanceApplied {
                layoutManager.removeTemporaryAttribute(
                    .foregroundColor,
                    forCharacterRange: fullRange
                )
            }
            focusedSentenceRange = nil
            isFocusAppearanceApplied = false
            resolvedFocusTextRevision = focusTextRevision
            needsDisplay = true
            return
        }

        let dimColor = DayDreamTheme.text(for: effectiveAppearance).withAlphaComponent(0.24)
        if !isFocusAppearanceApplied {
            layoutManager.addTemporaryAttribute(
                .foregroundColor,
                value: dimColor,
                forCharacterRange: fullRange
            )
            layoutManager.removeTemporaryAttribute(
                .foregroundColor,
                forCharacterRange: activeRange
            )
            focusedSentenceRange = activeRange
            isFocusAppearanceApplied = true
        } else if focusedSentenceRange != activeRange {
            if let previous = focusedSentenceRange {
                let safePrevious = NSIntersectionRange(previous, fullRange)
                if safePrevious.length > 0 {
                    layoutManager.addTemporaryAttribute(
                        .foregroundColor,
                        value: dimColor,
                        forCharacterRange: safePrevious
                    )
                }
            }
            let safeActive = NSIntersectionRange(activeRange, fullRange)
            layoutManager.addTemporaryAttribute(
                .foregroundColor,
                value: dimColor,
                forCharacterRange: safeActive
            )
            layoutManager.removeTemporaryAttribute(
                .foregroundColor,
                forCharacterRange: safeActive
            )
            focusedSentenceRange = activeRange
        }
        resolvedFocusTextRevision = focusTextRevision
        needsDisplay = true
    }

    func resetFocusAppearance() {
        if isFocusAppearanceApplied,
           let storage = textStorage,
           let layoutManager,
           storage.length > 0 {
            layoutManager.removeTemporaryAttribute(
                .foregroundColor,
                forCharacterRange: NSRange(location: 0, length: storage.length)
            )
        }
        focusedSentenceRange = nil
        isFocusAppearanceApplied = false
        resolvedFocusTextRevision = -1
    }

    private func updateWordCompletion() {
        completionSuffix = nil
        guard retypeSession == nil, EditorSettings.shared.wordCompletionEnabled,
              window?.firstResponder === self,
              !hasMarkedText(),
              selectedRange.length == 0,
              !isSlashCommandMenuOpen,
              !isCodeBlockAtSelection,
              let partial = WordCompletionResolver.partialWord(
                  in: string,
                  caretLocation: selectedRange.location
              ),
              partial.word.count >= 2 else {
            needsDisplay = true
            return
        }
        let candidates = NSSpellChecker.shared.completions(
            forPartialWordRange: partial.range,
            in: string,
            language: nil,
            inSpellDocumentWithTag: 0
        ) ?? []
        completionSuffix = WordCompletionResolver.suffix(
            partialWord: partial.word,
            candidates: candidates
        )
        needsDisplay = true
    }

    private var isCodeBlockAtSelection: Bool {
        if case .code = currentBlockKind(at: selectedRange.location) { return true }
        return false
    }

    private func drawWordCompletion(in dirtyRect: NSRect) {
        guard let suffix = completionSuffix,
              let caret = currentCaretRect(),
              caret.intersects(dirtyRect.insetBy(dx: -bounds.width, dy: -4)) else { return }
        let activeFont = typingAttributes[.font] as? NSFont ?? font ?? DayDreamTheme.font
        (suffix as NSString).draw(
            at: NSPoint(x: caret.maxX + 1, y: caret.minY),
            withAttributes: [
                .font: activeFont,
                .foregroundColor: DayDreamTheme.text(for: effectiveAppearance)
                    .withAlphaComponent(0.25),
                .kern: DayDreamTheme.letterSpacing * zoomScale,
            ]
        )
    }

    @objc private func windowKeyChanged() {
        if window?.isKeyWindow != true {
            closeSlashCommandMenu()
            hideFormatPanel()
        }
        updateCaret(animated: true)
    }

    @objc private func clipBoundsChanged() {
        centerUltraFocusCaret()
        hideFormatPanel()
    }

    deinit {
        pendingMarkdownNotification?.cancel()
        ultraScrollTimer?.invalidate()
        writingBarPanel?.orderOut(nil)
        slashPanel.closePanel()
        formatPanel.hide()
        stopAnimation()
        NotificationCenter.default.removeObserver(self)
    }
}

extension DayDreamTextView: NSTextStorageDelegate {
    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard !isApplyingSpaceWidth,
              editedMask.contains(.editedCharacters),
              editedRange.location != NSNotFound,
              editedRange.location <= textStorage.length else { return }
        mostRecentEditChangedCharacters = true
        let value = textStorage.string as NSString
        let safeRange = NSRange(
            location: editedRange.location,
            length: min(editedRange.length, value.length - editedRange.location)
        )
        applySpaceWidth(in: safeRange)
    }
}

struct InlineHighlightFragment: Equatable {
    let preset: String
    var characterRange: NSRange
    var rect: NSRect
}

enum InlineHighlightLayout {
    static func invalidationRects(
        for fragments: [InlineHighlightFragment],
        intersecting range: NSRange
    ) -> [NSRect] {
        fragments.compactMap { fragment in
            guard NSIntersectionRange(fragment.characterRange, range).length > 0 else {
                return nil
            }
            return fragment.rect.insetBy(dx: -2, dy: -2)
        }
    }

    static func join(
        _ fragments: [InlineHighlightFragment],
        maximumGap: CGFloat,
        text: NSString
    ) -> [InlineHighlightFragment] {
        let sorted = fragments.sorted {
            if abs($0.rect.minY - $1.rect.minY) > 1 { return $0.rect.minY < $1.rect.minY }
            return $0.rect.minX < $1.rect.minX
        }
        var result: [InlineHighlightFragment] = []
        for fragment in sorted {
            if var previous = result.last,
               previous.preset == fragment.preset,
               abs(previous.rect.minY - fragment.rect.minY) <= 1,
               abs(previous.rect.height - fragment.rect.height) <= 1,
               gapIsOnlyWhitespace(from: previous.characterRange, to: fragment.characterRange, in: text),
               fragment.rect.minX <= previous.rect.maxX + maximumGap {
                previous.rect = previous.rect.union(fragment.rect)
                previous.characterRange = NSUnionRange(previous.characterRange, fragment.characterRange)
                result[result.count - 1] = previous
            } else {
                result.append(fragment)
            }
        }
        return result
    }

    private static func gapIsOnlyWhitespace(
        from first: NSRange,
        to second: NSRange,
        in text: NSString
    ) -> Bool {
        let start = NSMaxRange(first)
        guard second.location >= start else { return true }
        let gap = NSRange(location: start, length: second.location - start)
        guard gap.length > 0 else { return true }
        return text.substring(with: gap).allSatisfy(\.isWhitespace)
    }
}
