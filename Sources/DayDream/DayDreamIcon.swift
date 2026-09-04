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
}

struct DayDreamIcon: View {
    let name: DayDreamIconName
    var color: Color = .primary
    var strokeWidth: CGFloat = 1.7

    var body: some View {
        DayDreamIconShape(name: name)
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: strokeWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

private struct DayDreamIconShape: Shape {
    let name: DayDreamIconName

    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 24
        let scaleY = rect.height / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scaleX, y: rect.minY + y * scaleY)
        }

        var path = Path()
        switch name {
        case .sidebar:
            path.addRoundedRect(
                in: CGRect(x: rect.minX + 3 * scaleX, y: rect.minY + 3 * scaleY, width: 18 * scaleX, height: 18 * scaleY),
                cornerSize: CGSize(width: 2 * scaleX, height: 2 * scaleY)
            )
            path.move(to: point(9, 3))
            path.addLine(to: point(9, 21))
        case .folder:
            path.move(to: point(3, 7))
            path.addCurve(to: point(5, 5), control1: point(3, 5.9), control2: point(3.9, 5))
            path.addLine(to: point(9, 5))
            path.addLine(to: point(11, 7))
            path.addLine(to: point(19, 7))
            path.addCurve(to: point(21, 9), control1: point(20.1, 7), control2: point(21, 7.9))
            path.addLine(to: point(21, 18))
            path.addCurve(to: point(19, 20), control1: point(21, 19.1), control2: point(20.1, 20))
            path.addLine(to: point(5, 20))
            path.addCurve(to: point(3, 18), control1: point(3.9, 20), control2: point(3, 19.1))
            path.closeSubpath()
        case .fileText:
            path.move(to: point(6, 3))
            path.addLine(to: point(14, 3))
            path.addLine(to: point(19, 8))
            path.addLine(to: point(19, 21))
            path.addLine(to: point(6, 21))
            path.closeSubpath()
            path.move(to: point(14, 3))
            path.addLine(to: point(14, 8))
            path.addLine(to: point(19, 8))
            path.move(to: point(9, 13))
            path.addLine(to: point(16, 13))
            path.move(to: point(9, 17))
            path.addLine(to: point(15, 17))
        case .chevronLeft, .chevronRight:
            let points: [(CGFloat, CGFloat)] = name == .chevronLeft
                ? [(15, 6), (9, 12), (15, 18)]
                : [(9, 6), (15, 12), (9, 18)]
            path.move(to: point(points[0].0, points[0].1))
            path.addLine(to: point(points[1].0, points[1].1))
            path.addLine(to: point(points[2].0, points[2].1))
        case .plus:
            path.move(to: point(12, 5))
            path.addLine(to: point(12, 19))
            path.move(to: point(5, 12))
            path.addLine(to: point(19, 12))
        }
        return path
    }
}
