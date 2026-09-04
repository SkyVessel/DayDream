import SwiftUI

/// 编辑器排版设置：持久化到 UserDefaults，改动实时生效。
///
/// 目前只有行距相关的两项：
/// - `contentWidth`：一行有多长（内容栏始终居中）
/// - `lineHeightMultiple`：两行之间的距离（行高倍数）
final class EditorSettings: ObservableObject {
    static let shared = EditorSettings()

    static let didChangeNotification = Notification.Name("DayDream.EditorSettings.didChange")

    // 可调范围
    static let contentWidthRange: ClosedRange<CGFloat> = 480...1400
    static let contentWidthStep: CGFloat = 10
    static let lineHeightRange: ClosedRange<CGFloat> = 1.1...2.2
    static let lineHeightStep: CGFloat = 0.05

    private enum Keys {
        static let contentWidth = "editor.contentWidth"
        static let lineHeightMultiple = "editor.lineHeightMultiple"
    }

    /// 一行有多长（pt）。默认 1200，与早期版本的固定值一致。
    @Published var contentWidth: CGFloat {
        didSet { persist(Double(contentWidth), forKey: Keys.contentWidth) }
    }

    /// 两行之间的距离（行高倍数）。默认沿用设计令牌里的 1.55。
    @Published var lineHeightMultiple: CGFloat {
        didSet { persist(Double(lineHeightMultiple), forKey: Keys.lineHeightMultiple) }
    }

    private init() {
        let defaults = UserDefaults.standard
        let storedWidth = defaults.object(forKey: Keys.contentWidth) as? Double
        let storedSpacing = defaults.object(forKey: Keys.lineHeightMultiple) as? Double
        contentWidth = storedWidth.map { CGFloat($0) } ?? 1200
        lineHeightMultiple = storedSpacing.map { CGFloat($0) } ?? DayDreamTheme.lineHeightMultiple
    }

    private func persist(_ value: Double, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
