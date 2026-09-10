import Foundation

/// Only pages created with /page opt into first-heading file naming.
enum PageTitles {
    private static let key = "pages.titleNamedPaths"
    static func contains(_ url: URL) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(url.standardizedFileURL.path)
    }
    static func register(_ url: URL) {
        var paths = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        paths.insert(url.standardizedFileURL.path)
        UserDefaults.standard.set(Array(paths), forKey: key)
    }
    static func unregister(_ url: URL) {
        let paths = (UserDefaults.standard.stringArray(forKey: key) ?? []).filter { $0 != url.standardizedFileURL.path }
        UserDefaults.standard.set(paths, forKey: key)
    }
    static func moved(from: URL, to: URL) {
        guard contains(from) else { return }
        var paths = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        paths.remove(from.standardizedFileURL.path); paths.insert(to.standardizedFileURL.path)
        UserDefaults.standard.set(Array(paths), forKey: key)
    }
    static func title(in markdown: String) -> String? {
        guard let first = markdown.components(separatedBy: .newlines).first, first.hasPrefix("# ") else { return nil }
        let title = InlineMarkdown.parse(String(first.dropFirst(2))).plain.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "\0", with: "")
        return title.isEmpty || title == "." || title == ".." ? nil : title
    }

    /// Rewrite only actual wiki links, leaving fenced and inline code byte-for-byte intact.
    static func replacingLinks(in markdown: String, source: URL, from old: URL, to new: URL, root: URL, files: [URL]) -> String {
        let pattern = try! NSRegularExpression(pattern: #"(`+).*?\1|\[\[([^\]\n]+)\]\]"#)
        var fence: (Character, Int)?
        return markdown.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let first = trimmed.first, first == "`" || first == "~" {
                let count = trimmed.prefix(while: { $0 == first }).count
                if count >= 3 {
                    if let open = fence {
                        if first == open.0 && count >= open.1 { fence = nil }
                    } else { fence = (first, count) }
                    return line
                }
            }
            guard fence == nil else { return line }
            let value = line as NSString
            var output = line
            for match in pattern.matches(in: line, range: NSRange(location: 0, length: value.length)).reversed() {
                let bodyRange = match.range(at: 2)
                guard bodyRange.location != NSNotFound else { continue }
                let prefix = value.substring(to: match.range.location)
                guard prefix.reversed().prefix(while: { $0 == "\\" }).count % 2 == 0 else { continue }
                let parts = value.substring(with: bodyRange).split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                guard let target = parts.first, NoteLinks.resolve(target, from: source, root: root, files: files) == old else { continue }
                let name = new.deletingPathExtension().lastPathComponent
                let label = parts.count == 2 && parts[1] != old.deletingPathExtension().lastPathComponent ? parts[1] : name
                let replacement = "[[" + NoteLinks.name(for: new, root: root) + "|" + label + "]]"
                output = (output as NSString).replacingCharacters(in: match.range, with: replacement)
            }
            return output
        }.joined(separator: "\n")
    }
}

extension Notification.Name {
    static let dayDreamWillRenamePage = Notification.Name("DayDream.willRenamePage")
    static let dayDreamNoteContentsChanged = Notification.Name("DayDream.noteContentsChanged")
}

@MainActor
final class PageRenamePreparation { var canProceed = true }
