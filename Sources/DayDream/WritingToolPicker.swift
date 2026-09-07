import SwiftUI

struct WritingToolPicker: View {
    let choose: (WritingTool?) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var fonts = FontLibrary.shared
    @State private var search = ""
    @State private var category = ""
    private var tools: [WritingTool] { WritingTool.allCases }
    private var categories: [String] { Array(Set(tools.map(\.category))).sorted() }
    private var matches: [WritingTool] {
        tools.filter { (category.isEmpty || $0.category == category) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.t("选择工具", "Choose a tool")).font(.title2.weight(.semibold))
                Spacer()
                Button(L10n.t("完成", "Done")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            TextField(L10n.t("搜索字体、颜色或样式", "Search fonts, colors or styles"), text: $search)
                .textFieldStyle(.roundedBorder)
            Picker(L10n.t("分类", "Category"), selection: $category) {
                Text(L10n.t("全部", "All")).tag("")
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(matches) { tool in
                        Button {
                            choose(tool); dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tool.symbol).frame(width: 22)
                                    .foregroundStyle(tool.isColor || tool.highlightColor != nil ? Color(nsColor: tool.highlightColor.map { DayDreamTheme.inlineHighlightColor($0, for: NSApp.effectiveAppearance) } ?? DayDreamTheme.inlineTextColor(tool.rawValue, for: NSApp.effectiveAppearance)) : Color.primary)
                                Text(tool.title).font(tool.fontName.map { Font(EditorSettings.resolveFont($0, size: 15)) } ?? .system(size: 14))
                                Spacer()
                                Text(tool.category).font(.caption).foregroundStyle(.secondary)
                            }.padding(10).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if matches.isEmpty { Text(L10n.t("没有匹配的工具", "No matching tools")).foregroundStyle(.secondary).padding() }
                }
            }
            Divider()
            Button(L10n.t("清空这个位置", "Clear this slot")) { choose(nil); dismiss() }
                .foregroundStyle(.secondary)
        }.padding(24).frame(width: 560, height: 510)
    }
}
