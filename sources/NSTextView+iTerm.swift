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
        let screenRect = window?.convertToScreen(convert(insertionPointRect, to: nil)) ?? .zero

        return screenRect
    }
}

extension NSTextView: iTermPopupWindowHosting {
    public func popupWindowHostingInsertionPointFrameInScreenCoordinates() -> NSRect {
        return cursorFrameInScreenCoordinates
    }

    public func words(beforeInsertionPoint count: Int) -> [String]! {
        guard let textStorage else {
            return []
        }
        let fullString = textStorage.string as NSString
        let text = fullString.substring(to: selectedRange().location)
        let words = text.lastWords(UInt(count)).reversed()
        if text.endsWithWhitespace {
            return words + [""]
        }
        return Array(words)
    }

    public func popupWindowHostingInsertText(_ string: String!) {
        insertText(string ?? "", replacementRange: selectedRange())
    }

    public func popupWindowHostSetPreview(_ string: String!) {
        let range = selectedRange()
        replaceCharacters(in: range, with: string)
        setSelectedRange(NSRange(from: range.location, to: range.location + string.utf16.count))
    }
}
