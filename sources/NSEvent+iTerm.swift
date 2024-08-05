//
//  NSEvent+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/4/24.
//

import Foundation

extension NSEvent.ModifierFlags {
    static let left =  UInt(0x20)
    static let right = UInt(0x40)

    static let leftOption =  NSEvent.ModifierFlags(rawValue: option.rawValue | left)
    static let rightOption = NSEvent.ModifierFlags(rawValue: option.rawValue | right)
}

extension NSEvent {
    func it_unicodeForKeyIgnoringShift(ignoreOption: Bool) -> UnicodeScalar? {
        // Returns the base unicode characters for this KeyDown event as though shift was
        // NOT pressed, and optionally as though option was also not pressed.
        //
        // A few examples:
        // * If the event is shift+A on a US keyboard, this would would return the
        //   UnicodeScalar for "a"
        // * If the event is option-A on a US keyboard and ignoreOption is true, this
        //   would return the UnicodeScalar for "a"
        // * If the event is option-A on a US keyboard and ignoreOption is false, this
        //   would return the UnicodeScalar for "å"Å
        return it_unicodeForKeyWithHacks(shift: false, ignoreOption: ignoreOption)
    }

    func it_unicodeForKeyForcingShift(ignoreOption: Bool) -> UnicodeScalar? {
        // Returns the base unicode character for this KeyDown event as though shift was
        // pressed and optionally as though option was *not* pressed.
        //
        // A few examples:
        // * If the event is "a" on a US keyboard, return the UnicodeScalar for "A"
        // * If the event is "A" on a US keyboard, return the UnicodeScalar for "A"
        // * If the event is option+"a" on a US keyboard and ignoreOption is true, return the UnicodeScalar for "A"
        // * If the event is option+"a" on a US keyboard and ignoreOption is false, return the UnicodeScalar for "Å"
        return it_unicodeForKeyWithHacks(shift: true, ignoreOption: ignoreOption)
    }

    private func it_unicodeForKeyWithHacks(shift shiftPressed: Bool,
                                           ignoreOption: Bool) -> UnicodeScalar? {
        let optionPressed = self.modifierFlags.contains(.option)
        let controlPressed = modifierFlags.contains(.control)
        let controlState = controlPressed ? (1 << controlKeyBit) : 0
        let optionState = ignoreOption ? 0 : (optionPressed ? (1 << shiftKeyBit) : 0)
        let shiftState = shiftPressed ? (1 << shiftKeyBit) : 0
        let state = UInt32(controlState | optionState | shiftState)

        let unichar = NSEvent.unicharForKey(withKeycode: keyCode, modifiers: state)
        return UnicodeScalar(unichar)
    }
}

@objc
extension NSEvent {
    private static let previousFlagsKey = { iTermMalloc(1) }()

    @objc var it_previousFlags: NSEvent.ModifierFlags {
        get {
            if let obj = it_associatedObject(forKey: Self.previousFlagsKey),
               let number = obj as? NSNumber {
                return NSEvent.ModifierFlags(rawValue: number.uintValue)
            }
            return []
        }
        set {
            it_setAssociatedObject(NSNumber(value: newValue.rawValue),
                                   forKey: Self.previousFlagsKey)
        }
    }
    
    var it_isFunctionOrNumericKeypad: Bool {
        let modifiers = it_modifierFlags
        return !modifiers.intersection([.numericPad, .function]).isEmpty
    }

    @objc func it_shouldSendOptionModifiedKey(leftOptionConfig: iTermOptionKeyBehavior,
                                              rightOptionConfig: iTermOptionKeyBehavior) -> Bool {
        let modifiers = it_modifierFlags;
        DLog("leftConfig=\(leftOptionConfig) rightConfig=\(rightOptionConfig) charactersIgnoringModifiers=\(charactersIgnoringModifiers ?? "") flags=\(modifiers)")

        guard !(charactersIgnoringModifiers ?? "").isEmpty else {
            DLog("> no characters")
            return false
        }
        let rightAltPressed = modifiers.contains(.rightOption)
        let leftAltPressed = modifiers.contains(.leftOption) && !rightAltPressed
        let leftOptionModifiesKey = leftAltPressed && leftOptionConfig != .OPT_NORMAL
        if leftOptionModifiesKey {
            DLog("> leftOptionModifiesKey=\(leftOptionModifiesKey)")
            return true
        }
        let rightOptionModifiesKey = rightAltPressed && rightOptionConfig != .OPT_NORMAL
        DLog("> rightOptionModifiesKey=\(rightOptionModifiesKey)")
        return rightOptionModifiesKey
    }

    // Did you press ctrl+option+[key that sends a control like c or 6]?
    // On non-US keyboards, if you have to press option to get a character, this treats it as
    // though option was *not* pressed. See the notes below about Spanish keyboards.
    @objc var it_isControlCodeWithOption: Bool {
        if keyCode == kVK_Escape {
            // esc doesn't get treated like other control characters.
            return false
        }
        let allFlags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        guard it_modifierFlags.intersection(allFlags) == [.control, .option] else {
            return false
        }
        guard let characters, characters.count == 1 else {
            return false
        }
        let character = characters.firstASCIICharacter
        guard character < 32 else {
            return false
        }
        let controlCode = Character(UnicodeScalar(character + UInt8("@".unicodeScalars.first!.value)))

        // When they are equal:
        // On US keyboards, when you just press control+opt+<char> you get:
        //  event.characters="<control code>" event.charactersIgnoringModifiers="<char>"
        // On Spanish ISO (and presumably all others like it) when you press control+opt+<char> you can get:
        //  event.characters="<control code>" event.charactersIgnoringModifiers="<some random other thing on the key>"
        // This code path prevents control-opt-char from ignoring the Option modifier on US-style
        // keyboards. Those should not be treated as control keys. The reason I think this is correct
        // is that on a keyboard that *requires* you to press option to get a control, it must be
        // because the default character for the key is not the one that goes with the control. For
        // example, on Spanish ISO the key labeled + becomes ] when you press option. So to send
        // C-] you have to press C-Opt-], and modifyOtherKeys should treat it as C-].
        //
        // When the are unequal:
        // This is a control key. We can't just send it in modifyOtherKeys=2 mode. For example,
        // in issue 9279 @elias.baixas notes that on a Spanish ISO keyboard you press control-alt-+
        // to get control-]. characters="<0x1d>".
        return charactersIgnoringModifiers != String(controlCode)
    }
}
