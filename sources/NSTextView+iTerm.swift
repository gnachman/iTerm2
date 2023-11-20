//
//  NSTextView+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/17/21.
//

import Foundation

extension NSTextContainer {
    func withFakeSize<T>(_ fakeSize: NSSize, closure: () throws -> T) rethrows -> T {
        let savedContainerSize = containerSize
        let saved = size
        size = fakeSize
        containerSize = fakeSize
        defer {
            size = saved
            containerSize = savedContainerSize
        }
        return try closure()
    }
}

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

    @objc(desiredHeightForWidth:)
    func desiredHeight(forWidth width: CGFloat) -> CGFloat {
        let fakeWidth: CGFloat
        if enclosingScrollView != nil {
            fakeWidth = .infinity
        } else {
            // Set the width so the height calculation will be based on it. The height here is arbitrary.
            fakeWidth = width
        }
        guard let textContainer = self.textContainer,
              let layoutManager = self.layoutManager else {
            return frame.size.height
        }
        return textContainer.withFakeSize(NSSize(width: fakeWidth, height: .infinity)) { () -> CGFloat in
            // forces layout
            // This is obviously indefensible but I just can't get it to work with a single call to glyphRange.
            // 😘 AppKit
            _ = layoutManager.glyphRange(for: textContainer)
            DLog("After first call to glyphRange rect would be \(layoutManager.usedRect(for: textContainer))")
            _ = layoutManager.glyphRange(for: textContainer)
            let rect = layoutManager.usedRect(for: textContainer)
            DLog("After second call to glyphRange rect is \(rect)")
            return rect.height
        }
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
