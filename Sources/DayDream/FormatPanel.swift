import AppKit

/// 选中文字后浮现的样式工具条：斜体 / 粗体 / 高亮 / 文字颜色。
/// 非激活面板：点击按钮不会夺走编辑器焦点，选区保持不变。
final class FormatPanel: NSPanel {

    enum Action {
        case italic, bold, inlineCode, highlight, textColor
    }

    var onAction: ((Action) -> Void)?

    private let panelWidth: CGFloat = 186
    private let panelHeight: CGFloat = 34

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.transient, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .utilityWindow

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        effect.material = .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 9
        effect.layer?.masksToBounds = true

        let items: [(Action, String)] = [
            (.italic, "italic"),
            (.bold, "bold"),
            (.inlineCode, "chevron.left.forwardslash.chevron.right"),
            (.highlight, "highlighter"),
            (.textColor, "textformat"),
        ]
        let buttonSize: CGFloat = 30
        let spacing: CGFloat = 4
        let totalWidth = CGFloat(items.count) * buttonSize + CGFloat(items.count - 1) * spacing
        var x = (panelWidth - totalWidth) / 2
        for (action, symbol) in items {
            let button = FormatPanelButton(
                action: action,
                symbol: symbol,
                frame: NSRect(x: x, y: (panelHeight - buttonSize) / 2, width: buttonSize, height: buttonSize)
            )
            button.onTap = { [weak self] tapped in
                self?.onAction?(tapped)
            }
            effect.addSubview(button)
            x += buttonSize + spacing
        }
        contentView = effect
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 显示在选区上方（rect 为屏幕坐标）。
    func show(above rect: NSRect) {
        var origin = NSPoint(x: rect.midX - panelWidth / 2, y: rect.maxY + 8)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(rect.origin) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 6), visible.maxX - panelWidth - 6)
            // 上方空间不足时放到选区下方。
            if origin.y + panelHeight > visible.maxY - 6 {
                origin.y = rect.minY - panelHeight - 8
            }
        }
        setFrameOrigin(origin)
        if !isVisible { orderFront(nil) }
    }

    func hide() {
        if isVisible { orderOut(nil) }
    }
}

private final class FormatPanelButton: NSView {
    let action: FormatPanel.Action
    var onTap: ((FormatPanel.Action) -> Void)?

    private let imageView = NSImageView()
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    init(action: FormatPanel.Action, symbol: String, frame: NSRect) {
        self.action = action
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 7

        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        imageView.contentTintColor = .secondaryLabelColor
        imageView.frame = bounds.insetBy(dx: 7, dy: 7)
        addSubview(imageView)

        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        }
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onTap?(action)
        }
    }
}
