import AppKit

/// DayDream 设计令牌：所有颜色遵循低饱和度规则。
enum DayDreamTheme {

    // MARK: - 亮色模式
    /// 背景：比白色稍微灰一点点，只是让白色不刺眼，不是明显的灰。
    static let lightBackground = NSColor(srgbRed: 0.980, green: 0.980, blue: 0.973, alpha: 1) // #FAFAF8
    /// 文字：柔和的墨色，不是纯黑。
    static let lightText = NSColor(srgbRed: 0.24, green: 0.24, blue: 0.23, alpha: 1)          // #3D3D3B
    /// 光标：淡蓝色。
    static let lightCaret = NSColor(srgbRed: 0.62, green: 0.77, blue: 0.91, alpha: 1)         // #9EC4E8
    /// 选区：光标的低透明度版本。
    static let lightSelection = NSColor(srgbRed: 0.62, green: 0.77, blue: 0.91, alpha: 0.22)

    // MARK: - 暗黑模式
    /// 背景：枪灰。
    static let darkBackground = NSColor(srgbRed: 41.0/255.0, green: 41.0/255.0, blue: 41.0/255.0, alpha: 1) // #292929
    /// 文字：白色但不刺眼——不是纯白，也不是明显的灰。
    static let darkText = NSColor(srgbRed: 0.906, green: 0.894, blue: 0.878, alpha: 1)        // #E7E4E0
    /// 光标：淡粉色。
    static let darkCaret = NSColor(srgbRed: 0.945, green: 0.745, blue: 0.788, alpha: 1)       // #F1BEC9
    /// 选区：光标的低透明度版本。
    static let darkSelection = NSColor(srgbRed: 0.945, green: 0.745, blue: 0.788, alpha: 0.24)

    // MARK: - 字体排印
    /// 默认使用苹果系统字体（SF）。
    static let font = NSFont.systemFont(ofSize: 19, weight: .regular)
    /// 词距较宽。
    static let letterSpacing: CGFloat = 0.8
    /// 行高倍数，留出呼吸感。
    static let lineHeightMultiple: CGFloat = 1.55

    // MARK: - 查询

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func background(for appearance: NSAppearance) -> NSColor {
        isDark(appearance) ? darkBackground : lightBackground
    }

    static func text(for appearance: NSAppearance) -> NSColor {
        isDark(appearance) ? darkText : lightText
    }

    static func caret(for appearance: NSAppearance) -> NSColor {
        isDark(appearance) ? darkCaret : lightCaret
    }

    static func selection(for appearance: NSAppearance) -> NSColor {
        isDark(appearance) ? darkSelection : lightSelection
    }

    static func textAttributes(
        for appearance: NSAppearance,
        scale: CGFloat = 1,
        blockKind: MarkdownBlockKind = .body
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        let pointSize: CGFloat
        let weight: NSFont.Weight

        switch blockKind {
        case .body, .bullet, .numbered, .todo:
            pointSize = font.pointSize
            weight = .regular
            // 行距：两行之间的距离，由设置页调整。
            paragraph.lineHeightMultiple = EditorSettings.shared.lineHeightMultiple
        case let .heading(level):
            let sizes: [CGFloat] = [34, 28, 23, 20]
            pointSize = sizes[min(max(level, 1), 4) - 1]
            weight = level <= 2 ? .bold : .semibold
            paragraph.lineHeightMultiple = 1.18
            paragraph.paragraphSpacingBefore = 8 * scale
            paragraph.paragraphSpacing = 5 * scale
        }

        if blockKind.isList {
            paragraph.firstLineHeadIndent = 30 * scale
            paragraph.headIndent = 30 * scale
        }

        let foreground: NSColor
        if case .todo(checked: true) = blockKind {
            foreground = text(for: appearance).withAlphaComponent(0.52)
        } else {
            foreground = text(for: appearance)
        }

        return [
            .font: NSFont.systemFont(ofSize: pointSize * scale, weight: weight),
            .foregroundColor: foreground,
            .kern: letterSpacing * scale,
            .paragraphStyle: paragraph,
        ]
    }
}
