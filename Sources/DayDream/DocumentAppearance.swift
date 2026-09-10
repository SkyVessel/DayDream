import AppKit

enum DocumentAppearance: String, CaseIterable {
    case light, dark
    var appearance: NSAppearance { NSAppearance(named: self == .dark ? .darkAqua : .aqua)! }
    var background: NSColor { self == .dark ? NSColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 1) : .white }
    static var current: Self { DayDreamTheme.isDark(NSApp.effectiveAppearance) ? .dark : .light }
    static func stored(for url: URL?) -> Self? {
        guard let url, let value = UserDefaults.standard.string(forKey: "document.appearance." + url.standardizedFileURL.path) else { return nil }
        return Self(rawValue: value)
    }
    func store(for url: URL) { UserDefaults.standard.set(rawValue, forKey: "document.appearance." + url.standardizedFileURL.path) }
}

final class DocumentAppearancePicker: NSView {
    private let popup = NSPopUpButton()
    var selection: DocumentAppearance { popup.indexOfSelectedItem == 1 ? .dark : .light }
    init(selection: DocumentAppearance) {
        super.init(frame: NSRect(x: 0, y: 0, width: 270, height: 38))
        let label = NSTextField(labelWithString: L10n.t("外观", "Appearance"))
        label.frame = NSRect(x: 0, y: 10, width: 90, height: 20)
        popup.addItems(withTitles: ["Light", "Dark"])
        popup.selectItem(at: selection == .dark ? 1 : 0)
        popup.frame = NSRect(x: 95, y: 6, width: 160, height: 28)
        addSubview(label); addSubview(popup)
    }
    required init?(coder: NSCoder) { fatalError() }
}
