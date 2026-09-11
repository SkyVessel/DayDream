import AppKit
import AVFoundation
import LinkPresentation
import UniformTypeIdentifiers

extension NSAttributedString.Key {
    static let dayDreamMedia = NSAttributedString.Key("DayDreamMedia")
}

struct MediaCard: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case image, video, link }
    var id = UUID()
    var kind: Kind
    var source: String
    var title: String
    var x: Double = 1
    var y: Double = 0
    var width: Double = 280

    static func kind(for url: URL) -> Kind {
        if let type = UTType(filenameExtension: url.pathExtension) {
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        }
        let host = url.host?.lowercased() ?? ""
        if host == "youtu.be" || host.hasSuffix("youtube.com") || host.hasSuffix("vimeo.com") || host.hasSuffix("bilibili.com") { return .video }
        return .link
    }

    var markdown: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "" }
        let url = Self.escape(source)
        let label = Self.escape(title)
        let fallback: String
        switch kind {
        case .image: fallback = "<img src=\"\(url)\" alt=\"\(label)\">"
        case .video: fallback = "<video controls src=\"\(url)\"></video><a href=\"\(url)\">\(label)</a>"
        case .link: fallback = "<a href=\"\(url)\">\(label)</a>"
        }
        return "<figure data-daydream=\"\(data.base64EncodedString())\">\(fallback)</figure>"
    }

    static func parse(_ text: String) -> MediaCard? {
        let prefix = "<figure data-daydream=\""
        guard text.hasPrefix(prefix), text.hasSuffix("</figure>"),
              let end = text.dropFirst(prefix.count).firstIndex(of: "\""),
              let data = Data(base64Encoded: String(text[text.index(text.startIndex, offsetBy: prefix.count)..<end])),
              let card = try? JSONDecoder().decode(MediaCard.self, from: data),
              card.x.isFinite, card.y.isFinite, card.width.isFinite,
              card.y >= 0, card.width >= 80, card.width <= 1400 else { return nil }
        return card
    }

    func resolvedURL(documentURL: URL?) -> URL? {
        if let url = URL(string: source), let scheme = url.scheme {
            return ["https", "http", "file"].contains(scheme.lowercased()) ? url : nil
        }
        return documentURL.map { $0.deletingLastPathComponent().appendingPathComponent(source.removingPercentEncoding ?? source) }
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}

final class MediaCardView: NSView {
    var card: MediaCard
    var onPreviewChanged: (() -> Void)?
    var onResize: ((CGFloat, Bool) -> Void)?
    private(set) var isInteracting = false
    private var resizing = false
    private var initialWidth: CGFloat = 0
    private var hovered = false
    private var hoverTracking: NSTrackingArea?
    var aspectRatio: CGFloat {
        guard let size = thumbnail?.size, size.width > 0, size.height > 0 else { return 1.6 }
        return size.width / size.height
    }
    var onMove: ((NSPoint, Bool) -> Void)?
    var onDelete: (() -> Void)?
    private var thumbnail: NSImage?
    var exportPreview: NSImage? { thumbnail }
    private var resolvedURL: URL?
    private var provider: LPMetadataProvider?
    private var imageTask: URLSessionDataTask?
    private var videoTask: Task<Void, Never>?
    private var dragStart: NSPoint?
    private var initialOrigin = NSPoint.zero
    private var dragged = false
    private var loading = true

    init(card: MediaCard, documentURL: URL?, exportPreview: NSImage? = nil, loadPreview: Bool = true) {
        self.card = card
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        setAccessibilityRole(.image)
        setAccessibilityLabel(card.title)
        toolTip = L10n.t("拖动排版 · 双击打开 · 右键移除", "Drag to arrange · Double-click to open · Right-click to remove")
        resolvedURL = card.resolvedURL(documentURL: documentURL)
        thumbnail = exportPreview
        if loadPreview { self.loadPreview() } else { loading = false }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    private func loadPreview() {
        guard let url = resolvedURL else { loading = false; return }
        if card.kind == .image {
            if url.isFileURL { thumbnail = NSImage(contentsOf: url); loading = false }
            else {
                imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                    let image = data.flatMap { NSImage(data: $0) }
                    DispatchQueue.main.async { self?.thumbnail = image; self?.loading = false; self?.needsDisplay = true; self?.onPreviewChanged?() }
                }
                imageTask?.resume()
            }
        } else if card.kind == .video && (url.isFileURL || !url.pathExtension.isEmpty) {
            videoTask = Task { [weak self] in
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = NSSize(width: 800, height: 500)
                if let result = try? await generator.image(at: .zero), !Task.isCancelled {
                    self?.thumbnail = NSImage(cgImage: result.image, size: .zero)
                    self?.loading = false; self?.needsDisplay = true; self?.onPreviewChanged?()
                } else if !Task.isCancelled { self?.loadLinkPreview(url) }
            }
        } else { loadLinkPreview(url) }
    }

