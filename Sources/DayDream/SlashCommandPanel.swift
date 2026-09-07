import AppKit

struct SlashCommand: Identifiable, Equatable {
    let syntax: String
    let kind: MarkdownBlockKind

    var id: MarkdownBlockKind { kind }

    var title: String {
        switch kind {
        case let .heading(level): return L10n.t("标题 \(min(max(level, 1), 4))", "Heading \(min(max(level, 1), 4))")
        case .bullet: return L10n.t("无序列表", "Bulleted list")
        case .numbered: return L10n.t("有序列表", "Numbered list")
        case .todo: return L10n.t("待办事项", "To-do list")
        case .quote: return L10n.t("引用", "Quote")
        case .code: return L10n.t("代码块", "Code block")
        case .divider: return L10n.t("分隔线", "Divider")
        case .body: return L10n.t("正文", "Text")
        }
    }

    var subtitle: String {
        switch kind {
        case .heading(1): return L10n.t("大节标题", "Large section title")
        case .heading(2): return L10n.t("中节标题", "Medium section title")
        case .heading(3): return L10n.t("小节标题", "Small section title")
        case .heading: return L10n.t("紧凑标题", "Compact section title")
        case .bullet: return L10n.t("创建一个无序列表", "Create a bulleted list")
        case .numbered: return L10n.t("创建一个有序列表", "Create an ordered list")
        case .todo: return L10n.t("用复选框跟踪任务", "Track a task with a checkbox")
        case .quote: return L10n.t("突出显示引用内容", "Capture a quoted passage")
        case .code: return L10n.t("保留格式的多行代码", "Write multi-line code")
        case .divider: return L10n.t("分隔线", "Divider")
        case .body: return L10n.t("普通文本", "Plain text")
        }
    }
}

enum SlashCommandCatalog {
    static func matching(_ query: String) -> [SlashCommand] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return all }
        return all.filter { command in
            let aliases: String
            switch command.kind {
            case .heading(let level): aliases = "heading title h\(level) 标题 \(level)"
            case .bullet: aliases = "bullet unordered list 无序列表"
            case .numbered: aliases = "number ordered list 有序 数字列表"
            case .todo: aliases = "todo checkbox task 待办 复选框"
            case .quote: aliases = "quote blockquote 引用"
            case .code: aliases = "code 代码"
            case .divider: aliases = "divider horizontal rule 分隔线"
            case .body: aliases = "text 正文"
            }
            return (aliases + " " + command.syntax + " " + command.title).lowercased().contains(query)
        }
    }

    static let all: [SlashCommand] = [
        .init(syntax: "---", kind: .divider),
        .init(syntax: "#", kind: .heading(level: 1)),
        .init(syntax: "##", kind: .heading(level: 2)),
        .init(syntax: "###", kind: .heading(level: 3)),
        .init(syntax: "####", kind: .heading(level: 4)),
        .init(syntax: "-", kind: .bullet),
        .init(syntax: "1.", kind: .numbered),
        .init(syntax: "[ ]", kind: .todo(checked: false)),
        .init(syntax: ">", kind: .quote),
        .init(syntax: "```", kind: .code(language: nil)),
    ]
}

enum SlashCommandNavigation {
    static func moved(from index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index + delta % count + count) % count
    }
}

