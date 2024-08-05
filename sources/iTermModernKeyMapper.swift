//
//  iTermModernKeyMapper.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/27/24.
//

import Foundation

@objc(iTermModernKeyMapperDelegate)
protocol ModernKeyMapperDelegate: iTermStandardKeyMapperDelegate {
    @objc
    func modernKeyMapperDelegateStringEncoding() -> UInt  // NSStringEncoding

    @objc
    func modernKeyMapperWillMapKey() -> ObjCModernKeyMapperConfiguration

    @objc
    func modernKeyMapperInApplicationKeypadMode() -> Bool
}

struct ModernKeyMapperConfiguration {
    var leftOptionKey: iTermOptionKeyBehavior
    var rightOptionKey: iTermOptionKeyBehavior
}

@objc(iTermModernKeyMapperConfiguration)
class ObjCModernKeyMapperConfiguration: NSObject {
    let value: ModernKeyMapperConfiguration

    @objc
    init(leftOptionKey: iTermOptionKeyBehavior,
         rightOptionKey: iTermOptionKeyBehavior) {
        value = ModernKeyMapperConfiguration(leftOptionKey: leftOptionKey,
                                             rightOptionKey: rightOptionKey)
    }
}

@objc(iTermModernKeyMapper)
class ModernKeyMapper: NSObject, iTermKeyMapper {
    @objc var flags = VT100TerminalKeyReportingFlags(rawValue: 0)
    @objc weak var delegate: ModernKeyMapperDelegate?
    private var configuration = ModernKeyMapperConfiguration(leftOptionKey: .OPT_NORMAL,
                                                             rightOptionKey: .OPT_NORMAL)
    private var event: NSEvent?

    // Process it immediately in the delegate? If you return true IME doesn't get a chance at this.
    func keyMapperShouldBypassPreCocoa(for event: NSEvent) -> Bool {
        NSLog("%@", "keyMapperShouldBypassPreCocoa(for: \(event))")
        updateConfiguration(event: event)

        if event.it_isFunctionOrNumericKeypad {
            // The original reason for this clause is in the old iterm codebase (commit f7c8312)
            // where Ujwal wrote:
            //   Fixed problem when PTYSession: -keyDown is never called when numeric or
            //   function keys were pressed. This messes up switching between application and
            //   numeric keypad modes. Now PTYTextView: -keyDown: invokes PTYSession: -keyDown:
            //   when numeric or function keys are pressed.
            // I think the problem this meant to solve is that function keys could cause
            // insertText: or doCommandBySelector: to be called which bypassed the function
            // key and application keypad mode handling in -[PTYSession keyDown:].
            //
            // This causes the IME to be bypassed, but I still think it's the right thing to
            // do because we do want the delegate to get first whack at scrolling keys, which
            // returning true forces to happen here.
            DLog("true: event is function or numeric keypad")
            return true
        }

        if event.it_shouldSendOptionModifiedKey(leftOptionConfig: configuration.leftOptionKey, rightOptionConfig: configuration.rightOptionKey) {
            // Treating option as Esc+ (or its CSI u equivalent)
            DLog("true: should send option-modified key")
            return true
        }

        if event.it_isControlCodeWithOption {
            // You pressed ctrl-option-[key that sends a control like c or 6]
            // We don't want Cocoa to handle it and call insertText: or performKeyEquivalent:.
            // Note that this is a departure from what the ModifyOtherKeys mapper does.
            // I believe it may be buggy.
            DLog("true: control+option control code")
            return true
        }

        return false
    }

    // flagsChanged takes only this path.
    func keyMapperString(forPreCocoaEvent event: NSEvent) -> String? {
        NSLog("%@", "keyMapperString(forPreCocoaEvent: \(event))")

        switch event.type {
        case .keyDown:
            if event.modifierFlags.contains(.numericPad) {
                return keyMapperData(forPostCocoaEvent: event)?.lossyString
            }
            if event.modifierFlags.intersection([.control, .command, .option]) != [.control] {
                // If you're holding a modifier other than control (and optionally shift) let it go
                // to cocoa. Other keymappers are a little more selective, choosing to handle
                // only valid controls pre-cocoa, but I don't think it matters. I could be wrong.
                return nil
            }
        case .flagsChanged:
            break
        default:
            return nil
        }

        return handle(event: event)?.lossyString
    }

