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
        static let focusModeEnabled = "editor.focusModeEnabled"
        static let wordCompletionEnabled = "editor.wordCompletionEnabled"
        static let automaticSpellingCorrectionEnabled = "editor.automaticSpellingCorrectionEnabled"
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

    // MARK: - 写作辅助

    @Published var focusModeEnabled: Bool {
        didSet { persist(focusModeEnabled, forKey: Keys.focusModeEnabled) }
    }

    @Published var wordCompletionEnabled: Bool {
        didSet { persist(wordCompletionEnabled, forKey: Keys.wordCompletionEnabled) }
    }

    @Published var automaticSpellingCorrectionEnabled: Bool {
        didSet {
            persist(
                automaticSpellingCorrectionEnabled,
                forKey: Keys.automaticSpellingCorrectionEnabled
            )
        }
    }

    @Published var typingAnimationStyle: String {
        didSet { persist(typingAnimationStyle, forKey: "editor.typingAnimationStyle") }
    }
    @Published var fallingStrength: Double {
        didSet { persist(fallingStrength, forKey: "editor.fallingStrength") }
    }
    @Published var fallingLifetime: Double {
        didSet { persist(fallingLifetime, forKey: "editor.fallingLifetime") }
    }
    @Published var typingAnimationEnabled: Bool {
        didSet { persist(typingAnimationEnabled, forKey: "editor.typingAnimationEnabled") }
    }
    @Published var wordCountEnabled: Bool {
        didSet { persist(wordCountEnabled, forKey: "editor.wordCountEnabled") }
    }
    @Published var writingBars: [[WritingTool]] {
        didSet {
            if let data = try? JSONEncoder().encode(writingBars) { persist(data, forKey: "editor.writingBars") }
        }
    }

    func setWritingTool(_ tool: WritingTool?, bar: Int, slot: Int) {
        guard writingBars.indices.contains(bar), (0..<4).contains(slot) else { return }
        var tools = writingBars[bar]
        if let tool {
            if slot < tools.count { tools[slot] = tool } else { tools.append(tool) }
        } else if slot < tools.count { tools.remove(at: slot) }
        writingBars[bar] = Array(tools.prefix(4))
    }

    // MARK: - 字体解析

    var editorFont: NSFont {
        // 自定义字体以进程级方式注册；访问字体前确保已从应用支持目录加载。
        _ = FontLibrary.shared.fonts
        return Self.resolveFont(fontFamily, size: DayDreamTheme.baseFontSize)
    }

    static func resolveFont(_ fontFamily: String, size: CGFloat) -> NSFont {
        switch fontFamily {
        case "", "-apple-system", "system-ui":
            return .systemFont(ofSize: size, weight: .regular)
        case "serif", "rounded", "mono", "monospace", "SF Pro Rounded":
            let design: NSFontDescriptor.SystemDesign = switch fontFamily {
            case "serif": .serif
            case "rounded", "SF Pro Rounded": .rounded
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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        typingAnimationStyle = defaults.string(forKey: "editor.typingAnimationStyle") ?? "elastic"
        fallingStrength = defaults.object(forKey: "editor.fallingStrength") as? Double ?? 1
        fallingLifetime = defaults.object(forKey: "editor.fallingLifetime") as? Double ?? 0.9
        typingAnimationEnabled = defaults.object(forKey: "editor.typingAnimationEnabled") as? Bool ?? true
        wordCountEnabled = defaults.object(forKey: "editor.wordCountEnabled") as? Bool ?? true
        if let data = defaults.data(forKey: "editor.writingBars"),
           let bars = try? JSONDecoder().decode([[WritingTool]].self, from: data), bars.count == 2 {
            writingBars = bars.map { Array($0.prefix(4)) }
        } else { writingBars = WritingTool.defaultBars }
        contentWidth = (defaults.object(forKey: Keys.contentWidth) as? Double).map { CGFloat($0) } ?? 1200
        lineHeightMultiple = (defaults.object(forKey: Keys.lineHeightMultiple) as? Double)
            .map { CGFloat($0) } ?? DayDreamTheme.lineHeightMultiple
        spaceWidth = (defaults.object(forKey: Keys.spaceWidth) as? Double).map { CGFloat($0) } ?? 0
        fontFamily = defaults.string(forKey: Keys.fontFamily) ?? ""
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .zh
        appearanceMode = AppAppearanceMode(rawValue: defaults.string(forKey: Keys.appearanceMode) ?? "") ?? .system
        highlightPreset = defaults.string(forKey: Keys.highlightPreset) ?? StyleColorPreset.caret.rawValue
        textColorPreset = defaults.string(forKey: Keys.textColorPreset) ?? StyleColorPreset.caret.rawValue
        focusModeEnabled = defaults.object(forKey: Keys.focusModeEnabled) as? Bool ?? false
        wordCompletionEnabled = defaults.object(forKey: Keys.wordCompletionEnabled) as? Bool ?? true
        automaticSpellingCorrectionEnabled = defaults.object(
            forKey: Keys.automaticSpellingCorrectionEnabled
        ) as? Bool ?? false
    }

    private func persist(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
