import SwiftUI

/// Morphicons works with Lucide-style 24×24 stroke data. The native macOS app
/// renders the same simple stroke vocabulary directly, without a JavaScript runtime.
/// Sources: https://www.morphicons.com and https://lucide.dev (ISC license).
enum DayDreamIconName: CaseIterable, Hashable {
    case sidebar
    case folder
    case fileText
    case chevronLeft
    case chevronRight
    case plus
    case importDocument
    case exportDocument
    case more

    var systemSymbolName: String {
        switch self {
        case .sidebar: "sidebar.left"
        case .folder: "folder"
        case .fileText: "doc.text"
        case .chevronLeft: "chevron.left"
        case .chevronRight: "chevron.right"
        case .plus: "plus"
        case .importDocument: "square.and.arrow.down"
        case .exportDocument: "square.and.arrow.up"
        case .more: "ellipsis"
        }
    }
}

struct DayDreamIcon: View {
    let name: DayDreamIconName
    var color: Color = .primary
    var strokeWidth: CGFloat = 1.7

    var body: some View {
        Image(systemName: name.systemSymbolName)
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.monochrome)
            .fontWeight(symbolWeight)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }

    private var symbolWeight: Font.Weight {
        if strokeWidth >= 2.2 { return .semibold }
        if strokeWidth >= 1.8 { return .medium }
        return .regular
    }
}