    func keyMapperData(forPostCocoaEvent event: NSEvent) -> Data? {
        NSLog("%@", "keyMapperString(forPostCocoaEvent: \(event))")
        return handle(event: event)
    }

    func keyMapperSetEvent(_ event: NSEvent) {
        NSLog("%@", "keyMapperSetEvent(\(event))")
        self.event = event
    }

    func keyMapperWantsKeyEquivalent(_ event: NSEvent) -> Bool {
        // Let command-key behave normally. Otherwise, we'll take it. For example,
        // control-shift-arrow takes this path.
        return !event.modifierFlags.contains(.command)
    }

    func keyMapperDictionaryValue() -> [AnyHashable : Any] {
        return ["flags": NSNumber(value: flags.rawValue)]
    }

    func keyMapperData(forKeyUp event: NSEvent) -> Data? {
        NSLog("%@", "keyMapperData(forKeyUp: \(event))")
        guard flags.contains(.reportAllEventTypes) else {
            return nil
        }
        return handle(event: event)
    }
}

private extension ModernKeyMapper {
    private var modifiers: KeyboardProtocolModifers {
        return KeyboardProtocolModifers(rawValue: UInt32(flags.rawValue))
    }

    private func updateConfiguration(event: NSEvent) {
        self.event = event
        if let delegate {
            configuration = delegate.modernKeyMapperWillMapKey().value
        }
    }

    private func handle(event: NSEvent) -> Data? {
        updateConfiguration(event: event)
        let encoding = delegate?.modernKeyMapperDelegateStringEncoding() ?? String.Encoding.utf8.rawValue
        let s = string(for: event, preCocoa: false)
        if s.isEmpty {
            NSLog("Returning nil")
            return nil
        }
        NSLog("%@", "Returning \(s)")
        return s.data(using: String.Encoding(rawValue: encoding))
    }

    private func string(for event: NSEvent, preCocoa: Bool) -> String {
        let reports = {
            switch event.type {
            case .keyDown:
                if event.isARepeat {
                    return [regularReport(type: .repeat, event: event)]
                }
                return [regularReport(type: .press, event: event)]
            case .keyUp:
                return [regularReport(type: .release, event: event)]
            case .flagsChanged:
                if !flags.contains(.reportAllEventTypes) {
                    return []
                }
                let before = event.it_previousFlags
                let after = event.it_modifierFlags
                let pressed = after.subtracting(before)
                let released = before.subtracting(after)
                let releaseReports = released.map {
                    flagsChangedReport(type: .release, flag: $0, event: event)
                }
                let pressReports = pressed.map {
                    flagsChangedReport(type: .press, flag: $0, event: event)
                }
                return releaseReports + pressReports
            default:
                DLog("Unexpected event type \(event.type)")
                return []
            }
        }()
        return reports.map {
            switch $0.encoded(enhancementFlags: flags) {
            case .fallbackToAmbiguous:
                return ambiguousString(keyReport: $0, preCocoa: preCocoa)
            case .nonReportable:
                return ""
            case .string(let value):
                return value
            }
        }.joined(separator: "")
    }

    private func regularReport(type: KeyReport.EventType, event: NSEvent) -> KeyReport {
        let unicodeKeyCode = self.unicodeKeyCode(for: event)
        let shiftedKeyCode = self.shiftedKeyCode(for: event)
        let baseLayoutKeyCode = self.baseLayoutKeyCode(for: event)
        let textCodepoints = (event.characters ?? "").flatMap { character in
            character.unicodeScalars.map { scalar in
                scalar.value
            }
        }
        return KeyReport(type: type,
                         virtualKeyCode: Int(event.keyCode),
                         unicodeKeyCode: unicodeKeyCode,
                         shiftedKeyCode: shiftedKeyCode,
                         baseLayoutKeyCode: baseLayoutKeyCode,
                         modifiers: KeyboardProtocolModifers(event, 
                                                             leftOptionNormal: leftOptionNormal,
                                                             rightOptionNormal: rightOptionNormal),
                         textAsCodepoints: textCodepoints,
                         characters: event.characters ?? "",
                         numpad: event.modifierFlags.contains(.numericPad),
                         charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                         event: event)
    }

