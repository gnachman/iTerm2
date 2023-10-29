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
        removingSelection = true
        setSelectedRange(NSRange(location: 0, length: 0))
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
        return false
    }

    override func becomeFirstResponder() -> Bool {
        return false
    }

    func temporarilyHighlight(_ ranges: [NSRange]) {
        for range in ranges {
            temporarilyHighlight(range)
        }
    }

    func removeTemporaryHighlights() {
        guard let textStorage = textStorage else {
            return
        }
        textStorage.editAttributes { update in
            let wholeRange = NSRange(location: 0, length: textStorage.string.utf16.count)
            var ranges = [NSRange]()
            textStorage.enumerateAttribute(.it2_temporarilyHighlighted,
                                           in: wholeRange) { flag, range, stop in
                if flag != nil {
                    ranges.append(range)
                }
            }
            for wholeRange in ranges {
                textStorage.enumerateAttributes(in: wholeRange) { originalAttributes, attributeRange, stop in
                    var fixed = originalAttributes
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
                        fixed.removeValue(forKey: .foregroundColor)
                    }
                    update(attributeRange, fixed)
                }
            }
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
