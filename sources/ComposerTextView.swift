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
    @objc(composerTextViewEnqueue:) func composerTextViewEnqueue(string: String)
    @objc(composerTextViewSendToAdvancedPaste:) func composerTextViewSendToAdvancedPaste(content: String)
    @objc(composerTextViewSendControl:) func composerTextViewSendControl(_ control: String)
    @objc(composerTextViewOpenHistoryWithPrefix:forSearch:) func composerTextViewOpenHistory(prefix: String,
                                                                                             forSearch: Bool)
    @objc(composerTextViewWantsKeyEquivalent:) func composerTextViewWantsKeyEquivalent(_ event: NSEvent) -> Bool
    @objc(composerTextViewPerformFindPanelAction:) func composerTextViewPerformFindPanelAction(_ sender: Any?)
    @objc(composerTextViewClear) func composerTextViewClear()

    @objc(composerSyntaxHighlighterForAttributedString:)
    func composerSyntaxHighlighter(textStorage: NSMutableAttributedString) -> SyntaxHighlighting

    // Optional
    @objc(composerTextViewDidResignFirstResponder) optional func composerTextViewDidResignFirstResponder()
    @objc(composerTextViewDidBecomeFirstResponder) optional func composerTextViewDidBecomeFirstResponder()
}

@objc(iTermComposerTextView)
class ComposerTextView: MultiCursorTextView {
    @IBOutlet weak var composerDelegate: ComposerTextViewDelegate?
    @objc private(set) var isSettingSuggestion = false
    @objc private(set) var isDoingSyntaxHighlighting = false
    private let syntaxHighlightingRateLimit = iTermRateLimitedUpdate(name: "Syntax Highlighting Rate Limit",
                                                                     minimumInterval: 0.05)

    // autoMode will be true for auto-composer, in which case it tries to blend in to the terminal
    // by not requiring shift+enter to send, handling certain control characters like a terminal,
    // etc.
    @objc var autoMode = false

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

    @objc
    var prefix: NSMutableAttributedString? {
        willSet {
            suggestion = nil
        }
        didSet {
            if let prefix {
                prefix.addAttribute(.promptKey, value: true, range: prefix.wholeRange)
            }
            updatePrefix()
        }
    }

    @objc
    var stringExcludingPrefix: String {
        get {
            return String(string.dropFirst(prefix?.string.count ?? 0))
        }
        set {
            string = newValue
            updatePrefix()
        }
    }

    @objc
    var selectedRangeExcludingPrefix: NSRange {
        let range = selectedRange()
        if range.location == NSNotFound {
            return range
        }
        guard let prefixLength = prefix?.string.count else {
            return range
        }
        return range.shiftedDown(by: prefixLength)
    }

    var rangeExcludingPrefixAndSuggestion: Range<Int> {
        let lowerBound = prefix?.string.count ?? 0
        if suggestionRange.length > 0 {
            return lowerBound..<suggestionRange.lowerBound
        } else {
            return lowerBound..<string.count
        }
    }

    private func updatePrefix() {
        guard let textStorage else {
            return
        }
        var done = false
        var actions = [() -> ()]()
        textStorage.enumerateAttribute(.promptKey,
                                       in: textStorage.wholeRange,
                                       options: [.reverse],
                                       using: { value, range, _ in
            if value != nil {
                done = true
                if let prefix {
                    actions.append({
                        textStorage.replaceCharacters(in: range, with: prefix)
                    })
                } else {
                    actions.append({
                        textStorage.deleteCharacters(in: range)
                    })
                }
            }
        })
        if !done, let prefix {
            actions.append({
                textStorage.insert(prefix, at: 0)
            })
        }
        for action in actions {
            action()
        }
    }

    @objc
    var prefixColor: NSColor? {
        didSet {
            updatePrefix()
        }
    }

    @objc
    override var textColor: NSColor? {
        didSet {
            guard let mutableAttributedString = self.textStorage else {
                return
            }
            let suggestionKey = NSAttributedString.Key.suggestionKey

            mutableAttributedString.enumerateAttribute(suggestionKey,
                                                       in: NSRange(location: 0,
                                                                   length: mutableAttributedString.length),
                                                       options: []) { value, range, _ in
                let newColor = value != nil ? suggestionTextColor : justTextColor
                mutableAttributedString.addAttribute(.foregroundColor, value: newColor, range: range)
            }
        }
    }