    private func baseLayoutKeyCode(for event: NSEvent) -> UInt32 {
        if let real = event.it_unicodeForKeyIgnoringShift(ignoreOption: true) {
            return real.value
        }
        if let firstScalar = event.charactersIgnoringModifiers?.first?.unicodeScalars.first {
            return firstScalar.value
        }
        return 0
    }

    private func unicodeKeyCode(for event: NSEvent) -> UInt32 {
        let ignoreOption = !shouldUseNativeOptionBehavior(event: event)
        if let real = event.it_unicodeForKeyIgnoringShift(ignoreOption: ignoreOption) {
            return real.value
        }
        if let firstScalar = event.charactersIgnoringModifiers?.first?.unicodeScalars.first {
            return firstScalar.value
        }
        return 0
    }

    private func shiftedKeyCode(for event: NSEvent) -> UInt32 {
        let ignoreOption = !shouldUseNativeOptionBehavior(event: event)
        if let real = event.it_unicodeForKeyForcingShift(ignoreOption: ignoreOption) {
            return real.value
        }
        if let firstScalar = event.charactersIgnoringModifiers?.first?.unicodeScalars.first {
            return firstScalar.value
        }
        return 0
    }

    private func flagsChangedReport(type: KeyReport.EventType,
                                    flag: NSEvent.ModifierFlags,
                                    event: NSEvent) -> KeyReport {
        precondition(flags.contains(.reportAllEventTypes))
        let (virtualKeyCode, unicodeKeyCode) =
            if flag.contains(.shift) {
                (kVK_Shift, UInt32(57441))
            } else if flag.contains(.control) {
                (kVK_Control, UInt32(57442))
            } else if flag.contains(.leftOption) && leftOptionNormal {
                (kVK_Option, UInt32(57443))
            } else if flag.contains(.rightOption) && rightOptionNormal {
                (kVK_Option, UInt32(57449))
            } else if flag.contains(.command) {
                (kVK_Command, UInt32(57444))
            } else {
                fatalError("Invalid flag \(flag.rawValue)")
            }
        return KeyReport(type: type,
                         virtualKeyCode: virtualKeyCode,
                         unicodeKeyCode: unicodeKeyCode,
                         shiftedKeyCode: nil,
                         baseLayoutKeyCode: unicodeKeyCode, 
                         modifiers: KeyboardProtocolModifers(
                            event,
                            leftOptionNormal: leftOptionNormal,
                            rightOptionNormal: rightOptionNormal),
                         textAsCodepoints: [],
                         characters: "",
                         numpad: event.modifierFlags.contains(.numericPad),
                         charactersIgnoringModifiers: "",
                         event: event)
    }

    private var leftOptionNormal: Bool {
        return configuration.leftOptionKey == .OPT_NORMAL
    }

    private var rightOptionNormal: Bool {
        return configuration.rightOptionKey == .OPT_NORMAL
    }

    private func shouldUseNativeOptionBehavior(event: NSEvent) -> Bool {
        if event.it_modifierFlags.contains(.leftOption) && leftOptionNormal {
            return true
        }
        if event.it_modifierFlags.contains(.rightOption) && rightOptionNormal {
            return true
        }
        return false
    }

    private func ambiguousString(keyReport: KeyReport, preCocoa: Bool) -> String {
        if keyReport.event.type == .flagsChanged {
            return ""
        }
        if keyReport.type == .release {
            return ""
        }

        let mapper = iTermStandardKeyMapper()
        mapper.delegate = delegate
        mapper.keyMapperSetEvent(keyReport.event)

        let data = if preCocoa {
            mapper.keyMapperData(forPostCocoaEvent: keyReport.event)
        } else {
            mapper.keyMapperData(forPostCocoaEvent: keyReport.event)
        }
        return data?.lossyString ?? ""
    }
}

extension Array where Element == String {
    var removingTrailingEmptyStrings: [String] {
        var temp = self
        while temp.last == "" {
            temp.removeLast()
        }
        return temp
    }
}

