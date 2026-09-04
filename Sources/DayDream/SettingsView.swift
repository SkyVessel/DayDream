import SwiftUI

/// 设置页面（DayDream 菜单 → Settings…，⌘,）。
/// 低饱和度、无装饰，与编辑器同一气质。
struct SettingsView: View {
    @ObservedObject private var settings = EditorSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            settingRow(
                title: "一行长度",
                hint: "内容始终居中",
                value: "\(Int(settings.contentWidth)) pt"
            ) {
                Slider(
                    value: $settings.contentWidth,
                    in: EditorSettings.contentWidthRange,
                    step: EditorSettings.contentWidthStep
                )
            }

            settingRow(
                title: "行距",
                hint: "两行之间的距离",
                value: String(format: "%.2f", settings.lineHeightMultiple)
            ) {
                Slider(
                    value: $settings.lineHeightMultiple,
                    in: EditorSettings.lineHeightRange,
                    step: EditorSettings.lineHeightStep
                )
            }
        }
        .padding(28)
        .frame(width: 400)
    }

    @ViewBuilder
    private func settingRow<Content: View>(
        title: String,
        hint: String,
        value: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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
            control()
                .controlSize(.small)
        }
    }
}
