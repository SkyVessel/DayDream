import AppKit
import SwiftUI

/// Finder-opened files keep their original location and independent save state.
@MainActor
final class ExternalDocumentWindow: NSWindowController, NSWindowDelegate {
    let fileDocument = DocumentController()
    private let center = ShortcutCenter()
    private weak var editor: DayDreamTextView?
    var onClose: (() -> Void)?

    init?(url: URL) {
        guard ["md", "markdown", "pdf"].contains(url.pathExtension.lowercased()) else { return nil }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 880),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        fileDocument.open(url)
        guard fileDocument.currentURL != nil else { return nil }
        window.title = url.lastPathComponent
        window.representedURL = url
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        center.mainWindow = window
        center.closeNote = { [weak self] in self?.window?.performClose(nil) }
        center.toggleBold = { [weak self] in self?.editor?.toggleBold() }
        center.toggleItalic = { [weak self] in self?.editor?.toggleItalic() }
        center.toggleHighlight = { [weak self] in self?.editor?.toggleHighlight() }
        center.toggleTextColor = { [weak self] in self?.editor?.toggleTextColor() }
        center.toggleInlineCode = { [weak self] in self?.editor?.toggleInlineCode() }
        center.writingCommand = { [weak self] command in
            guard let self else { return }
            switch command {
            case .retype: self.editor?.toggleRetype()
            case .enterUltraFocus: self.editor?.setUltraFocus(true)
            case .exitUltraFocus: self.editor?.setUltraFocus(false)
            default: break
            }
        }
        let content = NSHostingView(rootView: ExternalDocumentContent(document: fileDocument, center: center, register: { [weak self] in self?.editor = $0; self?.center.documentResponder = $0 }))
        content.frame = NSRect(origin: .zero, size: window.contentLayoutRect.size)
        content.autoresizingMask = [.width, .height]
        window.contentView = content
        window.contentMinSize = NSSize(width: 480, height: 360)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func save() -> Bool {
        editor?.flushPendingMarkdownChange()
        return fileDocument.flush()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if save() { return true }
        let alert = NSAlert()
        alert.messageText = L10n.t("文件尚未保存", "The file has not been saved")
        alert.informativeText = L10n.t("请先处理保存冲突或检查文件是否可写，再关闭窗口。", "Resolve any save conflict or check that the file is writable before closing.")
        alert.runModal()
        return false
    }

    func windowWillClose(_ notification: Notification) { onClose?() }
}

private struct ExternalDocumentContent: View {
    @ObservedObject var document: DocumentController
    let center: ShortcutCenter
    var register: (DayDreamTextView) -> Void

    var body: some View {
        Group {
            if let url = document.currentURL {
                if document.isPDF { PDFDocumentView(url: url, register: { center.documentResponder = $0 }) }
                else {
                    EditorView(markdown: document.markdown, documentURL: url,
                               reloadRevision: document.reloadRevision,
                               onMarkdownChange: { document.updateMarkdown($0) },
                               registerTextView: register)
                }
            }
        }
        .background(PaneShortcutBridge(center: center))
        .frame(minWidth: 480, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
        .alert(L10n.t("文件已被其他应用修改", "File changed in another app"), isPresented: Binding(
            get: { document.externalEditConflict != nil }, set: { _ in }
        )) {
            Button(L10n.t("读取磁盘版本", "Reload from Disk")) { document.reloadFromDisk() }
            Button(L10n.t("保留我的修改", "Keep My Changes")) { document.overwriteExternalChanges() }
        } message: {
            Text(L10n.t("请选择要保留的版本。", "Choose which version to keep."))
        }
    }
}
