import AppKit

/// DayDream 编辑器核心：纯文本 NSTextView。
///
/// 默认的 macOS 光标是闪烁 + 闪现移动的。这里完全接管光标的绘制：
/// 隐藏系统光标，自己维护一个「显示位置」与「目标位置」，
/// 用 60fps 的缓动插值让光标平缓地滑向目标，永不瞬移、永不闪烁。
final class DayDreamTextView: NSTextView {

    // MARK: - 光标状态

    private let caretWidth: CGFloat = 2.0
    /// 当前屏幕上实际绘制的光标位置（动画中间值）。
    private var caretRect: NSRect?
    /// 光标应该到达的位置。
    private var caretTarget: NSRect?
    /// 当前绘制的光标不透明度。
    private var caretAlpha: CGFloat = 0
    private var caretAlphaTarget: CGFloat = 0
    private var lastDrawnCaretRect: NSRect?
    private var animationTimer: Timer?

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

        font = DayDreamTheme.font
        // 隐藏系统光标的颜色（绘制也已在下方被禁用）。
        insertionPointColor = .clear
        textContainerInset = NSSize(width: 72, height: 56)

        applyTheme()
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
        backgroundColor = DayDreamTheme.background(for: appearance)
        enclosingScrollView?.drawsBackground = true
        enclosingScrollView?.backgroundColor = DayDreamTheme.background(for: appearance)
        selectedTextAttributes = [
            .backgroundColor: DayDreamTheme.selection(for: appearance),
            .foregroundColor: DayDreamTheme.text(for: appearance),
        ]
        typingAttributes = DayDreamTheme.textAttributes(for: appearance)

        // 纯文本模式：整篇文档统一套用排版（字体 / 词距 / 行高 / 颜色）。
        if let storage = textStorage, storage.length > 0 {
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes(DayDreamTheme.textAttributes(for: appearance), range: full)
            storage.endEditing()
        }
        needsDisplay = true
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

        let inWindow = window.convertFromScreen(screen)
        var rect = convert(inWindow, from: nil)
        rect.origin.x -= caretWidth / 2
        rect.size.width = caretWidth
        return rect.insetBy(dx: 0, dy: 3) // 上下各收一点，视觉上更安静
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
        guard let rect = caretRect, caretAlpha > 0 else { return }
        DayDreamTheme.caret(for: effectiveAppearance)
            .withAlphaComponent(caretAlpha)
            .setFill()
        NSBezierPath(roundedRect: rect,
                     xRadius: rect.width / 2,
                     yRadius: rect.width / 2).fill()
    }

    // MARK: - 光标需要更新的时机

    override func didChangeText() {
        super.didChangeText()
        updateCaret(animated: true)
    }

    override func setSelectedRange(_ charRange: NSRange,
                                   affinity: NSSelectionAffinity,
                                   stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelectingFlag)
        updateCaret(animated: !stillSelectingFlag)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
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

    @objc private func windowKeyChanged() {
        updateCaret(animated: true)
    }

    deinit {
        stopAnimation()
        NotificationCenter.default.removeObserver(self)
    }
}
