import AppKit
import QuartzCore

extension DayDreamTextView {
    /// Finish one interaction after its TextKit mutations have completed. Scheduling in
    /// common modes also works during mouse tracking; waking the run loop means a
    /// swallowed shortcut or the final drag event never waits for another input event.
    func requestDisplayCommit() {
        needsDisplay = true
        guard !isDisplayCommitScheduled else { return }
        isDisplayCommitScheduled = true
        let loop = CFRunLoopGetMain()
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            guard let self else { return }
            defer { self.isDisplayCommitScheduled = false }
            guard let window = self.window, window.isVisible else { return }
            window.contentView?.layoutSubtreeIfNeeded()
            if let container = self.textContainer {
                let visible = self.visibleRect.offsetBy(dx: -self.textContainerOrigin.x, dy: -self.textContainerOrigin.y)
                self.layoutManager?.ensureLayout(forBoundingRect: visible, in: container)
            }
            self.needsDisplay = true
            window.contentView?.displayIfNeeded()
            window.displayIfNeeded()
            CATransaction.flush()
        }
        CFRunLoopWakeUp(loop)
    }
}
