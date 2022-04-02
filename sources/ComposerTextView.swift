//
//  ComposerTextView.swift
//  iTerm2
//
//  Created by George Nachman on 4/1/22.
//

import Foundation

@objc(iTermComposerTextViewDelegate)
protocol ComposerTextViewDelegate: AnyObject {
    @objc(composerTextViewDidFinishWithCancel:) func composerTextViewDidFinish(cancel: Bool)
    @objc(composerTextViewSendToAdvancedPaste:) func composerTextViewSendToAdvancedPaste(content: String)

    @objc(composerTextViewDidResignFirstResponder) optional func composerTextViewDidResignFirstResponder()
}

@objc(iTermComposerTextView)
class ComposerTextView: MultiCursorTextView {
    @IBOutlet weak var composerDelegate: ComposerTextViewDelegate?
    @objc private(set) var isSettingSuggestion = false
    private var _suggestion: String?
    @objc var suggestion: String? {
        get {
            return _suggestion
        }

        set {
            precondition(!isSettingSuggestion)
            isSettingSuggestion = true
            reallySetSuggestion(newValue)
            isSettingSuggestion = false
        }
    }
    private var suggestionRange = NSRange(location: 0, length: 0)

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        smartInsertDeleteEnabled = false
    }

    @objc var hasSuggestion: Bool {
        return suggestion != nil
    }

    @objc func acceptSuggestion() {
        textStorage?.setAttributes(typingAttributes, range: suggestionRange)
        setSelectedRange(NSRange(location: suggestionRange.upperBound, length: 0))
        _suggestion = nil
        suggestionRange = NSRange(location: NSNotFound, length: 0)
    }

    override func viewDidMoveToWindow() {
        if window == nil {
            undoManager?.removeAllActions(withTarget: textStorage!)
        }
    }

    override func it_preferredFirstResponder() -> Bool {
        return true
    }

    override func keyDown(with event: NSEvent) {
        let pressedEsc = event.characters == "\u{1b}"
        let pressedShiftEnter = event.characters == "\r" && event.it_modifierFlags.contains(.shift)
        if pressedShiftEnter || pressedEsc {
            suggestion = nil
            composerDelegate?.composerTextViewDidFinish(cancel: pressedEsc)
            return
        }
        super.keyDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        composerDelegate?.composerTextViewDidResignFirstResponder?()
        return super.resignFirstResponder()
    }

    private func attributedString(for suggestion: String) -> NSAttributedString {
        var attributes = self.typingAttributes
        attributes[.foregroundColor] = NSColor(white: 0.5, alpha: 1.0)
        return NSAttributedString(string: suggestion, attributes: attributes)
    }

    private func attributedString(from suggestion: String) -> NSAttributedString {
        return NSAttributedString(string: suggestion, attributes: typingAttributes)
    }

    private func reallySetSuggestion(_ suggestion: String?) {
        if let suggestion = suggestion {
            if hasSuggestion {
                // Replace existing suggestion with a different one.
                textStorage?.replaceCharacters(in: suggestionRange,
                                               with: attributedString(for: suggestion))
                _suggestion = suggestion
                suggestionRange = NSRange(location: suggestionRange.location,
                                          length: (suggestion as NSString).length);
                setSelectedRange(NSRange(location: suggestionRange.location, length: 0))
                return;
            }

            // Didn't have suggestion before but will have one now
            let location = selectedRange().upperBound
            textStorage!.replaceCharacters(in: NSRange(location: location, length: 0),
                                           with: attributedString(for: suggestion))
            _suggestion = suggestion
            suggestionRange = NSRange(location: location, length: (suggestion as NSString).length)
            setSelectedRange(NSRange(location: suggestionRange.location, length: 0))
            return
        }

        if !hasSuggestion {
            return;
        }

        // Remove existing suggestion:
        // 1. Find the ranges of suggestion-looking text by examining the color.
        let temp = self.attributedString()
        var rangesToRemove = [NSRange]()
        temp.enumerateAttribute(.foregroundColor,
                                in: NSRange(location: 0, length: temp.length),
                                options: [.reverse]) { color, range, _ in
            if color as? NSColor != NSColor.textColor {
                rangesToRemove.append(range)
            }
        }

        // 2. Delete those ranges, adjusting the cursor location as needed to keep it in the same place.
        var selectedRange = self.selectedRange()
        for range in rangesToRemove {
            selectedRange = selectedRange.minus(range)
            textStorage?.deleteCharacters(in: range)
        }

        // 3. Position the cursor and clean up internal state.
        self.selectedRange = selectedRange
        _suggestion = nil
        suggestionRange = NSRange(location: NSNotFound, length: 0)
    }
}

extension NSRange {
    // Return lhs - rhs. We are deleting text in rhs and need to return a new value that refers to the
    // same characters as lhs does before the deletion.
    func minus(_ rhs: NSRange) -> NSRange {
        if rhs.length == 0 {
            return self
        }
        if rhs.location >= upperBound {
            // All of lhs is before rhs, so do nothing.
            return self
        }
        if location >= rhs.upperBound {
            // All of lhs is after rhs, so shift it back by rhs.
            return NSRange(location: location - rhs.length, length: length)
        }
        if length == 0 {
            // We know that lhs.location > rhs.location, lhs.location < max(rhs).
            // xxxxxxxxxxx
            //  |--rhs--|
            //   ???????   lhs is somewhere in here and of length 0.
            return NSRange(location: rhs.location, length: 0)
        }
        let inter = intersection(rhs)!
        precondition(inter.length > 0)
        if self == inter {
            // Remove all of lhs.
            return NSRange(location: rhs.location, length: 0)
        }
        if location == inter.location {
            // Remove prefix of lhs but not the whole thing.
            return NSRange(location: location, length: length - inter.length);
        }
        // Remove starting in middle of lhs.
        return NSRange(location: location, length: length - inter.length);
    }
}
