//
//  ComposerTextView.swift
//  iTerm2
//
//  Created by George Nachman on 4/1/22.
//

import Foundation
import AppKit

@objc(iTermComposerTextViewDelegate)
protocol ComposerTextViewDelegate: AnyObject {
    @objc(composerTextViewDidFinishWithCancel:) func composerTextViewDidFinish(cancel: Bool)
    @objc(composerTextViewSend:) func composerTextViewSend(string: String)
    @objc(composerTextViewSendToAdvancedPaste:) func composerTextViewSendToAdvancedPaste(content: String)

    // Optional
    @objc(composerTextViewDidResignFirstResponder) optional func composerTextViewDidResignFirstResponder()
}

@objc(iTermComposerTextView)
class ComposerTextView: MultiCursorTextView {
    @IBOutlet weak var composerDelegate: ComposerTextViewDelegate?
    @objc private(set) var isSettingSuggestion = false
    private var _suggestion: String?
    private var linkRange: NSRange? = nil
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
        usesFindBar = true
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

    override func performFindPanelAction(_ sender: Any?) {
        if let tag = (sender as? NSMenuItem)?.tag, tag == NSFindPanelAction.selectAll.rawValue {
            window?.makeFirstResponder(self)
        }
        super.performFindPanelAction(sender)
    }

    override func keyDown(with event: NSEvent) {
        let pressedEsc = event.characters == "\u{1b}"
        if pressedEsc {
            suggestion = nil
            composerDelegate?.composerTextViewDidFinish(cancel: true)
            return
        }

        let enter = event.characters == "\r"
        if enter {
            let flags = event.it_modifierFlags
            let mask: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
            let justShift = flags.intersection(mask) == [.shift]
            if justShift {
                suggestion = nil
                composerDelegate?.composerTextViewDidFinish(cancel: false)
                return
            }
            let justShiftOption = flags.intersection(mask) == [.shift, .option]
            if justShiftOption {
                suggestion = nil
                for command in take() {
                    composerDelegate?.composerTextViewSend(string: command)
                }
                return
            }
        }
        super.keyDown(with: event)
    }

    private func take() -> [String] {
        return Array(multiCursorSelectedRanges.reversed().compactMap {
            take(range: $0)
        }.reversed())
    }

    // Extracts the command intersecting `range`, removes it from the textview, and returns it.
    // Returns nil if the range is invalid.
    // range: A glyph range.
    private func take(range: NSRange) -> String? {
        let string = textStorage!.string as NSString
        let stringToTake: String
        var rangeToTake: NSRange
        if range.length > 0 {
            stringToTake = string.substring(with: range)
            rangeToTake = range
        } else {
            let characterIndex = layoutManager!.characterRange(forGlyphRange: range,
                                                               actualGlyphRange: nil)
            guard let tuple = characterRangeOfCommand(
                atCharacterIndex: characterIndex.location) else {
                return nil
            }
            (rangeToTake, _) = tuple
            stringToTake = string.substring(with: rangeToTake)
        }
        safelyReplaceCharacters(in: rangeToTake, with: "")
        return stringToTake
    }

    override func resignFirstResponder() -> Bool {
        composerDelegate?.composerTextViewDidResignFirstResponder?()
        return super.resignFirstResponder()
    }

    override func mouseExited(with event: NSEvent) {
        updateLink(with: event)
        super.mouseExited(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        updateLink(with: event)
        super.mouseEntered(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateLink(with: event)
        super.mouseMoved(with: event)
    }

    private func url(for command: String) -> URL {
        return CommandExplainer.instance.newURL(for: command, window: self.window)
    }

    private func updateLink(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .shift, .control, .option]) != [.command] {
            removeLink()
            return
        }

        // Set link if over a command.
        let point = convert(event.locationInWindow, from: nil)
        if let (range, command) = characterRangeOfCommand(at: point) {
            if range != linkRange {
                removeLink()
                makeLink(range, url: url(for: command))
            }
        } else {
            removeLink()
        }
    }

    override func flagsChanged(with event: NSEvent) {
        updateLink(with: event)
        super.flagsChanged(with: event)
    }

    private func makeLink(_ range: NSRange, url: URL) {
        textStorage?.addAttribute(.link, value: url, range: range)
        linkRange = range
        NSCursor.pointingHand.push()
    }

    private func removeLink() {
        if let range = linkRange {
            NSCursor.pop()
            let safeRange = range.intersection(NSRange(location: 0,
                                                       length: (textStorage!.string as NSString).length))
            if let safeRange = safeRange, safeRange.length > 0 {
                textStorage?.removeAttribute(.link, range: safeRange)
            }
            linkRange = nil
        }
    }

