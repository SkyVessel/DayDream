import SwiftUI
import PDFKit
import QuartzCore

struct LibrarySearchResult: Identifiable {
    let url: URL
    let path: String
    let preview: String
    var id: URL { url }
    var title: String { url.deletingPathExtension().lastPathComponent }
}

@MainActor
final class LibrarySearchModel: ObservableObject {
    @Published var query = "" { didSet { search() } }
    @Published var results: [LibrarySearchResult] = []
    @Published var selected = 0 { didSet { loadSelectedPreview() } }
    @Published var searching = false
    var choose: ((URL, Bool) -> Void)?
    private var revision = UUID()
    let root: URL
    let linking: Bool
    init(root: URL, linking: Bool = false) { self.root = root.standardizedFileURL; self.linking = linking }

    func search() {
        let revision = UUID(); self.revision = revision
        let query = query
        let root = root
        let linking = linking
        searching = true
        results = []
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let matches = LibrarySearchMatching.files(root: root, query: query, notesOnly: linking).prefix(40)
            let results = matches.map { url in
                LibrarySearchResult(url: url, path: LibrarySearchMatching.relativePath(url, root: root), preview: "…")
            }
            DispatchQueue.main.async {
                guard let self, self.revision == revision else { return }
                self.results = results; self.selected = 0; self.searching = false
            }
        }
    }
    private func loadSelectedPreview() {
        guard results.indices.contains(selected) else { return }
        let item = results[selected]
        guard item.preview == "…" else { return }
        let revision = revision
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let preview: String
            if item.url.pathExtension.lowercased() == "pdf" {
                preview = String((PDFDocument(url: item.url)?.page(at: 0)?.string ?? "PDF").prefix(200))
            } else if let handle = try? FileHandle(forReadingFrom: item.url) {
                defer { try? handle.close() }
                preview = String(String(decoding: (try? handle.read(upToCount: 4096)) ?? Data(), as: UTF8.self).prefix(200))
            } else { preview = "" }
            DispatchQueue.main.async {
                guard let self, self.revision == revision, let index = self.results.firstIndex(where: { $0.url == item.url }) else { return }
                self.results[index] = LibrarySearchResult(url: item.url, path: item.path, preview: preview)
            }
        }
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selected = min(results.count - 1, max(0, selected + delta))
    }
    func open(inReference: Bool) {
        guard !searching, results.indices.contains(selected) else { return }
        choose?(results[selected].url, inReference)
    }
}

final class LibrarySearchPanel: NSPanel {
    var model: LibrarySearchModel?
    var dismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    func routeKey(_ event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown else { return event }
        if let editor = firstResponder as? NSTextView, editor.hasMarkedText() { return event }
        switch event.keyCode {
        case 125: model?.move(1)
        case 126: model?.move(-1)
        case 36, 76: model?.open(inReference: event.modifierFlags.contains(.option))
        case 53: dismiss?()
        default: return event
        }
        return nil
    }
}

@MainActor
final class LibrarySearchController: NSWindowController, NSWindowDelegate {
    private weak var ownerWindow: NSWindow?
    private weak var previousResponder: NSResponder?
    init(root: URL, owner: NSWindow, linking: Bool = false, open: @escaping (URL, Bool) -> Void) {
        let panel = LibrarySearchPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 510), styleMask: [.borderless], backing: .buffered, defer: false)
        super.init(window: panel)
        self.ownerWindow = owner; previousResponder = owner.firstResponder
        let model = LibrarySearchModel(root: root, linking: linking)
        panel.model = model
        model.choose = { [weak self] url, reference in self?.dismiss(); open(url, reference) }
        panel.dismiss = { [weak self] in self?.dismiss() }
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.level = .floating
        panel.hidesOnDeactivate = true; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: LibrarySearchView(model: model))
        let screen = owner.screen?.visibleFrame ?? owner.frame
        panel.setFrameOrigin(NSPoint(x: max(screen.minX + 16, min(owner.frame.midX - 340, screen.maxX - 696)), y: min(screen.maxY - 32, owner.frame.maxY - 90) - 510))
        owner.addChildWindow(panel, ordered: .above)
        let finalFrame = panel.frame
        panel.alphaValue = 0
        panel.setFrame(finalFrame.offsetBy(dx: 0, dy: -12), display: false)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }
        model.search()
    }
    required init?(coder: NSCoder) { fatalError() }
    func dismiss(restoreFocus: Bool = true) {
        guard let window, window.isVisible else { return }
        ownerWindow?.removeChildWindow(window); window.orderOut(nil)
        guard restoreFocus else { return }
        ownerWindow?.makeKeyAndOrderFront(nil)
        if let previousResponder { ownerWindow?.makeFirstResponder(previousResponder) }
    }
    func windowDidResignKey(_ notification: Notification) { dismiss(restoreFocus: false) }
}

