//
//  PlaygroundTextView.swift
//  iTerm2
//
//  Created by George Nachman on 5/24/25.
//

@objc(iTermPlaygroundTextViewDelegate)
protocol PlaygroundTextViewDelegate: AnyObject {
    func playgroundClickCoordinateDidChange(_ sender: PlaygroundTextView, coordinate: VT100GridCoord)
}

@objc(iTermPlaygroundTextView)
class PlaygroundTextView: PlaceholderTextView {
    @objc weak var playgroundDelegate: PlaygroundTextViewDelegate?
    @objc var lastCoord = VT100GridCoord(x: -1, y: -1)

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)

        let pointInView = convert(event.locationInWindow, from: nil)
        guard let layoutManager,
              let textContainer,
              let textStorage else {
            return
        }

        let glyphIndex = layoutManager.glyphIndex(for: pointInView, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        if charIndex >= textStorage.length {
            return
        }

        let text = textStorage.string as NSString
        var row = 0
        var startOfRow = 0

        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length),
                                 options: [.byLines, .substringNotRequired]) { _, range, enclosingRange, stop in
            if NSLocationInRange(charIndex, enclosingRange) {
                stop.pointee = true
            } else {
                row += 1
                startOfRow = NSMaxRange(enclosingRange)
            }
        }

        let column = charIndex - startOfRow

        let delta = self.deltaString(row: row)
        let x = Int32(delta.cellIndexForUTF16Index(column))

        lastCoord = VT100GridCoordMake(x, Int32(row))
        playgroundDelegate?.playgroundClickCoordinateDidChange(self, coordinate: lastCoord)
    }

    private func row(_ row: Int) -> String {
        return textStorage?.string.components(separatedBy: "\n")[row] ?? ""
    }

    private func deltaString(row: Int) -> DeltaString {
        let line = self.row(row)
        let string = iTermLegacyStyleString(line.asScreenCharArray())
        let delta = string.deltaString(range: NSRange(location: 0, length: line.utf16.count))
        return delta
    }

    @objc
    func highlightGridRange(_ range: VT100GridCoordRange) {
        let startDelta = deltaString(row: Int(range.start.y))
        let endDelta = deltaString(row: Int(range.end.y))
        let s = (textStorage?.string ?? "")
        let lower = s.utf16OffsetOfLine(Int(range.start.y))! + startDelta.cellIndexForUTF16Index(Int(range.start.x))
        let upper = s.utf16OffsetOfLine(Int(range.end.y))! + endDelta.cellIndexForUTF16Index(Int(range.end.x))
        highlightRange(NSRange(lower..<upper))
    }

    func highlightRange(_ range: NSRange) {
        removeHighlighting()
        guard range.location != NSNotFound,
              range.length > 0,
              let textStorage = self.textStorage,
              NSMaxRange(range) <= textStorage.length else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .backgroundColor: NSColor.yellow,
            .foregroundColor: NSColor.black
        ]

        textStorage.beginEditing()
        textStorage.addAttributes(attributes, range: range)
        textStorage.endEditing()
    }

    func removeHighlighting() {
        guard let textStorage = textStorage else {
            return
        }

        let attributes = [NSAttributedString.Key.foregroundColor: NSColor.textColor]
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        textStorage.removeAttribute(.backgroundColor, range: fullRange)
        textStorage.removeAttribute(.foregroundColor, range: fullRange)
        textStorage.addAttributes(attributes, range: fullRange)
        textStorage.endEditing()
    }
}