    private var justTextColor: NSColor {
        return textColor ?? .textColor
    }

    private var suggestionTextColor: NSColor {
        return justTextColor.withAlphaComponent(0.5)
    }

    @objc var hasSuggestion: Bool {
        return suggestion != nil
    }

    @objc func acceptSuggestion() {
        textStorage?.setAttributes(typingAttributes, range: suggestionRange)
        setSelectedRange(NSRange(location: suggestionRange.upperBound, length: 0))
        _suggestion = nil
        suggestionRange = NSRange(location: NSNotFound, length: 0)
        doSyntaxHighlighting()
    }

    @objc var firstSelectionIsNontrivial: Bool {
        return (multiCursorSelectedRanges.first?.length ?? 0) > 0
    }

    @objc func replaceSelectionOrWholeString(string: String) {
        if multiCursorSelectedRanges.count > 1 || firstSelectionIsNontrivial {
            for range in multiCursorSelectedRanges.reversed() {
                multiCursorReplaceCharacters(in: range, with: string)
            }
        } else {
            multiCursorReplaceCharacters(in: NSRange(location: 0, length: textStorage?.length ?? 0),
                                         with: string)
        }
    }

    override func cancelOperation(_ sender: Any?) {
    }

    override func viewDidMoveToWindow() {
        guard let textStorage else {
            return
        }
        if window == nil {
            undoManager?.removeAllActions(withTarget: textStorage)
        }
    }

    override func it_preferredFirstResponder() -> Bool {
        return true
    }

    override func performFindPanelAction(_ sender: Any?) {
        if autoMode {
            if let menuItem = sender as? NSMenuItem {
                switch NSFindPanelAction(rawValue: UInt(menuItem.tag)) {
                case .setFindString:
                    guard let textStorage else {
                        return
                    }
                    let selection = multiCursorSelectedRanges.compactMap { nsrange -> Substring? in
                        guard let range = Range(nsrange) else {
                            return nil
                        }
                        return textStorage.string.substringWithUTF16Range(range)
                    }.joined(separator: "\n")
                    iTermFindPasteboard.sharedInstance().setStringValueUnconditionally(selection)
                    iTermFindPasteboard.sharedInstance().updateObservers(self)
                    return
                default:
                    break
                }
            }
            composerDelegate?.composerTextViewPerformFindPanelAction(sender)
            return
        }
        if let tag = (sender as? NSMenuItem)?.tag, tag == NSFindPanelAction.selectAll.rawValue {
            window?.makeFirstResponder(self)
        }
        super.performFindPanelAction(sender)
    }

    private struct Action {
        var modifiers: NSEvent.ModifierFlags
        var characters: String
        // Return true if you handled it and don't want super.keyDown(with:) called.
        var closure: (ComposerTextView, NSEvent) -> (Bool)
    }

    private let standardActions = [
        Action(modifiers: [.shift], characters: "\r", closure: { textView, _ in
            textView.sendAction()
            return true
        }),
        Action(modifiers: [.shift, .option], characters: "\r", closure: { textView, _ in
            textView.sendEachAction()
            return true
        }),
        Action(modifiers: [.option], characters: "\r", closure: { textView, _ in
            textView.enqueueEachAction()
            return true
        })
    ]

    private var isEmpty: Bool {
        let proposed = [NSRange(location: 0, length: textStorage?.length ?? 0)]
        let valid = self.valid(ranges: proposed)
        return valid.anySatisfies { range in
            range.length > 0
        }
    }

