//
//  iTermAccessibilitySelectionReplacement.swift
//  iTerm2SharedARC
//

import Foundation

@objc(iTermAccessibilitySelectionReplacementDecision)
enum iTermAccessibilitySelectionReplacementDecision: Int {
    // Nothing selected through accessibility. Insert at the cursor as usual.
    case insertNormally
    // Delete the selected text by backspacing, then insert.
    case replace
    // Text was selected through accessibility but can't be replaced. Don't insert anything.
    case drop
}

// Decides what to do when the text input system inserts text with no replacement range after an
// accessibility client selected text. Voice Control corrects a word this way: it selects the word
// and expects the insertion to replace it.
@objc(iTermAccessibilitySelectionReplacement)
class iTermAccessibilitySelectionReplacement: NSObject {
    @objc(decisionWithAccessibilityRange:hasAccessibilityRange:selection:hasSelection:cursor:softAlternateScreenMode:)
    static func decision(accessibilityRange: VT100GridAbsCoordRange,
                         hasAccessibilityRange: Bool,
                         selection: VT100GridAbsCoordRange,
                         hasSelection: Bool,
                         cursor: VT100GridAbsCoord,
                         softAlternateScreenMode: Bool) -> iTermAccessibilitySelectionReplacementDecision {
        guard hasAccessibilityRange,
              hasSelection,
              selection.start == accessibilityRange.start,
              selection.end == accessibilityRange.end else {
            // The selection has changed since accessibility set it, so it isn't a request to
            // replace text.
            return .insertNormally
        }
        // Text can be replaced only by backspacing over it, which works only when it ends at the
        // cursor and a full-screen app isn't interpreting the backspaces.
        if softAlternateScreenMode || selection.end != cursor {
            return .drop
        }
        return .replace
    }
}

// The text input system measures a replacement range in UTF-16 code units of the text it read, but
// the shell deletes one character per backspace.
@objc(iTermReplacedTextCounter)
class iTermReplacedTextCounter: NSObject {
    // Returns the number of characters spanned by the last `length` UTF-16 code units of `text`,
    // which is the text before the cursor.
    @objc(numberOfCharactersInLastUTF16Units:ofText:)
    static func numberOfCharacters(inLastUTF16Units length: Int, of text: String) -> Int {
        let nsText = text as NSString
        let clamped = min(max(length, 0), nsText.length)
        if clamped == 0 {
            return 0
        }
        // Widen the range if it splits a character, such as half of a surrogate pair.
        let range = nsText.rangeOfComposedCharacterSequences(for: NSRange(location: nsText.length - clamped,
                                                                          length: clamped))
        return (nsText.substring(with: range) as NSString).numberOfComposedCharacters()
    }
}