private struct LibrarySearchView: View {
    @ObservedObject var model: LibrarySearchModel
    @FocusState private var isFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "magnifyingglass").font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
                TextField(model.linking ? L10n.t("链接已有笔记", "Link an existing note") : L10n.t("搜索笔记", "Search notes"), text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 28, weight: .regular)).focused($isFocused)
                if model.searching { ProgressView().controlSize(.small) }
            }.padding(.horizontal, 24).frame(height: 78)
            Divider().opacity(0.4)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.results) { result in
                            let index = model.results.firstIndex(where: { $0.id == result.id }) ?? 0
                            Button { model.selected = index; model.open(inReference: false) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 10) {
                                        Image(systemName: result.url.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "doc.text")
                                        Text(result.title).font(.system(size: 15, weight: .medium))
                                        Spacer()
                                    }
                                    if model.selected == index {
                                        Text(result.path).font(.system(size: 10)).foregroundStyle(.secondary)
                                        Text(result.preview.isEmpty ? L10n.t("空白笔记", "Empty note") : result.preview)
                                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(model.selected == index ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 12))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).id(result.id)
                        }
                        if model.results.isEmpty && !model.searching {
                            Text(L10n.t("未找到文件", "No files found")).foregroundStyle(.secondary).padding(28)
                        }
                    }.padding(10)
                }.onChange(of: model.selected) { _, index in
                    guard model.results.indices.contains(index) else { return }
                    withAnimation(.easeOut(duration: 0.13)) { proxy.scrollTo(model.results[index].id, anchor: .center) }
                }
            }
            HStack {
                Text(L10n.t("↑↓ 选择", "↑↓ Select")); Spacer()
                Text(model.linking ? L10n.t("↩ 插入链接     Esc 取消", "↩ Insert link     Esc Cancel") : L10n.t("↩ 打开     ⌥↩ 在参考窗格打开", "↩ Open     ⌥↩ Open in side pane"))
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .padding(1)
        .animation(.easeOut(duration: 0.13), value: model.selected)
        .onAppear { isFocused = true }
    }
}

/// Match names directly; do not derive the searchable name by slicing a filesystem prefix.
enum LibrarySearchMatching {
    static func normalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    static func relativePath(_ url: URL, root: URL) -> String {
        let file = url.standardizedFileURL.pathComponents
        let base = root.standardizedFileURL.pathComponents
        return Array(file.prefix(base.count)) == base ? file.dropFirst(base.count).joined(separator: "/") : url.lastPathComponent
    }
    static func files(root: URL, query: String, notesOnly: Bool = false) -> [URL] {
        let query = normalized(query)
        let tokens = query.split(separator: " ").map(String.init)
        return NoteLinks.files(in: root).filter { url in
            guard !notesOnly || url.pathExtension.lowercased() != "pdf" else { return false }
            let name = normalized(url.lastPathComponent)
            let path = normalized(relativePath(url, root: root))
            return tokens.allSatisfy { name.contains($0) || path.contains($0) }
        }.sorted { lhs, rhs in
            func rank(_ url: URL) -> Int {
                let name = normalized(url.deletingPathExtension().lastPathComponent)
                return name == query ? 0 : name.hasPrefix(query) ? 1 : 2
            }
            return rank(lhs) != rank(rhs) ? rank(lhs) < rank(rhs) : lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }
}
