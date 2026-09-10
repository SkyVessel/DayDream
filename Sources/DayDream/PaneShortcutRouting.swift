import AppKit
import SwiftUI

@MainActor
enum PaneShortcutRouting {
    private static let panes = NSHashTable<PaneRoutingView>.weakObjects()
    private static let active = NSMapTable<NSWindow, ShortcutCenter>.weakToWeakObjects()

    static func register(_ view: PaneRoutingView) {
        panes.add(view)
        guard let window = view.window else { return }
        view.center.mainWindow = window
        if active.object(forKey: window) == nil { activate(view.center) }
    }

    static func activate(_ center: ShortcutCenter) {
        guard let window = center.mainWindow else { return }
        active.setObject(center, forKey: window)
    }

    static func current(in window: NSWindow?) -> ShortcutCenter? {
        guard let window else { return nil }
        return active.object(forKey: window)
    }

    static func routeMouse(_ event: NSEvent) {
        guard let window = event.window else { return }
        for pane in panes.allObjects where pane.window === window {
            if pane.bounds.contains(pane.convert(event.locationInWindow, from: nil)) {
                activate(pane.center)
                if let document = pane.center.documentResponder, document.bounds.contains(document.convert(event.locationInWindow, from: nil)) { pane.center.isSidebarFocused = false }
            }
        }
    }
}

struct PaneShortcutBridge: NSViewRepresentable {
    let center: ShortcutCenter
    func makeNSView(context: Context) -> PaneRoutingView { PaneRoutingView(center: center) }
    func updateNSView(_ view: PaneRoutingView, context: Context) { PaneShortcutRouting.register(view) }
}

final class PaneRoutingView: NSView {
    let center: ShortcutCenter
    init(center: ShortcutCenter) { self.center = center; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); PaneShortcutRouting.register(self) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
enum PaneFocusAnimation {
    static func focus(_ target: DayDreamTextView) {
        guard let window = target.window else { return }
        let source = window.firstResponder as? DayDreamTextView
        let from = source.flatMap { editor in editor.currentCaretRect().map { editor.convert($0, to: window.contentView) } }
        window.makeFirstResponder(target)
        guard let root = window.contentView, let from, let caret = target.currentCaretRect() else { return }
        let to = target.convert(caret, to: root)
        let flight = NSView(frame: from)
        flight.wantsLayer = true
        flight.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        flight.layer?.cornerRadius = 1
        root.addSubview(flight)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            flight.animator().frame = to
            flight.animator().alphaValue = 0.3
        } completionHandler: { flight.removeFromSuperview() }
    }
}