// Same as VT100TerminalKeyReportingFlags
fileprivate struct KeyboardProtocolModifers: OptionSet {
    let rawValue: UInt32

    static let shift =     Self.init(rawValue: 0b1)
    static let alt =       Self.init(rawValue: 0b10)
    static let ctrl =      Self.init(rawValue: 0b100)
    static let cmd =       Self.init(rawValue: 0b1000)  // called super in the docs
    static let hyper =     Self.init(rawValue: 0b10000)  // not relevant on Mac
    static let meta =      Self.init(rawValue: 0b100000)  // not relevant on Mac
    static let caps_lock = Self.init(rawValue: 0b1000000)
    static let num_lock =  Self.init(rawValue: 0b10000000)  // not relevant on Mac

    var encoded: UInt32? {
        if rawValue == 0 {
            return nil
        }
        return rawValue + 1
    }
}

extension KeyboardProtocolModifers {
    init(_ event: NSEvent, leftOptionNormal: Bool, rightOptionNormal: Bool) {
        var value = UInt32(0)
        if event.modifierFlags.contains(.shift) {
            value |= Self.shift.rawValue
        }
        if event.modifierFlags.contains(.leftOption) && !leftOptionNormal {
            value |= Self.alt.rawValue
        }
        if event.modifierFlags.contains(.rightOption) && !rightOptionNormal {
            value |= Self.alt.rawValue
        }
        if event.modifierFlags.contains(.control) {
            value |= Self.ctrl.rawValue
        }
        if event.modifierFlags.contains(.command) {
            value |= Self.cmd.rawValue
        }
        if event.modifierFlags.contains(.capsLock) {
            value |= Self.caps_lock.rawValue
        }
        rawValue = value
    }
}

