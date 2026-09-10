import AppKit

/// Wiki links remain readable Markdown on disk; their URL is only an editor attribute.
enum NoteLinks {
    static let scheme = "daydream-note:"
    static func destination(_ target: String) -> String {
        scheme + (target.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? target)
    }
    static func target(_ destination: String) -> String? {
        guard destination.hasPrefix(scheme) else { return nil }
        return String(destination.dropFirst(scheme.count)).removingPercentEncoding
    }
    static func files(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL, ["md", "markdown", "pdf"].contains(url.pathExtension.lowercased()),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            return url.standardizedFileURL
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
    static func resolve(_ target: String, from source: URL?, root: URL, files: [URL]? = nil) -> URL? {
        let files = files ?? self.files(in: root)
        let target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }
        for parent in [source?.deletingLastPathComponent(), root].compactMap({ $0 }) {
            let candidate = parent.appendingPathComponent(target).standardizedFileURL
            if let exact = files.first(where: { $0 == candidate || $0.deletingPathExtension() == candidate }) { return exact }
        }
        let matches = files.filter { $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(target) == .orderedSame || $0.lastPathComponent.caseInsensitiveCompare(target) == .orderedSame }
        return matches.count == 1 ? matches[0] : nil
    }
    static func name(for url: URL, root: URL) -> String {
        let prefix = root.standardizedFileURL.path + "/"
        let path = url.deletingPathExtension().standardizedFileURL.path
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : url.deletingPathExtension().lastPathComponent
    }
    static func backlinks(to document: URL, root: URL) -> [URL] {
        let all = files(in: root)
        return all.filter { url in
            guard url != document, url.pathExtension.lowercased() != "pdf", let source = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return MarkdownDocumentCodec.parse(source).blocks.contains { block in
                if case .code = block.kind { return false }
                return InlineMarkdown.parse(block.text).runs.contains { run in
                    guard let destination = run.style.linkDestination, let target = target(destination) else { return false }
                    return resolve(target, from: url, root: root, files: all) == document
                }
            }
        }
    }
}

extension DayDreamTextView {
    override func clicked(onLink link: Any, at charIndex: Int) {
        let destination = (link as? URL)?.absoluteString ?? (link as? String) ?? ""
        if let target = NoteLinks.target(destination) { openNoteLink?(target); return }
        super.clicked(onLink: link, at: charIndex)
    }

    func insertNoteLink(target: String, label: String, replacing range: NSRange) -> Bool {
        let kind = currentBlockKind(at: range.location)
        let indentation = currentListIndentation(at: range.location)
        var base = DayDreamTheme.textAttributes(for: effectiveAppearance, scale: zoomScale, blockKind: kind, listIndentation: indentation)
        base[.dayDreamBlockKind] = kind
        base[.dayDreamListIndentation] = indentation
        if let storage = textStorage, storage.length > 0 {
            base[.dayDreamOrderedStart] = storage.attribute(.dayDreamOrderedStart, at: min(range.location, storage.length - 1), effectiveRange: nil)
        }
        let attributes = DayDreamTheme.inlineStyledAttributes(base: base, bold: false, italic: false, inlineCode: false, linkDestination: NoteLinks.destination(target), imageDestination: nil, textColorName: nil, highlightName: nil, for: effectiveAppearance)
        guard shouldChangeText(in: range, replacementString: label) else { return false }
        textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: label, attributes: attributes))
        setSelectedRange(NSRange(location: range.location + label.utf16.count, length: 0))
        setTypingAttributes(for: kind, listIndentation: indentation)
        didChangeText()
        return true
    }

    func finishTypedNoteLink() {
        guard !hasMarkedText() else { return }
        if case .code = currentBlockKind(at: selectedRange().location) { return }
        if selectedRange().location > 0, textStorage?.attribute(.dayDreamInlineCode, at: selectedRange().location - 1, effectiveRange: nil) as? Bool == true { return }
        let end = selectedRange().location
        let prefix = (string as NSString).substring(to: end)
        guard prefix.hasSuffix("]]"), let opening = prefix.range(of: "[[", options: .backwards) else { return }
        let body = String(prefix[opening.upperBound...].dropLast(2))
        guard !body.contains("\n"), !body.isEmpty else { return }
        let parts = body.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let target = parts[0].trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        let location = prefix[..<opening.lowerBound].utf16.count
        _ = insertNoteLink(target: target, label: parts.count == 2 ? parts[1] : target, replacing: NSRange(location: location, length: end - location))
    }
}
