import AppKit

/// Presentation-only glyph motion. TextKit still owns shaping, selection and layout.
final class TypingLayoutManager: NSLayoutManager {
    private struct Reveal { var range: NSRange; let start: TimeInterval }
    private struct FallingCopy {
        let text: NSAttributedString
        let point: NSPoint
        let start: TimeInterval
        let velocity: CGFloat
        let strength: Double
        let lifetime: Double
    }
    private var falling: [FallingCopy] = []
    var fallingCopyCount: Int { falling.count }
    private var reveals: [Reveal] = []
    private var timer: Timer?

    func reveal(_ range: NSRange) {
        guard EditorSettings.shared.typingAnimationEnabled,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              range.length > 0 else { return }
        if EditorSettings.shared.typingAnimationStyle == "falling", let storage = textStorage,
           let container = textContainers.first, NSMaxRange(range) <= storage.length {
            ensureLayout(for: container)
            let value = storage.string as NSString
            value.enumerateSubstrings(in: range, options: .byComposedCharacterSequences) { _, characters, _, _ in
                let text = storage.attributedSubstring(from: characters)
                guard !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                let glyphs = self.glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
                let rect = self.boundingRect(forGlyphRange: glyphs, in: container)
                self.falling.append(FallingCopy(text: text, point: rect.origin,
                    start: ProcessInfo.processInfo.systemUptime, velocity: CGFloat.random(in: -85...85),
                    strength: EditorSettings.shared.fallingStrength, lifetime: EditorSettings.shared.fallingLifetime))
            }
            if falling.count > 120 { falling.removeFirst(falling.count - 120) }
        } else {
            reveals.append(Reveal(range: range, start: ProcessInfo.processInfo.systemUptime))
        }
        if timer == nil {
            let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.tick() }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        tick()
    }

    func clearReveals() {
        reveals.removeAll(); falling.removeAll()
        timer?.invalidate(); timer = nil
        textContainers.first?.textView?.needsDisplay = true
    }

    func prepareForEdit(_ range: NSRange, insertedLength: Int) {
        reveals = reveals.compactMap { item in
            guard NSIntersectionRange(range, item.range).length == 0 else { return nil }
            var item = item
            if item.range.location >= NSMaxRange(range) { item.range.location += insertedLength - range.length }
            return item
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        reveals.removeAll { now - $0.start >= 0.8 }
        falling.removeAll { now - $0.start >= $0.lifetime }
        if !EditorSettings.shared.typingAnimationEnabled || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            reveals.removeAll(); falling.removeAll()
        }
        textContainers.first?.textView?.needsDisplay = true
        if reveals.isEmpty && falling.isEmpty { timer?.invalidate(); timer = nil }
    }

    func drawFallingCopies(at origin: NSPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        for copy in falling {
            let state = FallingTextMotion.sample(age: now - copy.start, lifetime: copy.lifetime, strength: copy.strength, horizontalVelocity: copy.velocity)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setAlpha(state.opacity)
            copy.text.draw(at: NSPoint(x: origin.x + copy.point.x + state.offset.x, y: origin.y + copy.point.y + state.offset.y))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard !reveals.isEmpty, let storage = textStorage else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin); return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let active = reveals.compactMap { item -> (NSRange, Double)? in
            guard NSMaxRange(item.range) <= storage.length else { return nil }
            let glyphs = NSIntersectionRange(glyphRange(forCharacterRange: item.range, actualCharacterRange: nil), glyphsToShow)
            return glyphs.length > 0 ? (glyphs, min(1, (now - item.start) / 0.8)) : nil
        }.sorted { $0.0.location < $1.0.location }
        var cursor = glyphsToShow.location
        for (range, t) in active {
            if range.location > cursor {
                super.drawGlyphs(forGlyphRange: NSRange(location: cursor, length: range.location - cursor), at: origin)
            }
            NSGraphicsContext.saveGraphicsState()
            let ease = t == 0 ? 0 : pow(2, -10 * t) * sin((t - 0.075) * (2 * .pi) / 0.3) + 1
            NSGraphicsContext.current?.cgContext.setAlpha(min(1, t * 6))
            super.drawGlyphs(forGlyphRange: range, at: NSPoint(x: origin.x, y: origin.y + 26 * (1 - ease)))
            NSGraphicsContext.restoreGraphicsState()
            cursor = max(cursor, NSMaxRange(range))
        }
        if cursor < NSMaxRange(glyphsToShow) {
            super.drawGlyphs(forGlyphRange: NSRange(location: cursor, length: NSMaxRange(glyphsToShow) - cursor), at: origin)
        }
    }

    deinit { timer?.invalidate() }
}

struct FallingTextMotion {
    static func sample(age: Double, lifetime: Double, strength: Double, horizontalVelocity: CGFloat) -> (offset: NSPoint, opacity: CGFloat) {
        let time = max(0, age)
        let duration = max(0.1, lifetime)
        let progress = min(1, time / duration)
        return (NSPoint(x: horizontalVelocity * strength * time,
                        y: -115 * strength * time + 270 * time * time),
                max(0, min(0.85, (1 - progress) / 0.55)))
    }
}