    private let autoModeActions = [
        Action(modifiers: [], characters: "\r", closure: { textView, _ in
            textView.sendAction()
            return true
        }),
        Action(modifiers: [.shift, .option], characters: "\r", closure: { textView, _ in
            textView.sendEachAction()
            return true
        }),
        Action(modifiers: [.option], characters: "\r", closure: { textView, _ in
            textView.enqueueEachAction()
            return true
        }),
        // C-c
        Action(modifiers: [.control], characters: "\u{3}", closure: { textView, event in
            textView.sendKeystroke(event)
            return true
        }),
        // C-d
        Action(modifiers: [.control], characters: "\u{4}", closure: { textView, event in
            guard !textView.isEmpty else {
                // If you press C-d with text present it should do whatever C-D is bound to (normally
                // delete forward).
                return false
            }

            // If the textview is empty then send C-d to the shell, probably killing the session.
            textView.sendKeystroke(event)
            return true
        }),
        // C-l
        Action(modifiers: [.control], characters: "\u{c}", closure: { textView, event in
            textView.composerDelegate?.composerTextViewClear()
            return true
        }),
        // C-r
        Action(modifiers: [.control], characters: "\u{12}", closure: { textView, event in
            textView.selectAll(nil)
            textView.composerDelegate?.composerTextViewOpenHistory(prefix: "", forSearch: true)
            return true
        }),
        // C-u
        Action(modifiers: [.control], characters: "\u{15}", closure: { textView, event in
            textView.selectAll(nil)
            textView.delete(nil)
            return true
        })
    ]

    private var actionsForCurrentMode: [Action] {
        return autoMode ? autoModeActions : standardActions
    }

    private func sendAction() {
        suggestion = nil
        composerDelegate?.composerTextViewDidFinish(cancel: false)
    }

    private func sendEachAction() {
        suggestion = nil
        for command in take() {
            composerDelegate?.composerTextViewSend(string: command)
        }
    }

    private func enqueueEachAction() {
        suggestion = nil
        for command in take() {
            composerDelegate?.composerTextViewEnqueue(string: command)
        }
    }

