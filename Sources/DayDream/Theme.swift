import AppKit

/// 行内样式颜色预设。高亮与文字颜色遵循「低饱和度 + 低亮度」规则。
enum StyleColorPreset: String, CaseIterable, Sendable {
    /// 跟随光标色系（亮色 = 浅蓝系，暗黑 = 浅粉系）。
    case caret
    case yellow
    case green
    case blue
    case pink
}

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
    /// 基础字号。
    static let baseFontSize: CGFloat = 19
    /// 编辑器字体：跟随设置页选择，默认苹果系统字体（SF）。
    static var font: NSFont { EditorSettings.shared.editorFont }
    /// 词距较宽。
    static let letterSpacing: CGFloat = 0.8
    /// 行高倍数，留出呼吸感。
    static let lineHeightMultiple: CGFloat = 1.55

    /// 按字族 + 字号 + 字重构建字体。
    static func scaledFont(pointSize: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = EditorSettings.shared.editorFont
        guard weight != .regular else {
            return NSFont(descriptor: base.fontDescriptor, size: pointSize)
                ?? .systemFont(ofSize: pointSize, weight: .regular)
        }
        let descriptor = base.fontDescriptor.addingAttributes([
            .traits: [NSFontDescriptor.TraitKey.weight: NSNumber(value: Double(weight.rawValue))]
        ])
        return NSFont(descriptor: descriptor, size: pointSize)
            ?? .systemFont(ofSize: pointSize, weight: weight)
    }

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

    // MARK: - 段落基础属性

    static func textAttributes(
        for appearance: NSAppearance,
        scale: CGFloat = 1,
        blockKind: MarkdownBlockKind = .body,
        listIndentation: String = ""
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        let pointSize: CGFloat
        let weight: NSFont.Weight

        switch blockKind {
        case .body, .bullet, .numbered, .todo, .quote, .translation, .divider:
            pointSize = baseFontSize
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
        case .code:
            pointSize = 16.5
            weight = .regular
            paragraph.lineHeightMultiple = 1.35
            paragraph.firstLineHeadIndent = 14 * scale
            paragraph.headIndent = 14 * scale
            paragraph.paragraphSpacingBefore = 2 * scale
            paragraph.paragraphSpacing = 2 * scale
        }

        if blockKind.isList {
            let nestingOffset = CGFloat(indentationColumns(listIndentation)) * 12 * scale
            paragraph.firstLineHeadIndent = 30 * scale + nestingOffset
            paragraph.headIndent = 30 * scale + nestingOffset
        } else if blockKind == .quote {
            paragraph.firstLineHeadIndent = 18 * scale
            paragraph.headIndent = 18 * scale
        }

        let foreground: NSColor
        if case .todo(checked: true) = blockKind {
            foreground = text(for: appearance).withAlphaComponent(0.52)
        } else if blockKind == .quote {
            foreground = text(for: appearance).withAlphaComponent(0.78)
        } else {
            foreground = text(for: appearance)
        }

        let resolvedFont = if case .code = blockKind {
            NSFont.monospacedSystemFont(ofSize: pointSize * scale, weight: weight)
        } else {
            scaledFont(pointSize: pointSize * scale, weight: weight)
        }

        return [
            .font: resolvedFont,
            .foregroundColor: foreground,
            .kern: letterSpacing * scale,
            .paragraphStyle: paragraph,
        ]
    }

    static func indentationColumns(_ indentation: String) -> Int {
        indentation.reduce(0) { columns, character in
            columns + (character == "\t" ? 2 : 1)
        }
    }

    // MARK: - 行内样式（粗体 / 斜体 / 高亮 / 文字颜色）

    /// 在段落基础属性上叠加行内样式的视觉表现。
    /// 自定义语义键（.dayDreamBold 等）同时写入，供序列化与主题重建使用。
    static func inlineStyledAttributes(
        base: [NSAttributedString.Key: Any],
        bold: Bool,
        italic: Bool,
        inlineCode: Bool,
        linkDestination: String?,
        imageDestination: String?,
        textColorName: String?,
        highlightName: String?,
        fontFamily: String? = nil,
        underline: Bool = false,
        strikethrough: Bool = false,
        for appearance: NSAppearance
    ) -> [NSAttributedString.Key: Any] {
        var attributes = base
        var font = base[.font] as? NSFont ?? EditorSettings.shared.editorFont
        if let fontFamily {
            font = EditorSettings.resolveFont(fontFamily, size: font.pointSize)
            attributes[.dayDreamFontFamily] = fontFamily
        }
        if inlineCode {
            font = .monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
        }
        let manager = NSFontManager.shared
        if bold { font = manager.convert(font, toHaveTrait: .boldFontMask) }
        if italic { font = manager.convert(font, toHaveTrait: .italicFontMask) }
        // Imported fonts often provide only a regular face. AppKit silently keeps
        // that face when conversion fails, so synthesize the missing appearance.
        attributes[.strokeWidth] = nil
        attributes[.obliqueness] = nil
        if bold, !manager.traits(of: font).contains(.boldFontMask) {
            attributes[.strokeWidth] = -4.5
        }
        if bold, manager.traits(of: font).contains(.boldFontMask) { attributes[.strokeWidth] = -1.2 }
        if italic, !manager.traits(of: font).contains(.italicFontMask) {
            attributes[.obliqueness] = 0.22
        }
        attributes[.font] = font

        if bold { attributes[.dayDreamBold] = true }
        if italic { attributes[.dayDreamItalic] = true }
        if inlineCode { attributes[.dayDreamInlineCode] = true }
        if let linkDestination {
            attributes[.dayDreamLink] = linkDestination
            attributes[.link] = linkDestination
            attributes[.underlineStyle] = 0
            attributes[.foregroundColor] = inlineTextColor("blue", for: appearance)
        }
        if let imageDestination {
            attributes[.dayDreamImage] = imageDestination
            attributes[.foregroundColor] = inlineTextColor("blue", for: appearance)
        }
        if let textColorName {
            attributes[.foregroundColor] = inlineTextColor(textColorName, for: appearance)
            attributes[.dayDreamTextColor] = textColorName
        }
        if let highlightName {
            attributes[.dayDreamHighlight] = highlightName
        }
        attributes[.underlineStyle] = underline || linkDestination.flatMap(NoteLinks.target) != nil ? NSUnderlineStyle.single.rawValue : 0
        attributes[.strikethroughStyle] = strikethrough ? NSUnderlineStyle.single.rawValue : 0
        if underline { attributes[.dayDreamUnderline] = true }
        if strikethrough {
            attributes[.dayDreamStrikethrough] = true
            let color = attributes[.foregroundColor] as? NSColor ?? text(for: appearance)
            attributes[.foregroundColor] = color.withAlphaComponent(color.alphaComponent * 0.45)
        }
        return attributes
    }

    /// 文字颜色：低饱和度，按模式调整亮度保证可读。
    static func inlineTextColor(_ preset: String, for appearance: NSAppearance) -> NSColor {
        let dark = isDark(appearance)
        switch StyleColorPreset(rawValue: preset) ?? .caret {
        case .caret, .blue:
            return dark
                ? NSColor(srgbRed: 0.494, green: 0.592, blue: 0.682, alpha: 1) // #7E97AE
                : NSColor(srgbRed: 0.357, green: 0.498, blue: 0.651, alpha: 1) // #5B7FA6
        case .yellow:
            return dark
                ? NSColor(srgbRed: 0.639, green: 0.576, blue: 0.369, alpha: 1) // #A3935E
                : NSColor(srgbRed: 0.541, green: 0.478, blue: 0.282, alpha: 1) // #8A7A48
        case .green:
            return dark
                ? NSColor(srgbRed: 0.478, green: 0.604, blue: 0.518, alpha: 1) // #7A9A84
                : NSColor(srgbRed: 0.373, green: 0.498, blue: 0.408, alpha: 1) // #5F7F68
        case .pink:
            return dark
                ? NSColor(srgbRed: 0.769, green: 0.557, blue: 0.612, alpha: 1) // #C48E9C
                : NSColor(srgbRed: 0.604, green: 0.431, blue: 0.431, alpha: 1) // #9A6E6E
        }
    }

    /// 高亮颜色：低饱和度 + 低亮度，带透明度铺底，文字保持可读。
    static func inlineHighlightColor(_ preset: String, for appearance: NSAppearance) -> NSColor {
        let dark = isDark(appearance)
        let color: NSColor
        switch StyleColorPreset(rawValue: preset) ?? .caret {
        case .caret, .blue:
            color = dark
                ? NSColor(srgbRed: 0.369, green: 0.443, blue: 0.514, alpha: 1) // #5E7183
                : NSColor(srgbRed: 0.478, green: 0.576, blue: 0.678, alpha: 1) // #7A93AD
        case .yellow:
            color = dark
                ? NSColor(srgbRed: 0.486, green: 0.443, blue: 0.282, alpha: 1) // #7C7148
                : NSColor(srgbRed: 0.639, green: 0.580, blue: 0.408, alpha: 1) // #A39468
        case .green:
            color = dark
                ? NSColor(srgbRed: 0.369, green: 0.478, blue: 0.400, alpha: 1) // #5E7A66
                : NSColor(srgbRed: 0.498, green: 0.627, blue: 0.541, alpha: 1) // #7FA08A
        case .pink:
            color = dark
                ? NSColor(srgbRed: 0.588, green: 0.400, blue: 0.435, alpha: 1) // #96666F
                : NSColor(srgbRed: 0.659, green: 0.506, blue: 0.506, alpha: 1) // #A88181
        }
        return color.withAlphaComponent(0.32)
    }
}
