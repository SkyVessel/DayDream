import AppKit

extension DayDreamTextView {
    func registerStyleUndo() {
        guard let storage = textStorage else { return }
        let previous = NSAttributedString(attributedString: storage)
        let selection = selectedRange()
        let kind = trailingBlockKind
        let indentation = trailingListIndentation
        let start = trailingOrderedStart
        let writingState = [activeWritingStyle, activeWritingColor, activeWritingHighlight]
        undoManager?.registerUndo(withTarget: self) { editor in
            editor.restoreStyleSnapshot(previous, selection: selection, kind: kind, indentation: indentation, start: start, writingState: writingState)
        }
        undoManager?.setActionName(L10n.t("修改样式", "Change Style"))
    }

    private func restoreStyleSnapshot(_ snapshot: NSAttributedString, selection: NSRange, kind: MarkdownBlockKind, indentation: String, start: Int, writingState: [WritingTool?]) {
        registerStyleUndo()
        activeWritingStyle = writingState[0]; activeWritingColor = writingState[1]; activeWritingHighlight = writingState[2]
        textStorage?.setAttributedString(snapshot)
        trailingBlockKind = kind; trailingListIndentation = indentation; trailingOrderedStart = start
        setSelectedRange(selection)
        didChangeText()
        requestDisplayCommit()
    }

    func insertDivider() {
        guard retypeSession == nil, let storage = textStorage else { return }
        registerStyleUndo()
        let location = NSMaxRange(selectedRange())
        let prefix = location > 0 && (string as NSString).character(at: location - 1) != 10 ? "\n" : ""
        var attributes = DayDreamTheme.textAttributes(for: effectiveAppearance)
        attributes[.dayDreamBlockKind] = MarkdownBlockKind.body
        storage.insert(NSAttributedString(string: prefix + "\n", attributes: attributes), at: location)
        applyBlockKind(.divider, at: location + prefix.utf16.count)
        let caret = location + prefix.utf16.count + 1
        setSelectedRange(NSRange(location: caret, length: 0))
        applyBlockKind(.body, at: caret)
        didChangeText()
    }

    func writingToolIsAppliedToSelection(_ tool: WritingTool) -> Bool {
        guard let storage = textStorage, selectedRange().length > 0 else { return false }
        let selection = selectedRange()
        let key: NSAttributedString.Key
        let expected: NSObject
        if let kind = tool.blockKind {
            let text = string as NSString
            let range = text.paragraphRange(for: selection)
            var location = range.location
            while location < NSMaxRange(range) {
                if currentBlockKind(at: location) != kind { return false }
                let next = NSMaxRange(text.paragraphRange(for: NSRange(location: location, length: 0)))
                if next <= location { break }
                location = next
            }
            return true
        }
        if tool.isColor { key = .dayDreamTextColor; expected = tool.rawValue as NSString }
        else if let color = tool.highlightColor { key = .dayDreamHighlight; expected = color as NSString }
        else if let font = tool.fontName { key = .dayDreamFontFamily; expected = font as NSString }
        else if tool == .bold { key = .dayDreamBold; expected = NSNumber(value: true) }
        else if tool == .italic { key = .dayDreamItalic; expected = NSNumber(value: true) }
        else if tool == .inlineCode { key = .dayDreamInlineCode; expected = NSNumber(value: true) }
        else { return false }
        var matches = true
        storage.enumerateAttribute(key, in: selection) { value, _, stop in
            if !((value as? NSObject)?.isEqual(expected) ?? false) {
                matches = false; stop.pointee = true
            }
        }
        return matches
    }

    func applyWritingToolToSelection(_ tool: WritingTool) {
        guard retypeSession == nil, let storage = textStorage else { return }
        if tool.blockKind == .divider { insertDivider(); return }
        let selection = selectedRange()
        guard selection.length > 0 || tool.blockKind != nil else { return }
        let remove = writingToolIsAppliedToSelection(tool)
        registerStyleUndo()
        if let kind = tool.blockKind {
            let text = string as NSString
            let paragraphs = text.paragraphRange(for: selection)
            var location = paragraphs.location
            repeat {
                applyBlockKind(remove ? .body : kind, at: location)
                let next = NSMaxRange(text.paragraphRange(for: NSRange(location: location, length: 0)))
                if next <= location { break }
                location = next
            } while location < NSMaxRange(paragraphs)
        } else {
            if remove {
                let key: NSAttributedString.Key = tool.isColor ? .dayDreamTextColor : tool.highlightColor != nil ? .dayDreamHighlight : tool.fontName != nil ? .dayDreamFontFamily : tool == .bold ? .dayDreamBold : tool == .italic ? .dayDreamItalic : .dayDreamInlineCode
                storage.removeAttribute(key, range: selection)
            } else if tool.isColor { storage.addAttribute(.dayDreamTextColor, value: tool.rawValue, range: selection) }
            else if let color = tool.highlightColor { storage.addAttribute(.dayDreamHighlight, value: color, range: selection) }
            else {
                var keys: [NSAttributedString.Key] = [.dayDreamBold, .dayDreamItalic, .dayDreamInlineCode, .dayDreamFontFamily]
                if tool == .plain { keys += [.dayDreamTextColor, .dayDreamHighlight] }
                for key in keys { storage.removeAttribute(key, range: selection) }
                if tool == .bold { storage.addAttribute(.dayDreamBold, value: true, range: selection) }
                if tool == .italic { storage.addAttribute(.dayDreamItalic, value: true, range: selection) }
                if tool == .inlineCode { storage.addAttribute(.dayDreamInlineCode, value: true, range: selection) }
                if let font = tool.fontName { storage.addAttribute(.dayDreamFontFamily, value: font, range: selection) }
            }
            rebuildAttributes(in: selection)
        }
        setSelectedRange(selection)
        didChangeText()
        requestDisplayCommit()
    }
}
