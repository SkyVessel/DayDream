import SwiftUI

/// 编辑器窗格顶部的标签页条：点击切换、悬停显示关闭按钮。
struct TabStripView: View {
    @ObservedObject var pane: EditorPaneStore
    let onSelect: (Int) -> Void
    let onClose: (Int) -> Void

    @State private var hoveredIndex: Int?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(Array(pane.tabs.enumerated()), id: \.element) { index, url in
                    tabItem(url: url, index: index)
                }
            }
            .padding(.horizontal, 9)
        }
        .frame(height: 34)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.35))
                .frame(height: 0.5)
        }
    }

    private func tabItem(url: URL, index: Int) -> some View {
        let isActive = index == pane.activeIndex
        let isHovered = hoveredIndex == index
        return HStack(spacing: 6) {
            Text(url.deletingPathExtension().lastPathComponent)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isActive ? .primary : .secondary)

            if isActive || isHovered {
                Button {
                    onClose(index)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("关闭标签页", "Close tab"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    isActive
                        ? Color.primary.opacity(0.09)
                        : Color.primary.opacity(isHovered ? 0.05 : 0)
                )
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredIndex = hovering ? index : (hoveredIndex == index ? nil : hoveredIndex)
        }
        .onTapGesture { onSelect(index) }
    }
}