fileprivate struct KeyReport {
    enum EventType: UInt32 {
        case press = 1
        case `repeat` = 2
        case release = 3

        var encoded: UInt32? {
            if self == .press {
                return nil
            }
            return rawValue
        }
    }

    var type: EventType
    var virtualKeyCode: Int  // kVK…
    var unicodeKeyCode: UInt32  // associated with key, so 97 for shift-A; for function keys, use private use values.
    var shiftedKeyCode: UInt32?  // uppercase/shifted version of unicodeKeyCode (65 for shift-A)
    var baseLayoutKeyCode: UInt32  // keycode for physical key on PC-101 (so 97 for ф on a Russian keyboard because that's A on a US keyboard)
    var modifiers: KeyboardProtocolModifers  // won't include alt if alt has native functionality (i.e., not esc+)
    var textAsCodepoints: [UInt32]
    var characters: String
    var numpad: Bool  // is this key on the numeric keypad?
    var charactersIgnoringModifiers: String
    var event: NSEvent

    private let csi = "\u{001B}["

    private var eligibleForCSI: Bool {
        if !modifiers.isEmpty {
            return true
        }
        return ![UInt32("\r"),
                 UInt32("\t"),
                 UInt32(0x7f)].contains(unicodeKeyCode)
    }

    private var legacyUnderDisambiguateEscape: EncodedKeypress {
        let onlyLegacyCompatibleModifiers = modifiers.subtracting([.ctrl, .shift, .num_lock, .caps_lock]).isEmpty
        if !onlyLegacyCompatibleModifiers {
            return .nonReportable
        }

        // Turning on this flag will cause the terminal to report the Esc, alt+key, ctrl+key,
        // ctrl+alt+key, shift+alt+key keys using CSI u sequences instead of legacy ones.
        // Here key is any ASCII key as described in Legacy text keys. 
        if unicodeKeyCode == 27 {
            // esc must be reported with CSI u
            return .nonReportable
        }
        let nonLockModifiers = modifiers.subtracting([.caps_lock, .num_lock])
        guard nonLockModifiers == [] else {
            // keys with reportable modifiers must be reported with CSI u
            return .nonReportable
        }

        // Additionally, all keypad keys will be reported as separate keys with CSI u
        // encoding, using dedicated numbers from the table below.
        if numpad {
            return .nonReportable
        }

        // Legacy keys are defined as: a-z 0-9 ` - = [ ] \ ; ' , . /
        //
        // Furthermore:
        // The only exceptions are the Enter, Tab and Backspace keys which still generate
        // the same bytes as in legacy mode this is to allow the user to type and execute
        // commands in the shell such as reset after a program that sets this mode crashes
        // without clearing it.
        //
        // However, Kitty's implementation also allows backspace through.
        // I am interpreting this as referring to the unicode-key-code.
        // I am not confident this will work well with non-US keyboards.
        let sets = [CharacterSet(charactersIn: Unicode.Scalar("a")...Unicode.Scalar("z")),
                    CharacterSet(charactersIn: Unicode.Scalar("0")...Unicode.Scalar("9")),
                    CharacterSet(charactersIn: "`-=[]\\;',./"),
                    CharacterSet(charactersIn: "\n\r\t\u{7F}")]
        let legacyKeys = sets.reduce(CharacterSet()) {
            $0.union($1)
        }
        if !legacyKeys.contains(codePoint: unicodeKeyCode) {
            return .nonReportable
        }

        if nonLockModifiers == [] {
            return .string(characters)
        }
        let maybeEsc = modifiers.contains(.alt) ? "\u{001B}" : ""
        let rest = { () -> String? in
            if nonLockModifiers == [.ctrl] && characters == " " {
                return "\u{0}"
            }
            if modifiers.contains(.ctrl) {
                return legacyControl
            }
            return characters
        }()
        if let rest {
            return .string(maybeEsc + rest)
        }

        return .nonReportable
    }

    private var legacyControl: String? {
        let code = switch characters {
        case " ": 0
        case "/": 31
        case "0": 48
        case "1": 49
        case "2": 0
        case "3": 27
        case "4": 28
        case "5": 29
        case "6": 30
        case "7": 31
        case "8": 127
        case "9": 57
        case "?": 127
        case "@": 0
        case "[": 27
        case "\\": 28
        case "]": 29
        case "^": 30
        case "_": 31
        case "a": 1
        case "b": 2
        case "c": 3
        case "d": 4
        case "e": 5
        case "f": 6
        case "g": 7
        case "h": 8
        case "i": 9
        case "j": 10
        case "k": 11
        case "l": 12
        case "m": 13
        case "n": 14
        case "o": 15
        case "p": 16
        case "q": 17
        case "r": 18
        case "s": 19
        case "t": 20
        case "u": 21
        case "v": 22
        case "w": 23
        case "x": 24
        case "y": 25
        case "z": 26
        case "~": 30
        default: Optional<Int>.none
        }
        if let code {
            return String(ascii: UInt8(code))
        }
        return nil
    }

    enum EncodedKeypress {
        case nonReportable
        case string(String)
        case fallbackToAmbiguous
    }

    // This is tried first. If it should be reported as CSI U then return .nonReportable.
    private func legacyEncodedKeypress(_ enhancementFlags: VT100TerminalKeyReportingFlags) -> EncodedKeypress {
        if type == .repeat && enhancementFlags.contains(.reportAllEventTypes) {
            // When reporting event types, we cannot use legacy reporting for repeats.
            return .nonReportable
        }
        if type == .release {
            // Release is never reportable as legacy.
            return .nonReportable
        }
        if enhancementFlags.contains(.reportAllKeysAsEscapeCodes) {
            // Flag means to never use legacy.
            return .nonReportable
        }
        if enhancementFlags.contains(.disambiguateEscape) {
            // Return a legacy string unless it would be ambiguous
            return legacyUnderDisambiguateEscape
        }
        // Actually report as legacy. It's up to the client of ModernKeyMapper to implement
        // this.
        return .fallbackToAmbiguous
    }

    func encoded(enhancementFlags: VT100TerminalKeyReportingFlags) -> EncodedKeypress {
        if type == .release && !enhancementFlags.contains(.reportAllEventTypes) {
            // Don't report key-up unless reportEventType is on.
            return .nonReportable
        }
        switch legacyEncodedKeypress(enhancementFlags) {
        case .string(let string):
            return .string(string)
        case .fallbackToAmbiguous:
            return .fallbackToAmbiguous
        case .nonReportable:
            return csiU(enhancementFlags: enhancementFlags)
        }

    }

    private func functionalKey(modifiers: KeyboardProtocolModifers) -> FunctionalKeyDefinition? {
        switch virtualKeyCode {
        case kVK_Escape:
            return .ESCAPE
        case kVK_Return:
            return .ENTER
        case kVK_Tab:
            return .TAB
        case kVK_Delete:
            return .BACKSPACE
        case kVK_Help:
            return .INSERT
        case kVK_Delete:
            return .DELETE
        case kVK_LeftArrow:
            return .LEFT
        case kVK_RightArrow:
            return .RIGHT
        case kVK_UpArrow:
            return .UP
        case kVK_DownArrow:
            return .DOWN
        case kVK_PageUp:
            return .PAGE_UP
        case kVK_PageDown:
            return .PAGE_DOWN
        case kVK_Home:
            return .HOME
        case kVK_End:
            return .END
        case kVK_CapsLock:
            return .CAPS_LOCK
        case kVK_F1:
            return .F1
        case kVK_F2:
            return .F2
        case kVK_F3:
            return .F3
        case kVK_F4:
            return .F4
        case kVK_F5:
            return .F5
        case kVK_F6:
            return .F6
        case kVK_F7:
            return .F7
        case kVK_F8:
            return .F8
        case kVK_F9:
            return .F9
        case kVK_F10:
            return .F10
        case kVK_F11:
            return .F11
        case kVK_F12:
            return .F12
        case kVK_F13:
            return .F13
        case kVK_F14:
            return .F14
        case kVK_F15:
            return .F15
        case kVK_F16:
            return .F16
        case kVK_F17:
            return .F17
        case kVK_F18:
            return .F18
        case kVK_F19:
            return .F19
        case kVK_F20:
            return .F20
        case kVK_ANSI_Keypad0:
            if modifiers.contains(.num_lock) {
                return .KP_INSERT
            }
            return .KP_0
        case kVK_ANSI_Keypad1:
            if modifiers.contains(.num_lock) {
                return .KP_END
            }
            return .KP_1
        case kVK_ANSI_Keypad2:
            if modifiers.contains(.num_lock) {
                return .KP_DOWN
            }
            return .KP_2
        case kVK_ANSI_Keypad3:
            if modifiers.contains(.num_lock) {
                return .KP_PAGE_DOWN
            }
            return .KP_3
        case kVK_ANSI_Keypad4:
            if modifiers.contains(.num_lock) {
                return .KP_LEFT
            }
            return .KP_4
        case kVK_ANSI_Keypad5:
            return .KP_5
        case kVK_ANSI_Keypad6:
            if modifiers.contains(.num_lock) {
                return .KP_RIGHT
            }
            return .KP_6
        case kVK_ANSI_Keypad7:
            if modifiers.contains(.num_lock) {
                return .KP_HOME
            }
            return .KP_7
        case kVK_ANSI_Keypad8:
            if modifiers.contains(.num_lock) {
                return .KP_UP
            }
            return .KP_8
        case kVK_ANSI_Keypad9:
            if modifiers.contains(.num_lock) {
                return .KP_PAGE_UP
            }
            return .KP_9
        case kVK_ANSI_KeypadDecimal:
            if modifiers.contains(.num_lock) {
                return .KP_DELETE
            }
            return .KP_DECIMAL
        case kVK_ANSI_KeypadDivide:
            return .KP_DIVIDE
        case kVK_ANSI_KeypadMultiply:
            return .KP_MULTIPLY
        case kVK_ANSI_KeypadMinus:
            return .KP_SUBTRACT
        case kVK_ANSI_KeypadPlus:
            return .KP_ADD
        case kVK_ANSI_KeypadEnter:
            return .KP_ENTER
        case kVK_ANSI_KeypadEquals:
            return .KP_EQUAL
        case kVK_ANSI_KeypadClear:
            return .KP_SEPARATOR  // This is a blind guess
        case kVK_RightShift:
            return .RIGHT_SHIFT
        case kVK_RightControl:
            return .RIGHT_CONTROL
        case kVK_RightOption:
            return .RIGHT_ALT
        case kVK_RightCommand:
            return .RIGHT_SUPER

        default:
            return nil
        }
    }

    private func csiU(enhancementFlags: VT100TerminalKeyReportingFlags) -> EncodedKeypress {
        let exceptions = [UnicodeScalar("\n").value,
                          UnicodeScalar("\r").value,
                          UnicodeScalar("\t").value]
        if type == .release && exceptions.contains(unicodeKeyCode) && !enhancementFlags.contains(.reportAllKeysAsEscapeCodes) {
            // The Enter, Tab and Backspace keys will not have release events unless Report all
            // keys as escape codes is also set, so that the user can still type reset at a
            // shell prompt when a program that sets this mode ends without resetting it.
            return .nonReportable
        }
        // The central escape code used to encode key events is:
        //   CSI unicode-key-code:alternate-key-codes ; modifiers:event-type ; text-as-codepoints u
        struct ControlSequence {
            struct Parameter {
                var values: [UInt32?]
                var encoded: String {
                    values.map { $0.map { String($0) } ?? "" }.joined(separator: ":")
                }
            }
            var pre = "\u{1B}["
            var parameters = [Parameter]()
            var post = "u"

            var encoded: String {
                return pre + parameters.map { $0.encoded }.joined(separator: ";") + post
            }
        }

        // Number (unicode-key-code:alternate-key-codes)
        let numberComponents = if enhancementFlags.contains(.reportAlternateKeys) {
            [unicodeKeyCode, shiftedKeyCode, baseLayoutKeyCode]
        } else {
            [unicodeKeyCode]
        }
        var controlSequence = ControlSequence()
        if let functional = functionalKey(modifiers: modifiers),
           let suffix = functional.rawValue.last {
            controlSequence.post = String(suffix)
            if ["u", "~"].contains(suffix) {
                // CSI number ; modifiers [u~]
                // The number in the first form above will be either the Unicode codepoint for a
                // key, such as 97 for the a key, or one of the numbers from the Functional key
                // definitions table below. The modifiers optional parameter encodes any
                // modifiers active for the key event. The encoding is described in the
                // Modifiers section.
                controlSequence.parameters.append(.init(values: numberComponents))
            } else {
                // CSI 1; modifiers [ABCDEFHPQS]
                // The second form is used for a few functional keys, such as the Home, End,
                // Arrow keys and F1 … F4, they are enumerated in the Functional key definitions
                // table below. Note that if no modifiers are present the parameters are omitted
                // entirely giving an escape code of the form CSI [ABCDEFHPQS].
                controlSequence.parameters.append(.init(values: [1]))
            }
        } else {
            // See note above about `CSI number ; modifiers [u~]` form.
            controlSequence.parameters.append(.init(values: numberComponents))
        }

        // Modifiers (modifiers:event-type)
        controlSequence.parameters.append(.init(values: []))
        if let encodedType = type.encoded {
            controlSequence.parameters[controlSequence.parameters.count - 1].values.insert(encodedType, at: 0)
        }
        controlSequence.parameters[controlSequence.parameters.count - 1].values.insert(modifiers.encoded, at: 0)

        // Associated values (text-as-codepoints)
        if enhancementFlags.contains(.reportAssociatedText) {
            controlSequence.parameters.append(.init(values: textAsCodepoints))
        }

        return .string(controlSequence.encoded)
    }
}

