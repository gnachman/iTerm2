//
//  NSEvent+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/4/24.
//

import Foundation

extension NSEvent.ModifierFlags {
    static let leftControl = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICELCTLKEYMASK))
    static let leftShift = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICELSHIFTKEYMASK))
    static let rightShift = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERSHIFTKEYMASK))
    static let leftCommand = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICELCMDKEYMASK))
    static let rightCommand = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERCMDKEYMASK))
    static let leftOption = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICELALTKEYMASK))
    static let rightOption = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERALTKEYMASK))
    static let rightControl = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERCTLKEYMASK))
}

@objc
extension NSEvent {
    private static let previousFlagsKey = { iTermMalloc(1) }()

    @objc var it_previousFlags: NSEvent.ModifierFlags {
        get {
            if let obj = it_associatedObject(forKey: Self.previousFlagsKey),
               let number = obj as? NSNumber {
                DLog("Previous flags on event \(self) are \(number)")
                return NSEvent.ModifierFlags(rawValue: number.uintValue)
            }
            return []
        }
        set {
            let n = NSNumber(value: newValue.rawValue)
            DLog("Set previous flags on event \(self) to \(n)")
            it_setAssociatedObject(n,
                                   forKey: Self.previousFlagsKey)
        }
    }
    
    var it_isFunctionOrNumericKeypad: Bool {
        return NSEvent.it_isFunctionOrNumericKeypad(
            modifierFlags: it_modifierFlags)
    }

    static func it_isFunctionOrNumericKeypad(modifierFlags: ModifierFlags) -> Bool {
        return !modifierFlags.intersection([.numericPad, .function]).isEmpty
    }

    @objc func it_shouldSendOptionModifiedKey(leftOptionConfig: iTermOptionKeyBehavior,
                                              rightOptionConfig: iTermOptionKeyBehavior) -> Bool {
        return NSEvent.it_shouldSendOptionModifiedKey(
            modifierFlags: it_modifierFlags,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            leftOptionConfig: leftOptionConfig,
            rightOptionConfig: rightOptionConfig)
    }

    static func it_shouldSendOptionModifiedKey(
        modifierFlags modifiers: ModifierFlags,
        charactersIgnoringModifiers: String?,
        leftOptionConfig: iTermOptionKeyBehavior,
        rightOptionConfig: iTermOptionKeyBehavior) -> Bool {
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
        return NSEvent.it_isControlCodeWithOption(
            modifierFlags: it_modifierFlags,
            keyCode: keyCode,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers)
    }

    static func it_isControlCodeWithOption(
        modifierFlags: NSEvent.ModifierFlags,
        keyCode: UInt16,
        characters: String?,
        charactersIgnoringModifiers: String?) -> Bool {
        if keyCode == kVK_Escape {
            // esc doesn't get treated like other control characters.
            return false
        }
        let allFlags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        guard modifierFlags.intersection(allFlags) == [.control, .option] else {
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
