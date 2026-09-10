import Foundation

struct NoteHistory {
    private(set) var entries: [URL] = []
    private(set) var index = -1
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index >= 0 && index + 1 < entries.count }

    mutating func record(_ url: URL) {
        let url = url.standardizedFileURL
        if entries.indices.contains(index), entries[index] == url { return }
        entries = Array(entries.prefix(index + 1))
        entries.append(url)
        if entries.count > 5 { entries.removeFirst(entries.count - 5) }
        index = entries.count - 1
    }

    func destination(by delta: Int) -> URL? {
        let next = index + delta
        return entries.indices.contains(next) ? entries[next] : nil
    }

    mutating func move(by delta: Int) {
        if entries.indices.contains(index + delta) { index += delta }
    }

    mutating func apply(_ change: WorkspaceStructureChange) {
        switch change {
        case let .moved(from, to):
            entries = entries.map { url in
                if url == from { return to.standardizedFileURL }
                if url.path.hasPrefix(from.path + "/") { return to.appendingPathComponent(String(url.path.dropFirst(from.path.count + 1))).standardizedFileURL }
                return url
            }
        case let .removed(removed):
            let before = entries.prefix(max(0, index + 1)).filter { $0 != removed && !$0.path.hasPrefix(removed.path + "/") }.count
            entries.removeAll { $0 == removed || $0.path.hasPrefix(removed.path + "/") }
            index = min(entries.count - 1, before - 1)
        }
    }
}