enum FunctionalKeyDefinition: String {
    case ESCAPE="27u"
    case ENTER="13u"
    case TAB="9u"
    case BACKSPACE="127u"
    case INSERT="2~"
    case DELETE="3~"
    case LEFT="D"
    case RIGHT="C"
    case UP="A"
    case DOWN="B"
    case PAGE_UP="5~"
    case PAGE_DOWN="6~"
    case HOME="7~"
    case END="8~"
    case CAPS_LOCK="57358u"
    case SCROLL_LOCK="57359u"  // no virtual keycode for this
    case NUM_LOCK="57360u"  // no virtual keycode for this
    case PRINT_SCREEN="57361u"  // no virtual keycode for this
    case PAUSE="57362u"  // no virtual keycode for this
    case MENU="57363u"  // no virtual keycode for this
    case F1="11~"
    case F2="12~"
    case F3="13~"
    case F4="14~"
    case F5="15~"
    case F6="17~"
    case F7="18~"
    case F8="19~"
    case F9="20~"
    case F10="21~"
    case F11="23~"
    case F12="24~"
    case F13="57376u"
    case F14="57377u"
    case F15="57378u"
    case F16="57379u"
    case F17="57380u"
    case F18="57381u"
    case F19="57382u"
    case F20="57383u"
    case F21="57384u"  // no virtual keycode for this
    case F22="57385u"  // no virtual keycode for this
    case F23="57386u"  // no virtual keycode for this
    case F24="57387u"  // no virtual keycode for this
    case F25="57388u"  // no virtual keycode for this
    case F26="57389u"  // no virtual keycode for this
    case F27="57390u"  // no virtual keycode for this
    case F28="57391u"  // no virtual keycode for this
    case F29="57392u"  // no virtual keycode for this
    case F30="57393u"  // no virtual keycode for this
    case F31="57394u"  // no virtual keycode for this
    case F32="57395u"  // no virtual keycode for this
    case F33="57396u"  // no virtual keycode for this
    case F34="57397u"  // no virtual keycode for this
    case F35="57398u"  // no virtual keycode for this
    case KP_0="57399u"
    case KP_1="57400u"
    case KP_2="57401u"
    case KP_3="57402u"
    case KP_4="57403u"
    case KP_5="57404u"
    case KP_6="57405u"
    case KP_7="57406u"
    case KP_8="57407u"
    case KP_9="57408u"
    case KP_DECIMAL="57409u"
    case KP_DIVIDE="57410u"
    case KP_MULTIPLY="57411u"
    case KP_SUBTRACT="57412u"
    case KP_ADD="57413u"
    case KP_ENTER="57414u"
    case KP_EQUAL="57415u"
    case KP_SEPARATOR="57416u"  // not sure what this is meant to be
    case KP_LEFT="57417u"
    case KP_RIGHT="57418u"
    case KP_UP="57419u"
    case KP_DOWN="57420u"
    case KP_PAGE_UP="57421u"
    case KP_PAGE_DOWN="57422u"
    case KP_HOME="57423u"
    case KP_END="57424u"
    case KP_INSERT="57425u"
    case KP_DELETE="57426u"
    case KP_BEGIN="57427~"  // no virtual keycode for this
    case MEDIA_PLAY="57428u"  // no virtual keycode for this
    case MEDIA_PAUSE="57429u"  // no virtual keycode for this
    case MEDIA_PLAY_PAUSE="57430u"  // no virtual keycode for this
    case MEDIA_REVERSE="57431u"  // no virtual keycode for this
    case MEDIA_STOP="57432u"  // no virtual keycode for this
    case MEDIA_FAST_FORWARD="57433u"  // no virtual keycode for this
    case MEDIA_REWIND="57434u"  // no virtual keycode for this
    case MEDIA_TRACK_NEXT="57435u"  // no virtual keycode for this
    case MEDIA_TRACK_PREVIOUS="57436u"  // no virtual keycode for this
    case MEDIA_RECORD="57437u"  // no virtual keycode for this
    case LOWER_VOLUME="57438u"  // no virtual keycode for this
    case RAISE_VOLUME="57439u"  // no virtual keycode for this
    case MUTE_VOLUME="57440u"  // no virtual keycode for this
    case LEFT_SHIFT="57441u"
    case LEFT_CONTROL="57442u"
    case LEFT_ALT="57443u"
    case LEFT_SUPER="57444u"
    case LEFT_HYPER="57445u"
    case LEFT_META="57446u"
    case RIGHT_SHIFT="57447u"
    case RIGHT_CONTROL="57448u"
    case RIGHT_ALT="57449u"
    case RIGHT_SUPER="57450u"
    case RIGHT_HYPER="57451u"  // no virtual keycode for this
    case RIGHT_META="57452u"  // no virtual keycode for this
    case ISO_LEVEL3_SHIFT="57453u"  // no virtual keycode for this
    case ISO_LEVEL5_SHIFT="57454u"  // no virtual keycode for this
}

extension OptionSet where RawValue == UInt {
    func map<T>(_ closure: (Self) throws -> (T)) rethrows -> [T] {
        var result = [T]()
        for i in 0..<UInt.bitWidth {
            let value = UInt(1) << UInt(i)
            if (rawValue & value) != 0 {
                result.append(try closure(Self(rawValue: value)))
            }
        }
        return result
    }
}

fileprivate extension CharacterSet {
    func contains(codePoint: UInt32) -> Bool {
        guard let scalar = Unicode.Scalar(codePoint) else {
            return false
        }
        return contains(scalar)
    }
}