    private func loadLinkPreview(_ url: URL) {
        guard !url.isFileURL else { loading = false; needsDisplay = true; return }
        let provider = LPMetadataProvider()
        provider.timeout = 12
        self.provider = provider
        provider.startFetchingMetadata(for: url) { [weak self] metadata, _ in
            guard let imageProvider = metadata?.imageProvider else {
                DispatchQueue.main.async { self?.loading = false; self?.needsDisplay = true; self?.onPreviewChanged?() }; return
            }
            _ = imageProvider.loadObject(ofClass: NSImage.self) { image, _ in
                DispatchQueue.main.async {
                    self?.thumbnail = image as? NSImage
                    self?.loading = false; self?.needsDisplay = true; self?.onPreviewChanged?()
                }
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking); hoverTracking = tracking
    }
    override func mouseMoved(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    static func fittedRect(imageSize: NSSize, in rect: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.quaternaryLabelColor.withAlphaComponent(0.13).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        let imageRect = bounds
        if let thumbnail {
            thumbnail.draw(in: Self.fittedRect(imageSize: thumbnail.size, in: imageRect), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        } else {
            let symbol = NSImage(systemSymbolName: card.kind == .image ? "photo" : card.kind == .video ? "video" : "link", accessibilityDescription: nil)
            symbol?.draw(in: NSRect(x: imageRect.midX - 18, y: imageRect.midY - 18, width: 36, height: 36))
            let status = loading ? L10n.t("正在载入封面…", "Loading preview…") : L10n.t("封面不可用 · 双击打开", "Preview unavailable · Double-click to open")
            (status as NSString).draw(in: NSRect(x: 10, y: imageRect.midY + 24, width: imageRect.width - 20, height: 18), withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor])
        }
        if card.kind == .video && thumbnail != nil {
            NSColor.black.withAlphaComponent(0.38).setFill()
            NSBezierPath(ovalIn: NSRect(x: imageRect.midX - 21, y: imageRect.midY - 21, width: 42, height: 42)).fill()
            let play = NSBezierPath()
            play.move(to: NSPoint(x: imageRect.midX - 5, y: imageRect.midY - 9))
            play.line(to: NSPoint(x: imageRect.midX + 10, y: imageRect.midY))
            play.line(to: NSPoint(x: imageRect.midX - 5, y: imageRect.midY + 9))
            play.close(); NSColor.white.setFill(); play.fill()
        }
        if hovered || isInteracting {
        NSColor.black.withAlphaComponent(0.58).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: bounds.height - 38, width: bounds.width, height: 38)).fill()
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingMiddle
        (card.title as NSString).draw(in: NSRect(x: 12, y: bounds.height - 34, width: bounds.width - 24, height: 20), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: style])
        NSColor.white.setStroke()
        let handle = NSBezierPath()
        for offset in [CGFloat(5), 10] {
            handle.move(to: NSPoint(x: bounds.maxX - 4 - offset, y: bounds.maxY - 4))
            handle.line(to: NSPoint(x: bounds.maxX - 4, y: bounds.maxY - 4 - offset))
        }
        handle.lineWidth = 1.5; handle.stroke()
        }
        NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12).stroke()
    }

    override func mouseDown(with event: NSEvent) {
        if (superview as? DayDreamTextView)?.retypeSession != nil { return }
        if event.clickCount == 2, let resolvedURL { NSWorkspace.shared.open(resolvedURL); return }
        isInteracting = true
        resizing = convert(event.locationInWindow, from: nil).x >= bounds.maxX - 22 && convert(event.locationInWindow, from: nil).y >= bounds.maxY - 22
        initialWidth = frame.width
        dragStart = event.locationInWindow
        initialOrigin = frame.origin; dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let superview else { return }
        let start = superview.convert(dragStart, from: nil)
        let current = superview.convert(event.locationInWindow, from: nil)
        let next = NSPoint(x: initialOrigin.x + current.x - start.x, y: initialOrigin.y + current.y - start.y)
        dragged = true
        if resizing { onResize?(max(80, initialWidth + current.x - start.x), false) }
        else { onMove?(next, false) }
        autoscroll(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        isInteracting = false
        if dragged {
            if resizing { onResize?(frame.width, true) }
            else { onMove?(frame.origin, true) }
        }
        dragStart = nil; needsDisplay = true
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard (superview as? DayDreamTextView)?.retypeSession == nil else { return nil }
        let menu = NSMenu()
        let item = NSMenuItem(title: L10n.t("移除卡片", "Remove Card"), action: #selector(removeCard), keyEquivalent: "")
        item.target = self; menu.addItem(item); return menu
    }
    @objc private func removeCard() { onDelete?() }
    deinit { provider?.cancel(); imageTask?.cancel(); videoTask?.cancel() }
}