final class SlashCommandPanel: NSPanel {
    private var rowButtons: [SlashCommandButton] = []
    private var onChoose: ((MarkdownBlockKind) -> Void)?
    private var onDismiss: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isFloatingPanel = true
        hidesOnDeactivate = true
        collectionBehavior = [.transient, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(
        commands: [SlashCommand],
        selectedIndex: Int,
        screenAnchor: NSRect,
        onDismiss: @escaping () -> Void,
        onChoose: @escaping (MarkdownBlockKind) -> Void
    ) {
        self.onChoose = onChoose
        self.onDismiss = onDismiss

        let width: CGFloat = 320
        let outerInset: CGFloat = 8
        let headerHeight: CGFloat = 34
        let rowHeight: CGFloat = 42
        let footerHeight: CGFloat = 42
        let dividerHeight: CGFloat = 1
        let height = outerInset + headerHeight
            + CGFloat(commands.count) * rowHeight
            + outerInset + dividerHeight + footerHeight

        let surface = SlashCommandSurfaceView(
            frame: NSRect(x: 0, y: 0, width: width, height: height)
        )

        let header = NSTextField(labelWithString: commands.isEmpty ? L10n.t("没有匹配的样式", "No matching styles") : L10n.t("样式", "Basic blocks"))
        header.font = .systemFont(ofSize: 12.5, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.frame = NSRect(
            x: 16,
            y: outerInset,
            width: width - 32,
            height: headerHeight
        )
        surface.addSubview(header)

        rowButtons = commands.enumerated().map { index, command in
            let button = SlashCommandButton(command: command, index: index)
            button.target = self
            button.action = #selector(chooseCommand(_:))
            button.frame = NSRect(
                x: outerInset,
                y: outerInset + headerHeight + CGFloat(index) * rowHeight,
                width: width - outerInset * 2,
                height: rowHeight
            )
            surface.addSubview(button)
            return button
        }

        let dividerY = outerInset + headerHeight + CGFloat(commands.count) * rowHeight + outerInset
        let divider = SlashCommandDivider(frame: NSRect(
            x: 0,
            y: dividerY,
            width: width,
            height: dividerHeight
        ))
        surface.addSubview(divider)

        let closeButton = SlashCommandCloseButton(frame: NSRect(
            x: outerInset,
            y: dividerY + dividerHeight,
            width: width - outerInset * 2,
            height: footerHeight
        ))
        closeButton.target = self
        closeButton.action = #selector(closeFromFooter(_:))
        surface.addSubview(closeButton)

        contentView = surface
        setContentSize(NSSize(width: width, height: height))
        updateSelection(selectedIndex)

        let screenFrame = NSScreen.screens.first(where: { $0.frame.intersects(screenAnchor) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        var origin = NSPoint(x: screenAnchor.minX, y: screenAnchor.minY - height - 6)
        if origin.y < screenFrame.minY {
            origin.y = screenAnchor.maxY + 6
        }
        origin.x = min(max(origin.x, screenFrame.minX + 8), screenFrame.maxX - width - 8)
        setFrameOrigin(origin)
        orderFront(nil)
    }

    func updateSelection(_ index: Int) {
        for (buttonIndex, button) in rowButtons.enumerated() {
            button.isCommandSelected = buttonIndex == index
        }
    }

    func closePanel() {
        orderOut(nil)
        onChoose = nil
        rowButtons.removeAll()
        let dismiss = onDismiss
        onDismiss = nil
        dismiss?()
    }

    @objc private func chooseCommand(_ sender: SlashCommandButton) {
        onChoose?(sender.command.kind)
    }

    @objc private func closeFromFooter(_ sender: NSButton) {
        closePanel()
    }
}

private final class SlashCommandSurfaceView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let color = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.125, green: 0.125, blue: 0.125, alpha: 0.985)
            : NSColor(srgbRed: 0.965, green: 0.965, blue: 0.955, alpha: 0.985)
        color.setFill()
        bounds.fill()
    }
}

private final class SlashCommandDivider: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.22).setFill()
        bounds.fill()
    }
}

private final class SlashCommandButton: NSButton {
    let command: SlashCommand

    var isCommandSelected = false {
        didSet { needsDisplay = true }
    }

    init(command: SlashCommand, index: Int) {
        self.command = command
        super.init(frame: .zero)
        tag = index
        title = command.title
        isBordered = false
        imagePosition = .noImage
        focusRingType = .none
        setButtonType(.momentaryChange)
        toolTip = command.subtitle
        setAccessibilityLabel(command.title)
        setAccessibilityHelp("Type \(command.syntax) followed by Space")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        if isCommandSelected || isHighlighted {
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(
                roundedRect: bounds.insetBy(dx: 2, dy: 2),
                xRadius: 7,
                yRadius: 7
            ).fill()
        }

        let foreground = isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor
        drawIcon(in: NSRect(x: 12, y: 9, width: 24, height: 24), color: foreground)

        (command.title as NSString).draw(
            in: NSRect(x: 48, y: 11, width: bounds.width - 104, height: 22),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: foreground,
            ]
        )

