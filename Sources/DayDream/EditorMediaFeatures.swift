import AppKit
import UniformTypeIdentifiers

extension DayDreamTextView {
    func chooseMediaFiles() {
        guard retypeSession == nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie, .video]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        do { for url in panel.urls { try insertMedia(url: url) } }
        catch { NSAlert(error: error).runModal() }
    }

    func chooseMediaLink() {
        guard retypeSession == nil else { return }
        let alert = NSAlert()
        alert.messageText = L10n.t("插入链接、图片或视频", "Insert Link, Image or Video")
        alert.informativeText = L10n.t("粘贴网页、图片或视频地址", "Paste a web, image or video URL")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 26))
        field.placeholderString = "https://"
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.t("插入", "Insert")); alert.addButton(withTitle: L10n.t("取消", "Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let url = URL(string: field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            let error = NSError(domain: "DayDream", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.t("请输入有效的 http 或 https 链接。", "Enter a valid http or https URL.")])
            NSAlert(error: error).runModal(); return
        }
        do { try insertMedia(url: url) } catch { NSAlert(error: error).runModal() }
    }

    func insertMedia(url: URL) throws {
        guard retypeSession == nil, let storage = textStorage else { return }
        if MediaCard.kind(for: url) == .link, !url.isFileURL { insertInlineLink(url); return }
        var source = url.absoluteString
        if url.isFileURL {
            guard let documentURL else { throw CocoaError(.fileNoSuchFile) }
            let folder = documentURL.deletingLastPathComponent().appendingPathComponent(".daydream-assets", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = UUID().uuidString + "." + url.pathExtension
            try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(name))
            source = ".daydream-assets/" + name
        }
        let kind = MediaCard.kind(for: url)
        let selection = selectedRange()
        var y = max(0, visibleRect.minY - textContainerOrigin.y + 24)
        if let manager = layoutManager, storage.length > 0 {
            let glyph = manager.glyphIndexForCharacter(at: min(selection.location, storage.length - 1))
            y = max(0, manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY)
        }
        let card = MediaCard(kind: kind, source: source, title: url.isFileURL ? url.lastPathComponent : (url.host ?? url.absoluteString), y: y)
        // A media block is a single semantic character, kept in the normal editing/undo path.
        let prefix = selection.location > 0 && (string as NSString).character(at: selection.location - 1) != 10 ? "\n" : ""
        let value = prefix + "\u{FFFC}\n"
        guard shouldChangeText(in: selection, replacementString: value) else { return }
        let replacement = NSMutableAttributedString(string: value, attributes: DayDreamTheme.textAttributes(for: effectiveAppearance))
        replacement.addAttribute(.dayDreamBlockKind, value: MarkdownBlockKind.body, range: NSRange(location: 0, length: replacement.length))
        let anchor = NSRange(location: prefix.utf16.count, length: 1)
        replacement.addAttributes(Self.mediaAnchorAttributes(card), range: anchor)
        storage.replaceCharacters(in: selection, with: replacement)
        setSelectedRange(NSRange(location: selection.location + replacement.length, length: 0))
        setTypingAttributes(for: .body)
        didChangeText()
    }

    static func mediaAnchorAttributes(_ card: MediaCard) -> [NSAttributedString.Key: Any] {
        let attachment = NSTextAttachment()
        attachment.bounds = NSRect(x: 0, y: 0, width: 1, height: 1)
        return [.dayDreamMedia: card, .attachment: attachment, .foregroundColor: NSColor.clear]
    }

    func refreshMediaCards() {
        guard !isLayingOutMedia, let storage = textStorage, let container = textContainer else { return }
        isLayingOutMedia = true
        defer { isLayingOutMedia = false }
        var cards: [(MediaCard, NSRange)] = []
        storage.enumerateAttribute(.dayDreamMedia, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let card = value as? MediaCard { cards.append((card, range)) }
        }
        guard !cards.isEmpty || !mediaViews.isEmpty else { return }
        let ids = Set(cards.map { $0.0.id })
        for id in Array(mediaViews.keys) where !ids.contains(id) { mediaViews.removeValue(forKey: id)?.removeFromSuperview() }
        let width = max(80, bounds.width - textContainerInset.width * 2 - 10)
        // Never reapply saved positions while an AppKit drag is in progress.
        if mediaViews.values.contains(where: \.isInteracting) { return }
        var occupied: [NSRect] = []
        for (card, _) in cards {
            let view: MediaCardView
            if let existing = mediaViews[card.id] { view = existing }
            else {
                view = MediaCardView(card: card, documentURL: documentURL)
                mediaViews[card.id] = view; addSubview(view)
                view.onMove = { [weak self, weak view] point, finished in
                    guard let self, let view else { return }
                    let origin = self.textContainerOrigin
                    let available = max(1, self.bounds.width - self.textContainerInset.width * 2 - 10 - view.frame.width)
                    var moved = view.card
                    moved.x = min(1, max(0, (point.x - origin.x) / available))
                    moved.y = max(0, point.y - origin.y)
                    view.card = moved
                    if finished { self.commitMediaPosition(moved) }
                    else { self.layoutDraggedMedia(view, point: point) }
                }
                view.onPreviewChanged = { [weak self] in self?.refreshMediaCards() }
                view.onResize = { [weak self, weak view] requested, finished in
                    guard let self, let view else { return }
                    let available = max(80, self.bounds.width - self.textContainerInset.width * 2 - 10)
                    let width = min(available, max(80, requested))
                    view.card.width = Double(width)
                    view.setFrameSize(NSSize(width: width, height: width / view.aspectRatio))
                    view.card.x = Double(min(1, max(0, (view.frame.minX - self.textContainerOrigin.x) / max(1, available - width))))
                    if finished { self.commitMediaPosition(view.card) }
                    else { self.layoutDraggedMedia(view, point: view.frame.origin) }
                }
                view.onDelete = { [weak self] in self?.deleteMedia(id: card.id) }
            }
            view.card = card
            let cardWidth = min(CGFloat(card.width), width)
            var rect = NSRect(x: max(0, width - cardWidth) * min(1, max(0, card.x)), y: card.y, width: cardWidth, height: cardWidth / view.aspectRatio)
            // Resolve card collisions in document order. TextKit flows through remaining space.
            while let previous = occupied.first(where: { $0.insetBy(dx: -12, dy: -12).intersects(rect) }) {
                rect.origin.y = previous.maxY + 16
            }
            occupied.append(rect)
            view.frame = rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        }
        container.exclusionPaths = occupied.map { NSBezierPath(rect: $0.insetBy(dx: -12, dy: -12)) }
        layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
        if let bottom = occupied.map(\.maxY).max() {
            minSize.height = bottom + textContainerInset.height * 2 + 30
        } else { minSize.height = 0 }
        sizeToFit(); requestDisplayCommit()
    }

    private func layoutDraggedMedia(_ view: MediaCardView, point: NSPoint) {
        let origin = textContainerOrigin
        view.setFrameOrigin(NSPoint(x: max(origin.x, min(point.x, bounds.width - origin.x - view.frame.width)), y: max(origin.y, point.y)))
        textContainer?.exclusionPaths = mediaViews.values.map {
            NSBezierPath(rect: $0.frame.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -12, dy: -12))
        }
        layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: string.utf16.count), actualCharacterRange: nil)
        requestDisplayCommit()
    }

    private func mediaRange(id: UUID) -> NSRange? {
        guard let storage = textStorage else { return nil }
        var found: NSRange?
        storage.enumerateAttribute(.dayDreamMedia, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if (value as? MediaCard)?.id == id { found = range; stop.pointee = true }
        }
        return found
    }

    func commitMediaPosition(_ card: MediaCard) {
        guard let range = mediaRange(id: card.id), let storage = textStorage,
              let previous = storage.attribute(.dayDreamMedia, at: range.location, effectiveRange: nil) as? MediaCard else { return }
        undoManager?.registerUndo(withTarget: self) { $0.commitMediaPosition(previous) }
        undoManager?.setActionName(L10n.t("移动媒体", "Move Media"))
        storage.addAttribute(.dayDreamMedia, value: card, range: range)
        refreshMediaCards(); notifyMarkdownChange()
    }

    private func deleteMedia(id: UUID) {
        guard let range = mediaRange(id: id), shouldChangeText(in: range, replacementString: "") else { return }
        textStorage?.replaceCharacters(in: range, with: "")
        didChangeText()
    }

    override func paste(_ sender: Any?) {
        guard retypeSession == nil else { return }
        if insertMediaFromPasteboard(.general) { return }
        super.paste(sender)
    }

    private func insertMediaFromPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            do { for url in urls { try insertMedia(url: url) } }
            catch { NSAlert(error: error).runModal() }
            return true
        }
        if let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            do {
                try png.write(to: temp); defer { try? FileManager.default.removeItem(at: temp) }
                try insertMedia(url: temp)
            } catch { NSAlert(error: error).runModal() }
            return true
        }
        if let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: text), ["http", "https"].contains(url.scheme ?? ""), url.host != nil {
            do { try insertMedia(url: url) } catch { NSAlert(error: error).runModal() }
            return true
        }
        return false
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard retypeSession == nil else { return [] }
        if sender.draggingPasteboard.availableType(from: [.fileURL, .URL, .png, .tiff]) != nil { return .copy }
        return super.draggingEntered(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard retypeSession == nil else { return false }
        if sender.draggingPasteboard.availableType(from: [.fileURL, .URL, .png, .tiff]) != nil {
            let point = convert(sender.draggingLocation, from: nil)
            setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
            return insertMediaFromPasteboard(sender.draggingPasteboard)
        }
        return super.performDragOperation(sender)
    }
}
