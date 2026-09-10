import SwiftUI
import UniformTypeIdentifiers

/// 设置页面（DayDream 菜单 → Settings…，⌘,）。
/// 低饱和度、无装饰，与编辑器同一气质。
struct SettingsView: View {
    @ObservedObject private var settings = EditorSettings.shared
    @ObservedObject private var shortcutPreferences = ShortcutPreferences.shared
    @ObservedObject private var fontLibrary = FontLibrary.shared
    @State private var editingToolSlot: Int?
    @State private var fontImportError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                generalSection
                typographySection
                styleColorSection
                writingSection
                writingBarsSection
                shortcutSection
            }
            .padding(28)
        }
        .frame(width: 440, height: 560)
        .sheet(isPresented: Binding(get: { editingToolSlot != nil }, set: { if !$0 { editingToolSlot = nil } })) {
            if let slot = editingToolSlot {
                WritingToolPicker { tool in settings.setWritingTool(tool, bar: slot / 4, slot: slot % 4) }
            }
        }
        .alert(
            L10n.t("无法导入字体", "Couldn’t Import Font"),
            isPresented: Binding(
                get: { fontImportError != nil },
                set: { if !$0 { fontImportError = nil } }
            )
        ) {
            Button(L10n.t("好", "OK")) { fontImportError = nil }
        } message: {
            Text(fontImportError ?? "")
        }
    }

    private var writingSection: some View {
        section(title: L10n.t("写作体验", "Writing")) {
            Toggle(L10n.t("打字特效", "Typing Animation"), isOn: $settings.typingAnimationEnabled)
            if settings.typingAnimationEnabled {
                Picker(L10n.t("特效", "Effect"), selection: $settings.typingAnimationStyle) {
                    Text(L10n.t("弹性显现", "Elastic Reveal")).tag("elastic")
                    Text(L10n.t("字母弹落", "Falling Text")).tag("falling")
                }
                if settings.typingAnimationStyle == "falling" {
                    Text(L10n.t("弹射力度", "Launch strength")).font(.caption)
                    Slider(value: $settings.fallingStrength, in: 0.3...2)
                    Text(L10n.t("消散时间", "Fade lifetime") + String(format: " · %.1f s", settings.fallingLifetime)).font(.caption)
                    Slider(value: $settings.fallingLifetime, in: 0.4...1.6)
                }
            }
            Toggle(L10n.t("显示字数", "Show Word Count"), isOn: $settings.wordCountEnabled)
        }
    }

    private var writingBarsSection: some View {
        section(title: L10n.t("打字工具条", "Typing Bars")) {
            Text(L10n.t("按住 ⌘，重复按数字循环预选；松开 ⌘ 确认。样式与颜色分别覆盖。", "Hold the modifier key and repeat the number to preview. Release the modifier to apply. Style and color replace their previous choice."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            shortcutRow(.resetWritingStyle)
            ForEach(0..<2, id: \.self) { bar in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.t("工具条", "Bar") + " \(bar + 1)").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(shortcutPreferences.shortcut(for: bar == 0 ? .writingBarOne : .writingBarTwo).displayName)
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    ForEach(0..<4, id: \.self) { slot in
                        HStack {
                            Text(String(slot + 1)).foregroundStyle(.tertiary).frame(width: 16)
                            Button {
                                editingToolSlot = bar * 4 + slot
                            } label: {
                                HStack {
                                    if settings.writingBars[bar].indices.contains(slot) {
                                        let tool = settings.writingBars[bar][slot]
                                        Label(tool.title, systemImage: tool.symbol).lineLimit(1)
                                    } else { Text(L10n.t("添加工具", "Add a tool")) }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(14)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
        }
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
            fontPickerRow
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
                ForEach(ShortcutCommand.allCases) { command in
                    shortcutRow(command)
                }
                HStack {
                    Spacer()
                    Button(L10n.t("恢复默认", "Restore Defaults")) {
                        shortcutPreferences.resetToDefaults()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 3)
            }
        }
    }

    // MARK: - 组件

    private var fontPickerRow: some View {
        HStack(spacing: 10) {
            Text(L10n.t("字体", "Font"))
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Button {
                importFont()
            } label: {
                Label(L10n.t("导入…", "Import…"), systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.t("导入 TTF、OTF 或 TTC 字体", "Import a TTF, OTF, or TTC font"))

            Picker("", selection: $settings.fontFamily) {
                ForEach(fontOptions, id: \.0) { value, label in
                    Text(label).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 145)
        }
    }

    private var fontOptions: [(String, String)] {
        var options = EditorSettings.fontChoices.map { ($0.id, $0.displayName) }
        let builtInIDs = Set(options.map(\.0))
        options.append(contentsOf: fontLibrary.fonts
            .filter { !builtInIDs.contains($0.postScriptName) }
            .map { ($0.postScriptName, $0.displayName) })
        return options
    }

    private func importFont() {
        let panel = NSOpenPanel()
        panel.title = L10n.t("导入字体", "Import Font")
        panel.prompt = L10n.t("导入", "Import")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["ttf", "otf", "ttc"].compactMap {
            UTType(filenameExtension: $0)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try fontLibrary.importFont(from: url)
            if let first = imported.first {
                settings.fontFamily = first.postScriptName
            }
        } catch {
            fontImportError = error.localizedDescription
        }
    }

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

    private func shortcutRow(_ command: ShortcutCommand) -> some View {
        HStack {
            Text(shortcutTitle(command))
                .font(.system(size: 12, weight: .regular))
            Spacer()
            ShortcutRecorder(
                shortcut: shortcutPreferences.shortcut(for: command),
                onChange: { shortcutPreferences.set($0, for: command) }
            )
            .frame(width: 78, height: 26)
        }
    }

    private func shortcutTitle(_ command: ShortcutCommand) -> String {
        switch command {
        case .searchFiles: L10n.t("搜索文件", "Search Files")
        case .historyBack: L10n.t("上篇笔记", "Previous note")
        case .historyForward: L10n.t("下篇笔记", "Next note")
        case .focusLeftPane: L10n.t("聚焦左窗格", "Focus left pane")
        case .focusRightPane: L10n.t("聚焦右窗格", "Focus right pane")
        case .newNote: L10n.t("新建笔记", "New note")
        case .toggleSidebar: L10n.t("打开 / 关闭侧栏", "Toggle sidebar")
        case .closeWindow: L10n.t("关闭笔记", "Close note")
        case .renameSelection: L10n.t("重命名选中项", "Rename selection")
        case .copySelection: L10n.t("复制侧栏选中项", "Copy sidebar selection")
        case .pasteSelection: L10n.t("粘贴到侧栏", "Paste into sidebar")
        case .deleteSelection: L10n.t("删除侧栏选中项", "Delete sidebar selection")
        case .bold: L10n.t("粗体", "Bold")
        case .underline: L10n.t("下划线", "Underline")
        case .strikethrough: L10n.t("删除线", "Strikethrough")
        case .toggleFocus: L10n.t("专注模式", "Focus Mode")
        case .italic: L10n.t("斜体", "Italic")
        case .highlight: L10n.t("高亮", "Highlight")
        case .textColor: L10n.t("文字颜色", "Text color")
        case .inlineCode: L10n.t("行内代码", "Inline code")
        case .writingBarOne: L10n.t("工具条 1 · 循环", "Bar 1 · Cycle")
        case .writingBarTwo: L10n.t("工具条 2 · 循环", "Bar 2 · Cycle")
        case .resetWritingStyle: L10n.t("恢复默认打字样式", "Reset Typing Style")
        case .enterUltraFocus: L10n.t("进入极致专注", "Enter Ultra Focus")
        case .exitUltraFocus: L10n.t("退出极致专注", "Exit Ultra Focus")
        case .retype: L10n.t("重打练习", "Retype")
        }
    }
}
