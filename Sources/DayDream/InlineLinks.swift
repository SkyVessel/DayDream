import AppKit

extension NSAttributedString.Key {
    static let dayDreamLinkIcon = NSAttributedString.Key("DayDreamLinkIcon")
}

/// Icons are presentation attachments; serialization emits only the Markdown link.
final class SiteIconAttachment: NSTextAttachment {
    private var task: URLSessionDataTask?
    init(url: URL, size: CGFloat) {
        super.init(data: nil, ofType: nil)
        bounds = NSRect(x: 0, y: -2, width: size, height: size)
        image = NSImage(systemSymbolName: "globe", accessibilityDescription: url.host)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(components.scheme ?? "") else { return }
        components.path = "/favicon.ico"; components.query = nil; components.fragment = nil
        guard let iconURL = components.url else { return }
        var request = URLRequest(url: iconURL)
        request.timeoutInterval = 8
        task = URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data, data.count < 2_000_000, let icon = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
                    if DayDreamTheme.isDark(NSApp.effectiveAppearance) {
                        NSColor.white.withAlphaComponent(0.94).setFill()
                        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
                    }
                    icon.draw(in: MediaCardView.fittedRect(imageSize: icon.size, in: rect.insetBy(dx: 2, dy: 2)))
                    return true
                }
                // Every open editor sharing this attachment must repaint, without editing text.
                NotificationCenter.default.post(name: .siteIconDidLoad, object: self)
            }
        }
        task?.resume()
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    deinit { task?.cancel() }
}

extension Notification.Name { static let siteIconDidLoad = Notification.Name("DayDreamSiteIconDidLoad") }

enum InlineLinkPresentation {
    static func addIcons(to text: NSMutableAttributedString) {
        var links: [(NSRange, URL)] = []
        text.enumerateAttribute(.dayDreamLink, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let value = value as? String, let url = URL(string: value),
               ["https", "http"].contains(url.scheme ?? "") { links.append((range, url)) }
        }
        for (range, url) in links.reversed() {
            if range.location > 0, text.attribute(.dayDreamLinkIcon, at: range.location - 1, effectiveRange: nil) != nil { continue }
            let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? DayDreamTheme.font
            let attachment = SiteIconAttachment(url: url, size: font.pointSize * 0.85)
            var attributes = text.attributes(at: range.location, effectiveRange: nil)
            attributes[.dayDreamLink] = nil
            attributes[.dayDreamLinkIcon] = url.absoluteString
            attributes[.attachment] = attachment
            attributes[.kern] = 4
            text.insert(NSAttributedString(string: "\u{FFFC}", attributes: attributes), at: range.location)
        }
    }
}

extension DayDreamTextView {
    func insertInlineLink(_ url: URL) {
        guard retypeSession == nil else { return }
        let selection = selectedRange()
        let label = selection.length > 0 ? (string as NSString).substring(with: selection) : url.absoluteString
        let value = NSMutableAttributedString(string: label, attributes: DayDreamTheme.inlineStyledAttributes(
            base: DayDreamTheme.textAttributes(for: effectiveAppearance), bold: false, italic: false,
            inlineCode: false, linkDestination: url.absoluteString, imageDestination: nil,
            textColorName: nil, highlightName: nil, for: effectiveAppearance))
        InlineLinkPresentation.addIcons(to: value)
        guard shouldChangeText(in: selection, replacementString: value.string) else { return }
        textStorage?.replaceCharacters(in: selection, with: value)
        setSelectedRange(NSRange(location: selection.location + value.length, length: 0))
        setTypingAttributes(for: currentBlockKind(at: selectedRange().location))
        didChangeText()
    }

    @objc func siteIconLoaded(_ notification: Notification) {
        guard let attachment = notification.object as? SiteIconAttachment, let storage = textStorage else { return }
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let value = value as? NSTextAttachment, value === attachment {
                layoutManager?.invalidateDisplay(forCharacterRange: range)
            }
        }
        requestDisplayCommit()
    }
}
