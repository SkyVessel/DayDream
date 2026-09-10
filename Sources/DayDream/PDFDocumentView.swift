import PDFKit
import SwiftUI

struct PDFDocumentView: NSViewRepresentable {
    let url: URL
    var register: ((ReaderPDFView) -> Void)?

    func makeNSView(context: Context) -> ReaderPDFView {
        let view = ReaderPDFView()
        register?(view)
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        view.needsInitialScale = true
        view.applyReadingAppearance()
        return view
    }

    func updateNSView(_ view: ReaderPDFView, context: Context) {
        view.applyReadingAppearance()
        if view.document?.documentURL?.standardizedFileURL != url.standardizedFileURL {
            view.document = PDFDocument(url: url)
            view.needsInitialScale = true
            view.needsLayout = true
        }
    }
}

final class ReaderPDFView: PDFView {
    var needsInitialScale = true

    override func layout() {
        super.layout()
        applyReadingAppearance()
        guard needsInitialScale, bounds.width > 100, bounds.height > 100, document != nil else { return }
        needsInitialScale = false
        autoScales = false
        minScaleFactor = 0.1
        maxScaleFactor = 8
        scaleFactor = max(minScaleFactor, scaleFactorForSizeToFit * 0.88)
    }

    override var acceptsFirstResponder: Bool { true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let target = PaneShortcutRouting.current(in: window)?.documentResponder, target !== self { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers == .command || modifiers == [.command, .shift] else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "+", "=": adjustScale(by: 1.15)
        case "-", "_": adjustScale(by: 1 / 1.15)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    func applyReadingAppearance() {
        // PDFKit renders the original page, without theme inversion or raster filters.
        appearance = NSAppearance(named: .aqua)
        backgroundColor = NSColor(white: 0.92, alpha: 1)
    }

    func adjustScale(by factor: CGFloat) {
        needsInitialScale = false
        autoScales = false
        scaleFactor = min(maxScaleFactor, max(minScaleFactor, scaleFactor * factor))
    }
}