    private let suggestionAttribute =  NSAttributedString.Key("iTerm2 Suggestion")

    private func characterRangeOfCommand(at point: NSPoint) -> (NSRange, String)? {
        let characterIndex = layoutManager!.characterIndex(
            for: point,
            in: textContainer!,
            fractionOfDistanceBetweenInsertionPoints: nil)
        let glyphIndex = layoutManager!.glyphIndexForCharacter(at: characterIndex)
        let boundingRect = layoutManager!.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        if !boundingRect.contains(point) {
            return nil
        }
        return characterRangeOfCommand(atCharacterIndex: characterIndex)
    }

    private func characterRangeOfCommand(atCharacterIndex unsafeIndex: Int) -> (NSRange, String)? {
        var characterIndex = unsafeIndex

        // This dense chunk of code finds the range of the command under the cursor, chasing down
        // backslash-newline continuations and noting the index of characters (like backslashes)
        // that shouldn't be included in a query to explainshell.
        var spanningRange: NSRange? = nil
        var characterIndexesToDrop = Set<Int>()
        // Search forwards
        while true {
            let string = (textStorage!.string as NSString)
            let paragraphRange = string.paragraphRange(for: NSRange(location: characterIndex, length: 0))
            if paragraphRange.location == NSNotFound || paragraphRange.length == 0 {
                return nil
            }
            if spanningRange == nil {
                spanningRange = paragraphRange
            } else {
                spanningRange = NSRange(from: spanningRange!.location,
                                        to: paragraphRange.upperBound)
            }
            if spanningRange?.upperBound == string.length {
                break
            }
            let paragraph = string.substring(with: paragraphRange)
            let command = paragraph.trimmingTrailingNewline
            if !command.hasSuffix("\\") {
                break
            }
            characterIndexesToDrop.insert(paragraphRange.location + (command as NSString).length - 1)
            let newlineRange = (paragraph as NSString).rangeOfCharacter(from: .newlines)
            if newlineRange.location != NSNotFound {
                characterIndexesToDrop.insert(paragraphRange.location + newlineRange.location)
            }
            // Found a trailing backslash so add the next paragraph.
            characterIndex = paragraphRange.upperBound
        }
        // Search backwards
        if let suffixRange = spanningRange, suffixRange.location > 0 {
            characterIndex = max(0, suffixRange.location - 1)
            while spanningRange!.location > 0 {
                let string = (textStorage!.string as NSString)
                let paragraphRange = string.paragraphRange(for: NSRange(location: characterIndex, length: 0))
                if paragraphRange.location == NSNotFound || paragraphRange.length == 0 {
                    return nil
                }
                let paragraph = string.substring(with: paragraphRange)
                let command = paragraph.trimmingTrailingNewline
                if !command.hasSuffix("\\") {
                    // This paragraph above the cursor does not end in a continuation so don't
                    // include it.
                    break
                }
                characterIndexesToDrop.insert(paragraphRange.location + (command as NSString).length - 1)
                let newlineRange = (paragraph as NSString).rangeOfCharacter(from: .newlines)
                if newlineRange.location != NSNotFound {
                    characterIndexesToDrop.insert(paragraphRange.location + newlineRange.location)
                }
                spanningRange = NSRange(from: paragraphRange.location,
                                        to: spanningRange!.upperBound)
                characterIndex = max(0, paragraphRange.location - 1)
            }
        }
        guard let spanningRange = spanningRange else {
             return nil
        }

        var rangeExcludingSuggestion = NSRange(location: spanningRange.location, length: 0)
        textStorage!.enumerateAttributes(in: spanningRange) { attributes, range, stop in
            if attributes[suggestionAttribute] != nil {
                // Reached the start of the suggestion.
                stop.pointee = ObjCBool(true)
                return
            }
            rangeExcludingSuggestion = NSRange(from: spanningRange.location,
                                               to: range.upperBound)
        }
        // Remove line continuation backslashes.
        let temp = ((textStorage!.string as NSString).substring(with: rangeExcludingSuggestion) as NSString).mutableCopy() as! NSMutableString
        for index in characterIndexesToDrop.sorted().reversed() {
            temp.replaceCharacters(in: NSRange(location: index, length: 1), with: " ")
        }
        return (rangeExcludingSuggestion, temp as String)
    }

    private func attributedString(for suggestion: String) -> NSAttributedString {
        var attributes = self.typingAttributes
        attributes[.foregroundColor] = NSColor(white: 0.5, alpha: 1.0)
        attributes[suggestionAttribute] = true
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

