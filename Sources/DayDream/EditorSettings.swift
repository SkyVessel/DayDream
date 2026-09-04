import SwiftUI
import AppKit

/// UI 语言。
enum AppLanguage: String, CaseIterable, Sendable {
    case zh, en

    var displayName: String { self == .zh ? "中文" : "English" }
}

/// 外观模式。
enum AppAppearanceMode: String, CaseIterable, Sendable {
    case system, light, dark

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// 编辑器排版与界面设置：持久化到 UserDefaults，改动实时生效。
final class EditorSettings: ObservableObject {
    static let shared = EditorSettings()

    static let didChangeNotification = Notification.Name("DayDream.EditorSettings.didChange")

    // MARK: - 可调范围

    static let contentWidthRange: ClosedRange<CGFloat> = 480...1400
    static let contentWidthStep: CGFloat = 10
    static let lineHeightRange: ClosedRange<CGFloat> = 1.1...2.2
    static let lineHeightStep: CGFloat = 0.05
    static let spaceWidthRange: ClosedRange<CGFloat> = 0...6
    static let spaceWidthStep: CGFloat = 0.5

    /// 可选字体。id 为空 = 系统默认（SF）；serif/rounded/mono 走系统设计字族。
    static let fontChoices: [(id: String, displayName: String)] = [
        ("", "System (SF Pro)"),
        ("serif", "New York (Serif)"),
        ("rounded", "SF Rounded"),
        ("mono", "SF Mono"),
        ("Menlo", "Menlo"),
        ("Georgia", "Georgia"),
        ("Avenir Next", "Avenir Next"),
        ("PingFang SC", "PingFang SC"),
        ("Hiragino Sans GB", "Hiragino Sans GB"),
    ]

    private enum Keys {
        static let contentWidth = "editor.contentWidth"
        static let lineHeightMultiple = "editor.lineHeightMultiple"
        static let spaceWidth = "editor.spaceWidth"
        static let language = "app.language"
        static let appearanceMode = "app.appearanceMode"
        static let fontFamily = "editor.fontFamily"
        static let highlightPreset = "editor.highlightPreset"
        static let textColorPreset = "editor.textColorPreset"
    }

    // MARK: - 排版

    /// 一行有多长（pt）。默认 1200，与早期版本的固定值一致。
    @Published var contentWidth: CGFloat {
        didSet { persist(Double(contentWidth), forKey: Keys.contentWidth) }
    }

    /// 两行之间的距离（行高倍数）。默认沿用设计令牌里的 1.55。
    @Published var lineHeightMultiple: CGFloat {
        didSet { persist(Double(lineHeightMultiple), forKey: Keys.lineHeightMultiple) }
    }

    /// 空格宽度（pt，在词距基础上额外加宽空格）。
    @Published var spaceWidth: CGFloat {
        didSet { persist(Double(spaceWidth), forKey: Keys.spaceWidth) }
    }

    /// 字体。空字符串 = 系统默认。
    @Published var fontFamily: String {
        didSet { persist(fontFamily, forKey: Keys.fontFamily) }
    }

    // MARK: - 界面

    @Published var language: AppLanguage {
        didSet { persist(language.rawValue, forKey: Keys.language) }
    }

    @Published var appearanceMode: AppAppearanceMode {
        didSet {
            persist(appearanceMode.rawValue, forKey: Keys.appearanceMode)
            applyAppearance()
        }
    }

    // MARK: - 样式颜色（悬浮工具条使用）

    /// 高亮颜色预设名（StyleColorPreset 的 rawValue）。
    @Published var highlightPreset: String {
        didSet { persist(highlightPreset, forKey: Keys.highlightPreset) }
    }

    /// 文字颜色预设名。
    @Published var textColorPreset: String {
        didSet { persist(textColorPreset, forKey: Keys.textColorPreset) }
    }

    // MARK: - 字体解析

    var editorFont: NSFont {
        let size = DayDreamTheme.baseFontSize
        switch fontFamily {
        case "":
            return .systemFont(ofSize: size, weight: .regular)
        case "serif", "rounded", "mono":
            let design: NSFontDescriptor.SystemDesign = switch fontFamily {
            case "serif": .serif
            case "rounded": .rounded
            default: .monospaced
            }
            guard let descriptor = NSFont.systemFont(ofSize: size)
                .fontDescriptor.withDesign(design),
                let font = NSFont(descriptor: descriptor, size: size) else {
                return .systemFont(ofSize: size, weight: .regular)
            }
            return font
        default:
            return NSFont(name: fontFamily, size: size) ?? .systemFont(ofSize: size, weight: .regular)
        }
    }

    // MARK: - 外观

    /// 应用外观设置（启动时与改动时调用）。nil = 跟随系统。
    func applyAppearance() {
        NSApp.appearance = appearanceMode.nsAppearance
    }

    // MARK: - 持久化

    private init() {
        let defaults = UserDefaults.standard
        contentWidth = (defaults.object(forKey: Keys.contentWidth) as? Double).map { CGFloat($0) } ?? 1200
        lineHeightMultiple = (defaults.object(forKey: Keys.lineHeightMultiple) as? Double)
            .map { CGFloat($0) } ?? DayDreamTheme.lineHeightMultiple
        spaceWidth = (defaults.object(forKey: Keys.spaceWidth) as? Double).map { CGFloat($0) } ?? 0
        fontFamily = defaults.string(forKey: Keys.fontFamily) ?? ""
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .zh
        appearanceMode = AppAppearanceMode(rawValue: defaults.string(forKey: Keys.appearanceMode) ?? "") ?? .system
        highlightPreset = defaults.string(forKey: Keys.highlightPreset) ?? StyleColorPreset.caret.rawValue
        textColorPreset = defaults.string(forKey: Keys.textColorPreset) ?? StyleColorPreset.caret.rawValue
    }

    private func persist(_ value: Any, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}

