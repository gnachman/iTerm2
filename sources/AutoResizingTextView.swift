//
//  AutoResizingTextView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/1/23.
//

import Cocoa


@objc(iTermAutoResizingTextView)
class AutoResizingTextView: NSTextView {
    private let minimumFontSize: CGFloat = 8

    override var string: String {
        didSet {
            userFont = font
            adjustFontSizes()
        }
    }

    override var font: NSFont? {
        didSet {
            adjustFontSizes()
        }
    }

    override var textContainerInset: NSSize {
        didSet {
            adjustFontSizes()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        adjustFontSizes()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        adjustFontSizes()
    }

    private var userFont: NSFont?
    @objc var enableAutoResizing = false
    @objc private(set) var originalAttributedString: NSAttributedString?

    @objc
    func adjustFontSizes() {
        guard enableAutoResizing else {
            return
        }
        // Handle edge case of zero frame size
        guard frame.size.width > 0 && frame.size.height > 0 else {
            return
        }
        guard let attributedString = textStorage else {
            return
        }
        guard let font else {
            return
        }
        if userFont == nil {
            userFont = font
        }
        if originalAttributedString == nil {
            originalAttributedString = (attributedString.copy() as! NSAttributedString)
        }
        var maxFontSize = userFont!.pointSize
        let range = NSRange(location: 0, length: attributedString.length)
        // Find max font size that fits in the text view for each font run

        // Use binary search to find the maximum font size that fits in the text view
        var minFontSize: CGFloat = minimumFontSize
        while maxFontSize >= minFontSize {
            let midFontSize = (maxFontSize + minFontSize) / 2
            let newFont = NSFont(name: font.fontName, size: midFontSize)!
            let newAttributedString = originalAttributedString!.mutableCopy() as! NSMutableAttributedString
            newAttributedString.addAttribute(.font, value: newFont, range: range)
            let newSizeThatFits = sizeThatFits(newAttributedString, width: frame.width)
            if newSizeThatFits.height <= frame.size.height {
                minFontSize = midFontSize + 1
            } else {
                maxFontSize = midFontSize - 1
            }
            if maxFontSize < minFontSize {
                DLog("Font size \(font.pointSize) yields size \(newSizeThatFits)")
            }
        }

        // Apply the maximum font size that fits
        let newFont = NSFont(name: font.fontName, size: max(self.minimumFontSize, maxFontSize))!
        attributedString.setAttributedString(originalAttributedString!)
        attributedString.addAttribute(.font, value: newFont, range: range)

        // Set attributed string and update layout
        attributedString.setAttributedString(attributedString)

        truncateTextIfNeeded()
    }

    func sizeThatFits(_ attributedString: NSAttributedString,
                      width: CGFloat) -> CGSize {
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(containerSize: CGSize(width: width, height: .greatestFiniteMagnitude))
        textContainer.size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage(attributedString: attributedString.mutableCopy() as! NSMutableAttributedString)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let size = layoutManager.usedRect(for: textContainer).size
        layoutManager.removeTextContainer(at: layoutManager.textContainers.firstIndex(of: textContainer)!)
        textStorage.removeLayoutManager(layoutManager)
        return size
    }

    private var defaultAttributes: [NSAttributedString.Key: Any] {
        guard let textStorage else {
            return typingAttributes
        }
        if textStorage.string.isEmpty {
            return typingAttributes
        }
        return textStorage.attributes(at: 0, effectiveRange: nil)
    }

    private func truncateTextIfNeeded() {
        guard let textStorage = self.textStorage,
              let layoutManager = self.layoutManager,
              let textContainer = self.textContainer else {
            return
        }

        guard sizeThatFits(textStorage, width: textContainer.size.width).height > bounds.height else {
            return
        }

        let truncationToken = "…"
        let maxWidth = bounds.width - sizeThatFits(NSAttributedString(string: truncationToken,
                                                                      attributes: defaultAttributes),
                                                   width: .greatestFiniteMagnitude).width
        let maxPoint = NSPoint(x: maxWidth,
                               y: bounds.height - textContainerInset.height)

        // Determine the range of glyphs that are visible.
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: bounds, in: textContainer)

        // Find the last full line that is visible using binary search.
        var lo = visibleGlyphRange.location
        var hi = NSMaxRange(visibleGlyphRange)
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            let midRect = layoutManager.lineFragmentRect(forGlyphAt: mid, effectiveRange: nil, withoutAdditionalLayout: true)
            if midRect.origin.y + midRect.size.height > maxPoint.y {
                hi = mid - 1
            } else {
                lo = mid
            }
        }

        // Determine the range of characters to include in the truncated text.
        let truncatedGlyphRange = NSMakeRange(0, lo)
        let truncatedCharacterRange = layoutManager.characterRange(forGlyphRange: truncatedGlyphRange, actualGlyphRange: nil)

        // Find the last word in the truncated character range.
        var lastWordRange = truncatedCharacterRange
        if let lastSpaceRange = textStorage.string.range(of: "\\s*\\S+\\s*$",
                                                         options: .regularExpression,
                                                         range: Range(truncatedCharacterRange, in: textStorage.string),
                                                         locale: nil) {
            lastWordRange = NSRange(lastSpaceRange, in: textStorage.string)
        }

        // Replace the last word with the truncation token.
        let truncatedText = NSMutableAttributedString(attributedString: textStorage.attributedSubstring(from: truncatedCharacterRange))
        if lastWordRange.length > 0 {
            let rangeToDelete = NSRange(lastWordRange.upperBound..<textStorage.length)
            truncatedText.replaceCharacters(in: lastWordRange, with: truncationToken)
            textStorage.replaceCharacters(in: rangeToDelete, with: "")
        } else {
            truncatedText.append(NSAttributedString(string: truncationToken, attributes: defaultAttributes))
        }
        textStorage.setAttributedString(truncatedText)
    }
}