        let syntax = command.syntax as NSString
        let syntaxAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let syntaxWidth = ceil(syntax.size(withAttributes: syntaxAttributes).width)
        syntax.draw(
            in: NSRect(x: bounds.width - syntaxWidth - 14, y: 12, width: syntaxWidth, height: 20),
            withAttributes: syntaxAttributes
        )
    }

    private func drawIcon(in rect: NSRect, color: NSColor) {
        color.setStroke()
        color.setFill()

        switch command.kind {
        case .divider:
            NSBezierPath(rect: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: 1)).fill()
        case let .heading(level):
            ("H\(level)" as NSString).draw(in: rect.offsetBy(dx: 1, dy: 1), withAttributes: [
                .font: NSFont.systemFont(ofSize: 15.5, weight: .medium),
                .foregroundColor: color,
            ])
        case .bullet:
            drawListIcon(in: rect, numbered: false, color: color)
        case .numbered:
            drawListIcon(in: rect, numbered: true, color: color)
        case .todo:
            let box = NSBezierPath(roundedRect: rect.insetBy(dx: 3.5, dy: 3.5), xRadius: 3, yRadius: 3)
            box.lineWidth = 1.6
            box.stroke()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: rect.minX + 7, y: rect.midY))
            check.line(to: NSPoint(x: rect.minX + 10.5, y: rect.maxY - 7))
            check.line(to: NSPoint(x: rect.maxX - 6, y: rect.minY + 7))
            check.lineWidth = 1.5
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.stroke()
        case .quote:
            let bar = NSBezierPath(
                roundedRect: NSRect(x: rect.minX + 5, y: rect.minY + 3, width: 2.5, height: rect.height - 6),
                xRadius: 1.25,
                yRadius: 1.25
            )
            bar.fill()
            ("“" as NSString).draw(in: rect.offsetBy(dx: 8, dy: 1), withAttributes: [
                .font: NSFont.systemFont(ofSize: 17, weight: .medium),
                .foregroundColor: color,
            ])
        case .code:
            ("</>" as NSString).draw(in: rect.offsetBy(dx: 0, dy: 3), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: color,
            ])
        case .body:
            break
        }
    }

    private func drawListIcon(in rect: NSRect, numbered: Bool, color: NSColor) {
        let line = NSBezierPath()
        line.lineWidth = 1.55
        line.lineCapStyle = .round
        for offset in [6.5, 12, 17.5] as [CGFloat] {
            line.move(to: NSPoint(x: rect.minX + 9, y: rect.minY + offset))
            line.line(to: NSPoint(x: rect.maxX - 2, y: rect.minY + offset))
        }
        line.stroke()

        if numbered {
            ("1\n2\n3" as NSString).draw(
                in: NSRect(x: rect.minX, y: rect.minY + 1, width: 7, height: rect.height),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 7.5, weight: .medium),
                    .foregroundColor: color,
                ]
            )
        } else {
            for offset in [6.5, 12, 17.5] as [CGFloat] {
                NSBezierPath(ovalIn: NSRect(
                    x: rect.minX + 2,
                    y: rect.minY + offset - 1.25,
                    width: 2.5,
                    height: 2.5
                )).fill()
            }
        }
    }
}

private final class SlashCommandCloseButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = "Close menu"
        isBordered = false
        focusRingType = .none
        setButtonType(.momentaryChange)
        setAccessibilityLabel("Close menu")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 3), xRadius: 7, yRadius: 7).fill()
        }
        ("Close menu" as NSString).draw(
            in: NSRect(x: 8, y: 11, width: 180, height: 21),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 13.5, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        ("esc" as NSString).draw(
            in: NSRect(x: bounds.width - 42, y: 12, width: 32, height: 19),
            withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        )
    }
}
