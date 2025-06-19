//
//  iTermBrowserURLTextView.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

@available(macOS 11.0, *)
class iTermBrowserURLTextView: PlaceholderTextView {
    var willBecomeFirstResponder: (() -> ())?
    var willResignFirstResponder: (() -> ())?
    var shouldSelectAllOnMouseDown = true

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        guard result && window?.firstResponder == self else {
            return result
        }
        willBecomeFirstResponder?()
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        shouldSelectAllOnMouseDown = true
        willResignFirstResponder?()

        DispatchQueue.main.async {
            var range = self.selectedRange()
            range.location = range.upperBound
            range.length = 0
            self.setSelectedRange(range)
            self.discardCursorRects()
        }

        return result
    }

    override func mouseDown(with event: NSEvent) {
        let select = shouldSelectAllOnMouseDown
        shouldSelectAllOnMouseDown = false

        super.mouseDown(with: event)

        if select {
            self.selectAll(nil)
        }
    }
/*
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        // only draw the caret when we're actually first responder
        if window?.firstResponder == self {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
        }
    }
 */
}
