//
//  VimKeyParser.swift
//  iTerm2
//
//  Created by George Nachman on 4/2/25.
//

import AppKit
import Carbon

@objc(iTermVimKeyParser)
final class VimKeyParser: NSObject {
    private let input: String
    private var currentIndex: String.Index

    @objc let errorDomain = "com.iterm2.vim-key-parser"
    @objc let invalidRangeErrorKey = "InvalidRange"

    @objc enum ErrorCode: Int {
        case missingClosingBracket
        case invalidKey

        func localizedDescription(_ arg: String?,
                                  range: NSRange,
                                  input: String) -> String {
            let problem = switch self {
            case .missingClosingBracket:
                "Missing closing '>'"
            case .invalidKey:
                "Invalid key: <\(arg.d)>"
            }

            return "\(problem) at index \(range.location) in \(input)"
        }
    }

    @objc(initWithString:)
    init(_ input: String) {
        self.input = input
        currentIndex = self.input.startIndex
    }

    /// Parses a vim-style key sequence into an array of NSEvent (KeyDown) events.
    ///
    /// - Parameters:
    ///   - input: The string containing the key sequence.
    ///   - error: If parsing fails, upon return contains an NSError describing the invalid range.
    /// - Returns: An array of KeyDown events.
    @discardableResult
    @objc(eventsWithError:)
    func events() throws -> [NSEvent] {
        var events = [NSEvent]()
        currentIndex = input.startIndex

        while currentIndex < input.endIndex {
            let event = switch input[currentIndex] {
            case "<":
                try handleBeginWakeWaka()
            default:
                try handleRegular()
            }
            DLog("Result is \(event.d)")
            if let event {
                events.append(event)
            }
        }
        return events
    }
}

private extension VimKeyParser {
    private func error(code: ErrorCode, arg: String?, range: Range<String.Index>) -> Error {
        let startUTF16 = input.utf16.distance(from: input.utf16.startIndex, to: range.lowerBound)
        let lengthUTF16 = input.utf16.distance(from: range.lowerBound, to: range.upperBound)
        let nsrange = NSRange(location: startUTF16, length: lengthUTF16)
        DLog("ERROR: code=\(code) arg=\(arg.d) range=\(range) input=\(input)")
        return NSError(domain: errorDomain,
                       code: code.rawValue,
                       userInfo: [NSLocalizedDescriptionKey: code.localizedDescription(arg, range: nsrange, input: input),
                                       invalidRangeErrorKey: NSValue(range: nsrange)])
    }

    // Sequence beginning with "<".
    private func handleBeginWakeWaka() throws -> NSEvent? {
        DLog("handleBeginWakeWaka at \(input.distance(from: input.startIndex, to: currentIndex)) of \(input)")
        let tokenStartIndex = currentIndex
        guard let closingIndex = input[tokenStartIndex...].firstIndex(of: ">") else {
            throw error(code: .missingClosingBracket,
                        arg: nil,
                        range: currentIndex..<input.index(after: currentIndex))
        }

        let tokenContents = input[input.index(after: tokenStartIndex)..<closingIndex]
        let token = String(tokenContents)
        if let parsed = parseToken(token) {
            currentIndex = input.index(after: closingIndex)
            let event = NSEvent.keyEvent(with: .keyDown,
                                         location: .zero,
                                         modifierFlags: parsed.modifierFlags,
                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: 0,
                                         context: nil,
                                         characters: parsed.characters,
                                         charactersIgnoringModifiers: parsed.characters,
                                         isARepeat: false,
                                         keyCode: parsed.keyCode)
            return event
        }
        throw error(code: .invalidKey, arg: token, range: tokenStartIndex..<closingIndex)
    }

    // Literal character
    private func handleRegular() throws -> NSEvent? {
        let char = input[currentIndex]
        DLog("handleRegular for \(char)")
        currentIndex = input.index(after: currentIndex)
        return NSEvent.keyDown(forCharacter: char)
    }

