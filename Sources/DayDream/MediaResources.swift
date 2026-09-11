import Foundation

/// Keep imported media working when its owning Markdown file is moved or exported.
/// Only the application's own relative resource references are copied.
enum MediaResources {
    static func copyAlongsideDocument(from source: URL, to destination: URL, markdown: String? = nil) throws {
        guard ["md", "markdown"].contains(source.pathExtension.lowercased()),
              source.deletingLastPathComponent().standardizedFileURL != destination.deletingLastPathComponent().standardizedFileURL else { return }
        let text = try markdown ?? String(contentsOf: source, encoding: .utf8)
        let pattern = #"<figure data-daydream="[A-Za-z0-9+/=]+">.*?</figure>"#
        let regex = try NSRegularExpression(pattern: pattern)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count)) {
            guard let card = MediaCard.parse((text as NSString).substring(with: match.range)),
                  card.source.hasPrefix(".daydream-assets/") else { continue }
            let relative = card.source.removingPercentEncoding ?? card.source
            guard relative.split(separator: "/").count == 2, !relative.contains("..") else { continue }
            let from = source.deletingLastPathComponent().appendingPathComponent(relative)
            let to = destination.deletingLastPathComponent().appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            if FileManager.default.fileExists(atPath: to.path) {
                guard FileManager.default.contentsEqual(atPath: from.path, andPath: to.path) else { throw CocoaError(.fileWriteFileExists) }
                continue
            }
            try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: from, to: to)
        }
    }
}
