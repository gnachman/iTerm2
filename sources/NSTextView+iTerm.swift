//
//  NSTextView+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/17/21.
//

import Foundation

extension NSTextView {
    @objc func it_scrollCursorToVisible() {
        guard let location = selectedRanges.first?.rangeValue.location else {
            return
        }
        scrollRangeToVisible(NSRange(location: location, length: 0))
    }

    @objc
    var cursorFrameInScreenCoordinates: CGRect {
        guard let textContainer, let layoutManager else {
            DLog("No text container or layout manager found.")
            return .zero
        }

        let insertionPointIndex = selectedRange.location
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: insertionPointIndex, length: 0),
            actualCharacterRange: nil)
        let insertionPointRect = layoutManager.boundingRect(forGlyphRange: glyphRange,
                                                            in: textContainer)
        let screenRect = self.window?.convertToScreen(insertionPointRect) ?? .zero

        return screenRect
    }
}
