import Foundation

/// 极简运行时本地化：跟随设置页的语言切换，SwiftUI 视图通过观察
/// EditorSettings.shared 自动重渲染。
enum L10n {
    static var isZh: Bool { EditorSettings.shared.language == .zh }

    /// 按当前语言返回文案。t("新建笔记", "New Note")
    static func t(_ zh: String, _ en: String) -> String {
        isZh ? zh : en
    }
}