    private func parseToken(_ token: String) -> (characters: String, modifierFlags: NSEvent.ModifierFlags, keyCode: UInt16)? {
        var modifierFlags: NSEvent.ModifierFlags = []
        var baseKey = token

        // Check for modifier prefixes separated by '-'
        let parts = token.split(separator: "-")
        if parts.count > 1 {
            for part in parts.dropLast() {
                switch part {
                case "S":
                    modifierFlags.insert(.shift)
                case "C", "c":
                    modifierFlags.insert(.control)
                case "M", "A":
                    modifierFlags.insert(.option)
                case "D":
                    modifierFlags.insert(.command)
                default:
                    return nil
                }
            }
            baseKey = String(parts.last!)
        }

        // This comes from `:help <>` in vim
        let baseMapping: [String: (String, UInt16)] = [
            "BS":     ("\u{8}", UInt16(kVK_Delete)),
            "Tab":    ("\t", UInt16(kVK_Tab)),
            "NL":     ("\r", UInt16(kVK_Return)),
            "CR":     ("\r", UInt16(kVK_Return)),
            "Return": ("\r", UInt16(kVK_Return)),
            "Enter":  ("\r", UInt16(kVK_Return)),
            "Esc":    ("\u{1B}", UInt16(kVK_Escape)),
            "Space":  (" ", UInt16(kVK_Space)),
            "lt":     ("<", UInt16(kVK_ANSI_Period)),
            "Bslash": ("\\", UInt16(kVK_ANSI_Backslash)),
            "Bar":    ("|", UInt16(kVK_ANSI_Backslash)),
            "Del":    ("", UInt16(kVK_ForwardDelete)),
            "EOL":    ("\r", UInt16(kVK_Return)),
            "Up":     (String(UnicodeScalar(NSUpArrowFunctionKey)!), UInt16(kVK_UpArrow)),
            "Down":   (String(UnicodeScalar(NSDownArrowFunctionKey)!), UInt16(kVK_DownArrow)),
            "Left":   (String(UnicodeScalar(NSLeftArrowFunctionKey)!), UInt16(kVK_LeftArrow)),
            "Right":  (String(UnicodeScalar(NSRightArrowFunctionKey)!), UInt16(kVK_RightArrow)),
            "F1":     (String(UnicodeScalar(NSF1FunctionKey)!), UInt16(kVK_F1)),
            "F2":     (String(UnicodeScalar(NSF2FunctionKey)!), UInt16(kVK_F2)),
            "F3":     (String(UnicodeScalar(NSF3FunctionKey)!), UInt16(kVK_F3)),
            "F4":     (String(UnicodeScalar(NSF4FunctionKey)!), UInt16(kVK_F4)),
            "F5":     (String(UnicodeScalar(NSF5FunctionKey)!), UInt16(kVK_F5)),
            "F6":     (String(UnicodeScalar(NSF6FunctionKey)!), UInt16(kVK_F6)),
            "F7":     (String(UnicodeScalar(NSF7FunctionKey)!), UInt16(kVK_F7)),
            "F8":     (String(UnicodeScalar(NSF8FunctionKey)!), UInt16(kVK_F8)),
            "F9":     (String(UnicodeScalar(NSF9FunctionKey)!), UInt16(kVK_F9)),
            "F10":    (String(UnicodeScalar(NSF10FunctionKey)!), UInt16(kVK_F10)),
            "F11":    (String(UnicodeScalar(NSF11FunctionKey)!), UInt16(kVK_F11)),
            "F12":    (String(UnicodeScalar(NSF12FunctionKey)!), UInt16(kVK_F12)),
            "Insert": ("", UInt16(kVK_Help)),
            "Home":   ("", UInt16(kVK_Home)),
            "End":    ("", UInt16(kVK_End)),
            "PageUp": ("", UInt16(kVK_PageUp)),
            "PageDown": ("", UInt16(kVK_PageDown))
        ]

        let keypadMapping: [String: (String, UInt16)] = [
            "kPlus":     ("+", UInt16(kVK_ANSI_KeypadPlus)),
            "kMinus":    ("-", UInt16(kVK_ANSI_KeypadMinus)),
            "kMultiply": ("*", UInt16(kVK_ANSI_KeypadMultiply)),
            "kDivide":   ("/", UInt16(kVK_ANSI_KeypadDivide)),
            "kEnter":    ("\r", UInt16(kVK_ANSI_KeypadEnter)),
            "kPoint":    (".", UInt16(kVK_ANSI_KeypadDecimal)),
            "k0":        ("0", UInt16(kVK_ANSI_Keypad0)),
            "k1":        ("1", UInt16(kVK_ANSI_Keypad1)),
            "k2":        ("2", UInt16(kVK_ANSI_Keypad2)),
            "k3":        ("3", UInt16(kVK_ANSI_Keypad3)),
            "k4":        ("4", UInt16(kVK_ANSI_Keypad4)),
            "k5":        ("5", UInt16(kVK_ANSI_Keypad5)),
            "k6":        ("6", UInt16(kVK_ANSI_Keypad6)),
            "k7":        ("7", UInt16(kVK_ANSI_Keypad7)),
            "k8":        ("8", UInt16(kVK_ANSI_Keypad8)),
            "k9":        ("9", UInt16(kVK_ANSI_Keypad9))
        ]

        if let mapping = baseMapping[baseKey] {
            return (mapping.0, modifierFlags, mapping.1)
        }
        if let mapping = keypadMapping[baseKey] {
            return (mapping.0, modifierFlags, mapping.1)
        }
        if baseKey.count == 1 {
            return (baseKey, modifierFlags, 0)
        }
        return nil
    }
}

