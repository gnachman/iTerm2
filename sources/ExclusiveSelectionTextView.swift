//
//  ExclusiveSelectionTextView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/22/22.
//

import Foundation

@objc class ExclusiveSelectionTextView: NSTextView {
    var didAcquireSelection: (() -> ())?
    private var removingSelection = false

    func removeSelection() {
        guard selectedRange().length > 0 else {
            return
        }
        removingSelection = true
        setSelectedRange(NSRange(location: selectedRange().location, length: 0))
        removingSelection = false
    }

    override func setSelectedRanges(_ ranges: [NSValue],
                                    affinity: NSSelectionAffinity,
                                    stillSelecting stillSelectingFlag: Bool) {
        if !removingSelection {
            didAcquireSelection?()
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
    }

    override var acceptsFirstResponder: Bool {
        return isEditable
    }

    override func becomeFirstResponder() -> Bool {
        NSLog("Become first responder \(self)")
        super.becomeFirstResponder()
        return isEditable
    }

    override func resignFirstResponder() -> Bool {
        NSLog("Resign first responder \(self)")
        return super.resignFirstResponder()
    }

    func temporarilyHighlight(_ ranges: [NSRange]) {
        for range in ranges {
            temporarilyHighlight(range)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if isEditable {
            // I'm sure this is the wrong fix but I can't figure out why it's necessary.
            // Setting the frame also sets the container size which breaks automatic resizing.
            textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                  height: CGFloat.greatestFiniteMagnitude)
        }
        NSLog("\(newSize)")
    }

    func removeTemporaryHighlights() {
        guard let textStorage = textStorage else {
            return
        }
        textStorage.editAttributes { update in
            textStorage.enumerateAttribute(.it2_temporarilyHighlighted,
                                           in: NSRange(location: 0, length: textStorage.string.utf16.count),
                                           using: { value, attributeRange, stop in
                var fixed = textStorage.attributes(at: attributeRange.location, effectiveRange: nil)
                fixed.removeValue(forKey: .it2_temporarilyHighlighted)
                if let backgroundColor = fixed[.it2_savedBackgroundColor] {
                    fixed[.backgroundColor] = backgroundColor
                    fixed.removeValue(forKey: .it2_savedBackgroundColor)
                } else {
                    fixed.removeValue(forKey: .backgroundColor)
                }
                if let foregroundColor = fixed[.it2_savedForegroundColor] {
                    fixed[.foregroundColor] = foregroundColor
                    fixed.removeValue(forKey: .it2_savedForegroundColor)
                } else {
                    fixed.removeValue(forKey: .backgroundColor)
                }
                update(attributeRange, fixed)
            })
        }
    }

    private func temporarilyHighlight(_ range: NSRange) {
        var counter = 1
        textStorage?.editAttributes { update in
            textStorage?.enumerateAttributes(in: range, using: { preexistingAttributes, subrange, stop in
                if preexistingAttributes[.it2_temporarilyHighlighted] != nil {
                    return
                }
                var fixed = preexistingAttributes
                fixed[.it2_temporarilyHighlighted] = counter
                counter += 1
                if let bgColor = preexistingAttributes[.backgroundColor] {
                    fixed[.it2_savedBackgroundColor] = bgColor
                }
                if let fgColor = preexistingAttributes[.foregroundColor] {
                    fixed[.it2_savedForegroundColor] = fgColor
                }
                fixed[.backgroundColor] = NSColor.yellow
                fixed[.foregroundColor] = NSColor.black

                update(subrange, fixed)
            })
        }
    }
}

extension NSAttributedString.Key {
    static let it2_temporarilyHighlighted: NSAttributedString.Key = .init("it2_temporarilyHighlighted")  // Int value
    static let it2_savedBackgroundColor: NSAttributedString.Key = .init("it2_savedBackgroundColor")  // NSColor
    static let it2_savedForegroundColor: NSAttributedString.Key = .init("it2_savedForegroundColor")  // NSColor
}
