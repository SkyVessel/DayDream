import AppKit
import SwiftUI

@MainActor
struct WorkspaceView: View {
    @StateObject private var store: WorkspaceStore
    @State private var isSidebarVisible = true
    @State private var isFullScreen = false

    init() {
        _store = StateObject(wrappedValue: WorkspaceStore(repositoryDefaults: .standard))
    }

    init(store: WorkspaceStore) {
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if isSidebarVisible {
                    SidebarView(store: store, isFullScreen: isFullScreen)
                        .frame(width: 250)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                editorRegion
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            sidebarToggle
                .padding(.leading, sidebarToggleLeadingInset)
                .padding(.top, sidebarToggleTopInset)
                .offset(y: sidebarToggleVerticalOffset)
                .zIndex(10)
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Color(nsColor: DayDreamTheme.background(for: NSApp.effectiveAppearance)))
        .animation(.easeOut(duration: 0.16), value: isSidebarVisible)
        .animation(.easeOut(duration: 0.18), value: isFullScreen)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            flushSave()
        }
        .onDisappear {
            flushSave()
        }
    }

    @ViewBuilder
    private var editorRegion: some View {
        if let selectedURL = store.selectedURL,
           selectedURL.pathExtension.lowercased() == "md" {
            EditorView(
                markdown: store.currentMarkdown,
                documentURL: selectedURL,
                autofocus: false,
                onMarkdownChange: { store.updateCurrentMarkdown($0) }
            )
        } else {
            ZStack {
                Color(nsColor: DayDreamTheme.background(for: NSApp.effectiveAppearance))
                Text(store.nodes.isEmpty ? "Create your first note" : "Select a note")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary.opacity(0.58))
            }
        }
    }

    private var sidebarToggle: some View {
        Button {
            isSidebarVisible.toggle()
        } label: {
            DayDreamIcon(
                name: .sidebar,
                color: Color(nsColor: .secondaryLabelColor),
                strokeWidth: 1.65
            )
            .frame(width: 17, height: 17)
            .frame(width: 32, height: 32)
            .background(.ultraThinMaterial, in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isSidebarVisible ? "Hide sidebar" : "Show sidebar")
        .accessibilityLabel(isSidebarVisible ? "Hide sidebar" : "Show sidebar")
    }

    private var sidebarToggleLeadingInset: CGFloat {
        if isSidebarVisible { return 175 }
        return isFullScreen ? 8 : 76
    }

    private var sidebarToggleTopInset: CGFloat {
        if isSidebarVisible { return isFullScreen ? 28.5 : 8 }
        return isFullScreen ? 9 : 8
    }

    private var sidebarToggleVerticalOffset: CGFloat {
        isSidebarVisible || isFullScreen ? 0 : -40 // 收起时与红绿灯对齐；展开时保持原位
    }

    private func flushSave() {
        do {
            try store.flushPendingSave()
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}