    private func sendKeystroke(_ event: NSEvent) {
        if let characters = event.characters {
            composerDelegate?.composerTextViewSendControl(characters)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let composerDelegate,
           composerDelegate.composerTextViewWantsKeyEquivalent(event) {
            return true
        }
        // Allow NSTextView to handle it.
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let pressedEsc = event.characters == "\u{1b}"
        if pressedEsc {
            suggestion = nil
            composerDelegate?.composerTextViewDidFinish(cancel: true)
            return
        }

        let mask: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        let maskedModifiers = event.it_modifierFlags.intersection(mask)

        let action = actionsForCurrentMode.first { action in
            action.characters == event.characters && action.modifiers == maskedModifiers
        }
        if let action, action.closure(self, event) {
            return
        }
        super.keyDown(with: event)
    }

    private var canMoveUp: Bool {
        return glyphRangeAbove(glyphRange: selectedRange()) != nil
    }

    private var canMoveDown: Bool {
        return glyphRangeBelow(glyphRange: selectedRange()) != nil
    }

    override func moveUp(_ sender: Any?) {
        if cursorAtEndExcludingSuggestion && !canMoveUp && multiCursorSelectedRanges.count <= 1 {
            suggestion = nil
            composerDelegate?.composerTextViewOpenHistory(prefix: stringExcludingPrefix, forSearch: false)
        } else {
            super.moveUp(sender)
        }
    }

    override func moveDown(_ sender: Any?) {
        if cursorAtEndExcludingSuggestion && !canMoveDown && multiCursorSelectedRanges.count <= 1 {
            suggestion = nil
            composerDelegate?.composerTextViewOpenHistory(prefix: stringExcludingPrefix, forSearch: false)
        } else {
            super.moveDown(sender)
        }
    }

    private func withoutPrefix<T>(_ closure: () throws -> (T)) rethrows -> T {
        let saved = prefix
        prefix = nil
        defer {
            prefix = saved
        }
        return try closure()
    }

    private func take() -> [String] {
        withoutPrefix {
            return Array(multiCursorSelectedRanges.reversed().compactMap {
                take(range: $0)
            }.reversed())
        }
    }

    // Extracts the command intersecting `range`, removes it from the textview, and returns it.
    // Returns nil if the range is invalid.
    // range: A glyph range.
    private func take(range: NSRange) -> String? {
        guard let layoutManager, let textStorage else {
            return nil
        }
        let string = textStorage.string as NSString
        let stringToTake: String
        var rangeToTake: NSRange
        if range.length > 0 {
            stringToTake = string.substring(with: range)
            rangeToTake = range
        } else {
            let characterIndex = layoutManager.characterRange(forGlyphRange: range,
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

    override func becomeFirstResponder() -> Bool {
        composerDelegate?.composerTextViewDidBecomeFirstResponder?()
        return super.becomeFirstResponder()
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
        guard let textStorage else {
            return
        }
        if let range = linkRange {
            NSCursor.pop()
            let safeRange = range.intersection(NSRange(location: 0,
                                                       length: (textStorage.string as NSString).length))
            if let safeRange = safeRange, safeRange.length > 0 {
                textStorage.removeAttribute(.link, range: safeRange)
            }
            linkRange = nil
        }
    }

    private func characterRangeOfCommand(at point: NSPoint) -> (NSRange, String)? {
        guard let layoutManager, let textContainer else {
            return nil
        }
        let characterIndex = layoutManager.characterIndex(
            for: point,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        let boundingRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        if !boundingRect.contains(point) {
            return nil
        }
        return characterRangeOfCommand(atCharacterIndex: characterIndex)
    }

    private func characterRangeOfCommand(atCharacterIndex unsafeIndex: Int) -> (NSRange, String)? {
        guard let textStorage else {
            return nil
        }
        if unsafeIndex < 0 {
            return nil
        }
        if let prefixLength = prefix?.string.count, prefixLength > 0 {
            if unsafeIndex > prefixLength {
                return nil
            }
            if let (_range, string) = withoutPrefix({
                return characterRangeOfCommand(atCharacterIndex: unsafeIndex - prefixLength)
            }) {
                var range = _range
                range.location += prefixLength
                return (range, string)
            } else {
                return nil
            }
        }
        var characterIndex = unsafeIndex

        // This dense chunk of code finds the range of the command under the cursor, chasing down
        // backslash-newline continuations and noting the index of characters (like backslashes)
        // that shouldn't be included in a query to explainshell.
        var spanningRange: NSRange? = nil
        var characterIndexesToDrop = Set<Int>()
        // Search forwards
        while true {
            let string = (textStorage.string as NSString)
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
                let string = (textStorage.string as NSString)
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
        textStorage.enumerateAttributes(in: spanningRange) { attributes, range, stop in
            if attributes[NSAttributedString.Key.suggestionKey] != nil {
                // Reached the start of the suggestion.
                stop.pointee = ObjCBool(true)
                return
            }
            rangeExcludingSuggestion = NSRange(from: spanningRange.location,
                                               to: range.upperBound)
        }
        // Remove line continuation backslashes.
        let temp = ((textStorage.string as NSString).substring(with: rangeExcludingSuggestion) as NSString).mutableCopy() as! NSMutableString
        for index in characterIndexesToDrop.sorted().reversed() {
            temp.replaceCharacters(in: NSRange(location: index, length: 1), with: " ")
        }
        return (rangeExcludingSuggestion, temp as String)
    }

    private func attributedString(for suggestion: String) -> NSAttributedString {
        var attributes = self.typingAttributes
        attributes[.foregroundColor] = suggestionTextColor
        attributes[NSAttributedString.Key.suggestionKey] = true
        return NSAttributedString(string: suggestion, attributes: attributes)
    }

    private func attributedString(from suggestion: String) -> NSAttributedString {
        return NSAttributedString(string: suggestion, attributes: typingAttributes)
    }

    private var cursorAtEnd: Bool {
        guard let textStorage else {
            return false
        }
        let endLocation = textStorage.string.count
        return multiCursorSelectedRanges.anySatisfies { range in
            range.location == endLocation
        }
    }

    private var cursorAtEndExcludingSuggestion: Bool {
        guard let saved = suggestion else {
            return cursorAtEnd
        }
        suggestion = nil
        defer {
            suggestion = saved
        }
        return cursorAtEnd
    }

    private func reallySetSuggestion(_ suggestion: String?) {
        guard let textStorage else {
            return
        }
        if !cursorAtEnd, let suggestion, suggestion.contains(" ") {
            let truncated = suggestion.substringUpToFirstSpace
            if truncated.isEmpty {
                reallySetSuggestion(nil)
            } else {
                reallySetSuggestion(String(truncated))
            }
            return
        }
        if let suggestion = suggestion {
            if hasSuggestion {
                // Replace existing suggestion with a different one.
                textStorage.replaceCharacters(in: suggestionRange,
                                              with: attributedString(for: suggestion))
                _suggestion = suggestion
                suggestionRange = NSRange(location: suggestionRange.location,
                                          length: (suggestion as NSString).length);
                setSelectedRange(NSRange(location: suggestionRange.location, length: 0))
                return;
            }

            // Didn't have suggestion before but will have one now
            let location = selectedRange().upperBound
            textStorage.replaceCharacters(in: NSRange(location: location, length: 0),
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
        temp.enumerateAttribute(NSAttributedString.Key.suggestionKey,
                                in: NSRange(location: 0, length: temp.length),
                                options: [.reverse]) { value, range, _ in
            if value != nil {
                rangesToRemove.append(range)
            }
        }

        // 2. Delete those ranges, adjusting the cursor location as needed to keep it in the same place.
        var selectedRange = self.selectedRange()
        for range in rangesToRemove {
            selectedRange = selectedRange.minus(range)
            textStorage.deleteCharacters(in: range)
        }

        // 3. Position the cursor and clean up internal state.
        self.selectedRange = selectedRange
        _suggestion = nil
        suggestionRange = NSRange(location: NSNotFound, length: 0)
    }

    @objc
    func doSyntaxHighlighting() {
        syntaxHighlightingRateLimit.performRateLimitedBlock { [weak self] in
            self?.reallyDoSyntaxHighlighting()
        }
    }

    private func reallyDoSyntaxHighlighting() {
        guard let textStorage else {
            return
        }
        isDoingSyntaxHighlighting = true
        composerDelegate?.composerSyntaxHighlighter(
            textStorage: textStorage).highlight(
                range: NSRange(rangeExcludingPrefixAndSuggestion))
        isDoingSyntaxHighlighting = false
    }

    private var prefixLength: Int {
        return prefix?.string.utf16.count ?? 0
    }

    private var prefixRange: NSRange {
        NSRange(location: 0, length: prefixLength)
    }

    override func valid(ranges: [NSRange]) -> [NSRange] {
        // Ensure no part of the prefix is selected
        var modifiedRanges = ranges.compactMap { charRange -> NSRange? in
            if charRange.location > prefixLength {
                return charRange
            }
            let end = charRange.location + charRange.length
            if end < prefixLength {
                return nil
            }
            return NSRange(prefixLength..<end)
        }
        if modifiedRanges.isEmpty && !ranges.isEmpty {
            // If there are none then it must have removed all of them for being in the prefix.
            modifiedRanges = [NSRange(from: prefixLength, to: prefixLength)]
        }
        return modifiedRanges
    }

    override func setSelectedRanges(_ ranges: [NSValue],
                                    affinity: NSSelectionAffinity,
                                    stillSelecting stillSelectingFlag: Bool) {

        // Ensure no part of the prefix is selected
        let modifiedRanges = valid(ranges: ranges.map { $0.rangeValue }).map { NSValue(range: $0) }
        super.setSelectedRanges(modifiedRanges,
                                affinity: affinity,
                                stillSelecting: stillSelectingFlag)
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        if let affected = Range(affectedCharRange), let prefixRange = Range(self.prefixRange), affected.overlaps(prefixRange) {
            return false
        }
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
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


extension NSEvent.ModifierFlags: Hashable {

}

extension String {
    var substringUpToFirstSpace: Substring {
        guard let index = self.firstIndex(of: " ") else {
            return Substring(self)
        }
        return self[..<index]
    }
}

extension NSAttributedString.Key {
    static let suggestionKey = NSAttributedString.Key(rawValue: "com.googlecode.iterm2.ComposerTextView.suggestionKey")
    static let promptKey = NSAttributedString.Key(rawValue: "com.googlecode.iterm2.ComposerTextView.promptKey")
}

extension NSAttributedString {
    var wholeRange: NSRange { NSRange(location: 0, length: length) }
}

