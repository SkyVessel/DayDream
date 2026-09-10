import SwiftUI

/// One application window, with independently routed editor panes.
@MainActor
struct WorkspaceHost: View {
    var registerCoordinator: ((WorkspaceCoordinator, Bool) -> Void)?
    @StateObject private var store = WorkspaceStore(repositoryDefaults: .standard)
    @State private var search: LibrarySearchController?
    @State private var ultraFocus = false
    @State private var reference: URL?
    @State private var referenceStore: WorkspaceStore?
    @State private var ratio: CGFloat = 0.5
    @State private var left: WorkspaceCoordinator?
    @State private var right: WorkspaceCoordinator?

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                WorkspaceView(store: store, isEmbedded: reference != nil,
                              sharedUltraFocus: ultraFocus, onUltraFocusChanged: { ultraFocus = $0 },
                              onOpenReference: openReference, focusPane: focus,
                              registerCoordinator: { left = $0; $0.center.searchFiles = showSearch; registerCoordinator?($0, false) })
                    .frame(width: reference == nil ? geometry.size.width : min(geometry.size.width - 332, max(360, geometry.size.width * ratio - 6)))
                if let reference, let referenceStore {
                    PaneDivider(ratio: $ratio, totalWidth: geometry.size.width)
                    WorkspaceView(store: referenceStore, initialURL: reference,
                                  isEmbedded: true, showsChrome: false, sharedUltraFocus: ultraFocus,
                                  onUltraFocusChanged: { ultraFocus = $0 }, onOpenReference: openReference,
                                  onClosePane: { self.reference = nil; self.referenceStore = nil; right = nil; focus(false) },
                                  focusPane: focus, registerCoordinator: { right = $0; registerCoordinator?($0, true); $0.center.toggleSidebar = { left?.center.toggleSidebar() }; $0.center.searchFiles = showSearch })
                        .id(reference)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: reference == nil ? 560 : 760, minHeight: 420)
    }

    private func showSearch() {
        guard let window = left?.center.mainWindow, left?.flushDocument() != false, right?.flushDocument() != false else { return }
        search?.dismiss()
        search = LibrarySearchController(root: store.rootURL, owner: window) { url, reference in
            if reference { openReference(url) }
            else { left?.openDocument(url) }
        }
    }

    private func openReference(_ url: URL) {
        guard right?.flushDocument() != false else { return }
        if let right {
            right.openDocument(url)
            return
        }
        if referenceStore == nil { referenceStore = WorkspaceStore(rootURL: store.rootURL) }
        reference = url
    }

    private func focus(_ isRight: Bool) {
        guard let coordinator = isRight ? right : left else { return }
        PaneShortcutRouting.activate(coordinator.center)
        coordinator.center.isSidebarFocused = false
        if let editor = coordinator.textView { PaneFocusAnimation.focus(editor) }
        else { coordinator.center.mainWindow?.makeFirstResponder(coordinator.pdfView) }
    }
}

struct PaneDivider: View {
    @Binding var ratio: CGFloat
    let totalWidth: CGFloat
    @State private var startingRatio: CGFloat?

    var body: some View {
        RoundedRectangle(cornerRadius: 1.25)
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 2.5)
            .padding(.vertical, 40)
            .frame(width: 12)
            .contentShape(Rectangle())
            .onHover { if $0 { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture().onChanged { value in
                if startingRatio == nil { startingRatio = ratio }
                let minimum = min(0.45, 320 / max(totalWidth, 1))
                ratio = min(1 - minimum, max(minimum, (startingRatio ?? ratio) + value.translation.width / max(totalWidth, 1)))
            }.onEnded { _ in startingRatio = nil })
            .accessibilityLabel(L10n.t("调整窗格宽度", "Resize panes"))
    }
}