fileprivate struct CarbonKeystroke {
    var keyCode: UInt16
    var modifiers: UInt32
}

// Input source (e.g., com.apple.US) -> String produced (e.g., "G") -> CarbonKeystroke that produces that key (e.g., (kVK_ANSI_G, shiftKey))
fileprivate var cachedKeystrokeToStringMapping = [String: [String: CarbonKeystroke]]()

fileprivate func currentInputSourceID() -> String {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
        return ""
    }
    let cfSourceID = unsafeBitCast(TISGetInputSourceProperty(source, kTISPropertyInputSourceID), to: CFString.self)
    return cfSourceID as String
}

func keyCodeIsOnKeypad(keyCode: UInt16) -> Bool {
    switch Int(keyCode) {
    case kVK_ANSI_KeypadDecimal, kVK_ANSI_KeypadMultiply, kVK_ANSI_KeypadPlus, kVK_ANSI_KeypadClear,
        kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadEnter, kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadEquals,
        kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4,
        kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9:
        true
    default:
        false
    }
}

extension NSEvent {
    fileprivate static func productionToCarbonKeystrokeDictionary(forInputSourceID sourceID: String) -> [String: CarbonKeystroke] {
        let sourceID = currentInputSourceID()

        if let dict = cachedKeystrokeToStringMapping[sourceID] {
            return dict
        }

        DLog("Build production to keystroke map for input source \(sourceID)")
        let modifierCombinations: [UInt32] = [0, UInt32(shiftKey), UInt32(optionKey), UInt32(shiftKey | optionKey)]
        var dict = [String: CarbonKeystroke]()
        for modifier in modifierCombinations {
            let maxKeyCode: UInt16 = 127
            for keyCode in 0...maxKeyCode {
                if let produced = NSEvent.stringForKey(withKeycode: keyCode, modifiers: modifier) {
                    let carbonKeystroke = CarbonKeystroke(keyCode: keyCode, modifiers: modifier)
                    if let existing = dict[produced] {
                        if keyCodeIsOnKeypad(keyCode: keyCode) && !keyCodeIsOnKeypad(keyCode: existing.keyCode) {
                            // Prefer non-keypad to keypad
                            continue
                        }
                        if existing.keyCode == keyCode && existing.modifiers.nonzeroBitCount <= modifier.nonzeroBitCount {
                            // Prefer fewer modifiers
                            continue
                        }
                    }
                    dict[produced] = carbonKeystroke
                }
            }
        }
        DLog("\(dict)")
        cachedKeystrokeToStringMapping[sourceID] = dict
        return dict
    }
    
    fileprivate static func carbonKeystroke(toProduce desired: String) -> CarbonKeystroke? {
        let dict = productionToCarbonKeystrokeDictionary(forInputSourceID: currentInputSourceID())
        return dict[desired]
    }

    // Helper function that converts a literal character into an NSEvent with the correct key code and modifier flags
    static func keyDown(forCharacter char: Character) -> NSEvent? {
        DLog("char=\(char)")
        let string = String(char)

        guard let carbonKeystroke = carbonKeystroke(toProduce: string) else {
            DLog("No carbon keystroke for \(string) so use fallback")
            return NSEvent.keyEvent(with: .keyDown,
                                    location: .zero,
                                    modifierFlags: [],
                                    timestamp: ProcessInfo.processInfo.systemUptime,
                                    windowNumber: 0,
                                    context: nil,
                                    characters: string,
                                    charactersIgnoringModifiers: string,
                                    isARepeat: false,
                                    keyCode: 0)
        }
        DLog("carbonKeystroke=\(carbonKeystroke)")

        var flags: NSEvent.ModifierFlags = []
        if carbonKeystroke.modifiers & UInt32(shiftKey) != 0 {
            flags.insert(.shift)
        }
        if carbonKeystroke.modifiers & UInt32(controlKey) != 0 {
            flags.insert(.control)
        }
        if carbonKeystroke.modifiers & UInt32(optionKey) != 0 {
            flags.insert(.option)
        }
        if carbonKeystroke.modifiers & UInt32(cmdKey) != 0 {
            flags.insert(.command)
        }

        return NSEvent.keyEvent(with: .keyDown,
                                location: .zero,
                                modifierFlags: flags,
                                timestamp: ProcessInfo.processInfo.systemUptime,
                                windowNumber: 0,
                                context: nil,
                                characters: string,
                                charactersIgnoringModifiers: string,
                                isARepeat: false,
                                keyCode: carbonKeystroke.keyCode)
    }
}
