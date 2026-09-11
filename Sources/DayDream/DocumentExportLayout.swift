import AppKit
import PDFKit

/// A detached, fully laid out editor. Coordinates remain in editor points so
/// exporting never changes wrapping, zoom, selection or scroll position on screen.
@MainActor
final class DocumentExportLayout {
    let editor: DayDreamTextView
    let pageSize: NSSize
    private(set) var pages: [ClosedRange<CGFloat>] = []
    let margin: CGFloat = 40

    init(markdown: String, sourceURL: URL?, mode: DocumentAppearance, source: DayDreamTextView?) {
        let width = max(200, source?.bounds.width ?? (EditorSettings.shared.contentWidth + 64))
        pageSize = NSSize(width: width, height: width * sqrt(2))
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: width, height: .greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        editor = DayDreamTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100), textContainer: container)
        editor.appearance = mode.appearance
        editor.documentURL = sourceURL
        editor.prepareForExport(markdown: markdown, scale: source?.zoomScale ?? 1)
        // Ultra Focus's large scrolling padding is UI state, not document content.
        editor.textContainerInset.height = margin
        container.widthTracksTextView = false
        container.containerSize.width = width - editor.textContainerInset.width * 2
        let available = max(80, width - editor.textContainerInset.width * 2 - 10)
        var occupied: [NSRect] = []
        storage.enumerateAttribute(.dayDreamMedia, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let card = value as? MediaCard else { return }
            let preview = source?.mediaViews[card.id]?.exportPreview
                ?? card.resolvedURL(documentURL: sourceURL).flatMap { $0.isFileURL && card.kind == .image ? NSImage(contentsOf: $0) : nil }
            let view = MediaCardView(card: card, documentURL: sourceURL, exportPreview: preview, loadPreview: false)
            let w = min(CGFloat(card.width), available)
            var rect = NSRect(x: max(0, available - w) * min(1, max(0, card.x)), y: card.y, width: w, height: w / view.aspectRatio)
            while let previous = occupied.first(where: { $0.insetBy(dx: -12, dy: -12).intersects(rect) }) {
                rect.origin.y = previous.maxY + 16
            }
            occupied.append(rect)
            view.frame = rect.offsetBy(dx: editor.textContainerOrigin.x, dy: margin)
            editor.mediaViews[card.id] = view
            editor.addSubview(view)
        }
        container.exclusionPaths = occupied.map { NSBezierPath(rect: $0.insetBy(dx: -12, dy: -12)) }
        manager.ensureLayout(for: container)
        let bottom = max(manager.usedRect(for: container).maxY, occupied.map(\.maxY).max() ?? 0)
        editor.setFrameSize(NSSize(width: width, height: max(100, bottom + margin * 2)))
        manager.ensureLayout(for: container)
        var protectedRects = occupied
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { rect, _, _, _, _ in
            protectedRects.append(rect)
        }
        let capacity = pageSize.height - margin * 2
        var slices: [ClosedRange<CGFloat>] = []
        var start: CGFloat = 0
        repeat {
            var end = min(max(bottom, 1), start + capacity)
            // Move a page boundary upward until it no longer cuts a line or a
            // card that fits on a page. Oversized cards are clipped across pages.
            while let crossing = protectedRects.filter({ $0.minY < end && $0.maxY > end && $0.minY > start && $0.height <= capacity }).map(\.minY).min() {
                end = crossing
            }
            if end <= start { end = start + capacity }
            slices.append(start...end)
            start = end
        } while start < bottom
        pages = slices
    }

    func pdfData() throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { throw DocumentTransferError.destinationUnavailable }
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw DocumentTransferError.destinationUnavailable }
        editor.effectiveAppearance.performAsCurrentDrawingAppearance {
            for slice in pages {
                context.beginPDFPage(nil)
                context.setFillColor(DayDreamTheme.background(for: editor.effectiveAppearance).cgColor)
                context.fill(box)
                context.saveGState()
                context.translateBy(x: 0, y: pageSize.height)
                context.scaleBy(x: 1, y: -1)
                context.clip(to: CGRect(x: 0, y: margin, width: pageSize.width, height: slice.upperBound - slice.lowerBound))
                context.translateBy(x: 0, y: -slice.lowerBound)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
                editor.drawExportContent(in: NSRect(x: 0, y: margin + slice.lowerBound, width: pageSize.width, height: slice.upperBound - slice.lowerBound))
                NSGraphicsContext.restoreGraphicsState()
                context.restoreGState()
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }
}
