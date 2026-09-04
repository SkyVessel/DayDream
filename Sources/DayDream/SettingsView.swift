import SwiftUI

/// 设置页面（DayDream 菜单 → Settings…，⌘,）。
/// 低饱和度、无装饰，与编辑器同一气质。
struct SettingsView: View {
    @ObservedObject private var settings = EditorSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                generalSection
                typographySection
                styleColorSection
                shortcutSection
            }
            .padding(28)
        }
        .frame(width: 440, height: 560)
    }

    // MARK: - 通用

    private var generalSection: some View {
        section(title: L10n.t("通用", "General")) {
            pickerRow(
                title: L10n.t("语言", "Language"),
                selection: $settings.language,
                options: AppLanguage.allCases.map { ($0, $0.displayName) }
            )
            pickerRow(
                title: L10n.t("外观", "Appearance"),
                selection: $settings.appearanceMode,
                options: [
                    (.system, L10n.t("跟随系统", "System")),
                    (.light, L10n.t("浅色", "Light")),
                    (.dark, L10n.t("深色", "Dark")),
                ]
            )
        }
    }

    // MARK: - 排版

    private var typographySection: some View {
        section(title: L10n.t("排版", "Typography")) {
            pickerRow(
                title: L10n.t("字体", "Font"),
                selection: $settings.fontFamily,
                options: EditorSettings.fontChoices.map { ($0.id, $0.displayName) }
            )
            sliderRow(
                title: L10n.t("一行长度", "Line Length"),
                hint: L10n.t("内容始终居中", "Content stays centered"),
                value: "\(Int(settings.contentWidth)) pt",
                sliderValue: $settings.contentWidth,
                range: EditorSettings.contentWidthRange,
                step: EditorSettings.contentWidthStep
            )
            sliderRow(
                title: L10n.t("行距", "Line Spacing"),
                hint: L10n.t("两行之间的距离", "Space between lines"),
                value: String(format: "%.2f", settings.lineHeightMultiple),
                sliderValue: $settings.lineHeightMultiple,
                range: EditorSettings.lineHeightRange,
                step: EditorSettings.lineHeightStep
            )
            sliderRow(
                title: L10n.t("空格宽度", "Space Width"),
                hint: L10n.t("空格字符的额外宽度", "Extra width for spaces"),
                value: String(format: "%.1f pt", settings.spaceWidth),
                sliderValue: $settings.spaceWidth,
                range: EditorSettings.spaceWidthRange,
                step: EditorSettings.spaceWidthStep
            )
        }
    }

    // MARK: - 样式颜色

    private var styleColorSection: some View {
        section(title: L10n.t("选中样式", "Selection Style")) {
            swatchRow(
                title: L10n.t("高亮颜色", "Highlight"),
                selection: $settings.highlightPreset,
                isHighlight: true
            )
            swatchRow(
                title: L10n.t("文字颜色", "Text Color"),
                selection: $settings.textColorPreset,
                isHighlight: false
            )
        }
    }

    // MARK: - 快捷键

    private var shortcutSection: some View {
        section(title: L10n.t("快捷键", "Shortcuts")) {
            VStack(alignment: .leading, spacing: 8) {
                shortcutRow("⌘N", L10n.t("新建笔记", "New note"))
                shortcutRow("⌘1…9", L10n.t("切换标签页", "Switch tabs"))
                shortcutRow("⌘O", L10n.t("打开侧栏并导航", "Focus sidebar"))
                shortcutRow("⌘D", L10n.t("左右分屏", "Split editor"))
                shortcutRow("⌘W", L10n.t("关闭当前标签页", "Close current tab"))
                shortcutRow("⌘⌥←/→", L10n.t("切换分屏焦点", "Switch split focus"))
                shortcutRow("⌘R", L10n.t("重命名选中项", "Rename selection"))
                shortcutRow("⌘C / ⌘V", L10n.t("复制 / 粘贴选中项", "Copy / paste selection"))
            }
        }
    }

    // MARK: - 组件

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
        }
    }

    private func pickerRow<Value: Hashable>(
        title: String,
        selection: Binding<Value>,
        options: [(Value, String)]
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.0) { value, label in
                    Text(label).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    @ViewBuilder
    private func sliderRow(
        title: String,
        hint: String,
        value: String,
        sliderValue: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .regular).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: sliderValue, in: range, step: step)
                .controlSize(.small)
        }
    }

    private func swatchRow(
        title: String,
        selection: Binding<String>,
        isHighlight: Bool
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            HStack(spacing: 8) {
                ForEach(StyleColorPreset.allCases, id: \.rawValue) { preset in
                    swatch(preset: preset, isHighlight: isHighlight, selection: selection)
                }
            }
        }
    }

    private func swatch(
        preset: StyleColorPreset,
        isHighlight: Bool,
        selection: Binding<String>
    ) -> some View {
        let appearance = NSApp.effectiveAppearance
        let color = isHighlight
            ? DayDreamTheme.inlineHighlightColor(preset.rawValue, for: appearance)
            : DayDreamTheme.inlineTextColor(preset.rawValue, for: appearance)
        let isSelected = selection.wrappedValue == preset.rawValue
        return Button {
            selection.wrappedValue = preset.rawValue
        } label: {
            Circle()
                .fill(Color(nsColor: color))
                .frame(width: 18, height: 18)
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.45), lineWidth: 1.5)
                            .frame(width: 24, height: 24)
                    }
                }
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(presetDisplayName(preset))
    }

    private func presetDisplayName(_ preset: StyleColorPreset) -> String {
        switch preset {
        case .caret: return L10n.t("跟随光标", "Follow caret")
        case .yellow: return L10n.t("暗调黄", "Muted yellow")
        case .green: return L10n.t("暗调绿", "Muted green")
        case .blue: return L10n.t("暗调蓝", "Muted blue")
        case .pink: return L10n.t("暗调粉", "Muted pink")
        }
    }

    private func shortcutRow(_ keys: String, _ description: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(description)
                .font(.system(size: 12))
            Spacer()
        }
    }
}
