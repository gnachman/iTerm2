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

extension VT100TerminalKeyReportingFlags: Codable {
    enum CodingKeys: String, CodingKey {
        case rawValue
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.rawValue, forKey: .rawValue)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(UInt.self, forKey: .rawValue)
        self = Self(rawValue: Int32(rawValue))
    }
}

extension NSEvent.EventType: Codable {
    enum CodingKeys: String, CodingKey {
        case rawValue
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.rawValue, forKey: .rawValue)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(UInt.self, forKey: .rawValue)
        guard let eventType = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(forKey: .rawValue, in: container, debugDescription: "Invalid event type")
        }
        self = eventType
    }
}

extension NSEvent.ModifierFlags: Codable {
    enum CodingKeys: String, CodingKey {
        case rawValue
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.rawValue, forKey: .rawValue)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(UInt.self, forKey: .rawValue)
        self = Self(rawValue: rawValue)
    }
}

fileprivate struct KeyEventInfo: CustomDebugStringConvertible, Codable {
    var debugDescription: String {
        return "<KeyEventInfo: type=\(eventType) modifiers=\(modifierFlags) keyCode=\(virtualKeyCode) characters=\(characters ?? "") charactersIgnoringModifiers=\(charactersIgnoringModifiers ?? "")>"
    }
    var eventType: NSEvent.EventType
    var previousFlags: NSEvent.ModifierFlags
    var modifierFlags: NSEvent.ModifierFlags
    var virtualKeyCode: UInt16  // kVK…
    var characters: String?
    var charactersIgnoringModifiers: String?
    var isARepeat: Bool

    // associated with key, so 97 for shift-A; for function keys, use private
    // use values. Can be 0 for some function keys that don't have private use values.
    var unicodeKeyCode: UInt32

    // The number to use for CSI u reports. This is separate from
    // unicodeKeyCode to disambiguate things like function keys, whose numbers
    // are not unicode keycodes. Otherwise it's about the same.
    var csiUNumber: UInt32

    // uppercase/shifted version of unicodeKeyCode (65 for shift-A)
    var shiftedKeyCode: UInt32?

    // keycode for physical key on PC-101 (so 97 for ф on a Russian keyboard
    // because that's A on a US keyboard)
    var baseLayoutKeyCode: UInt32
    var textAsCodepoints: [UInt32]

    var nsevent: NSEvent? {
        return NSEvent.keyEvent(with: eventType,
                                location: .zero,
                                modifierFlags: modifierFlags,
                                timestamp: Date.timeIntervalSinceReferenceDate,
                                windowNumber: 0,
                                context: nil,
                                characters: characters ?? "",
                                charactersIgnoringModifiers: charactersIgnoringModifiers ?? "",
                                isARepeat: isARepeat,
                                keyCode: virtualKeyCode)
    }

    init(event: NSEvent, 
         configuration: ModernKeyMapperConfiguration,
         flags: VT100TerminalKeyReportingFlags) {
        eventType = event.type
        previousFlags = event.it_previousFlags
        modifierFlags = event.it_modifierFlags

        virtualKeyCode = event.keyCode
        if event.type == .keyDown || event.type == .keyUp {
            characters = event.characters
            charactersIgnoringModifiers = event.charactersIgnoringModifiers
            isARepeat = event.isARepeat
            let leftOptionNormal = configuration.leftOptionKey == .OPT_NORMAL
            let rightOptionNormal = configuration.rightOptionKey == .OPT_NORMAL
            let useNativeOptionBehavior = {
                if flags.contains(.reportAllKeysAsEscapeCodes) {
                    return false
                }
                if event.it_modifierFlags.contains(.leftOption) && leftOptionNormal {
                    return true
                }
                if event.it_modifierFlags.contains(.rightOption) && rightOptionNormal {
                    return true
                }
                return false
            }()
            unicodeKeyCode = event.it_unicodeKeyCode(
                useNativeOptionBehavior: useNativeOptionBehavior)
            csiUNumber = event.it_csiUNumber(useNativeOptionBehavior: useNativeOptionBehavior)
            shiftedKeyCode = event.it_shiftedKeyCode(
                useNativeOptionBehavior: useNativeOptionBehavior)
            baseLayoutKeyCode = event.it_baseLayoutKeyCode

            let textUsesNativeOptionBehavior = 
                if event.it_modifierFlags.contains(.leftOption) &&
                    leftOptionNormal {
                    true
                } else if event.it_modifierFlags.contains(.rightOption) &&
                            rightOptionNormal {
                    true
                } else {
                    false
                }
            textAsCodepoints = event.it_textAsCodePoints(
                useNativeOptionBehavior: textUsesNativeOptionBehavior)
        } else {
            characters = ""
            charactersIgnoringModifiers = ""
            isARepeat = false

            switch Int(virtualKeyCode) {
            case kVK_Shift:
                unicodeKeyCode = 57441
            case kVK_RightShift:
                unicodeKeyCode = 57447
            case kVK_Control:
                unicodeKeyCode = 57442
            case kVK_RightControl:
                unicodeKeyCode = 57448
            case kVK_Option:
                unicodeKeyCode = 57443
            case kVK_RightOption:
                unicodeKeyCode = 57449
            case kVK_Command:
                unicodeKeyCode = 57444
            case kVK_RightCommand:
                unicodeKeyCode = 57450
            default:
                unicodeKeyCode = 0
            }
            csiUNumber = unicodeKeyCode
            shiftedKeyCode = nil
            baseLayoutKeyCode = unicodeKeyCode
            textAsCodepoints = []
        }
        DLog(debugDescription)
    }
}

// This is an ObjC and Appkit-aware class that doesn't contain any logic.
// It just removes those dependencies and calls the implementation, which
// is pure swift and barely needs AppKit.
@objc(iTermModernKeyMapper)
class ModernKeyMapper: NSObject, iTermKeyMapper {
    @objc weak var delegate: ModernKeyMapperDelegate? {
        didSet {
            impl.delegate = delegate
        }
    }
    @objc var flags: VT100TerminalKeyReportingFlags {
        get {
            impl.flags
        }
        set {
            impl.flags = newValue
        }
    }

    private let impl = ModernKeyMapperImpl()

    var keyMapperWantsKeyUp: Bool {
        return impl.keyMapperWantsKeyUp
    }

    // Process it immediately in the delegate? If you return true IME doesn't get a chance at this.
    func keyMapperShouldBypassPreCocoa(for nsevent: NSEvent) -> Bool {
        DLog("keyMapperShouldBypassPreCocoa \(nsevent)")
        let event = updateConfiguration(event: nsevent)
        let result = impl.keyMapperShouldBypassPreCocoa(for: event)
        DLog("return \(result)")
        return result
    }

    // flagsChanged takes only this path.
    func keyMapperString(forPreCocoaEvent nsevent: NSEvent) -> String? {
        DLog("keyMapperString(forPreCocoaEvent \(nsevent)")
        let event = updateConfiguration(event: nsevent)
        let result = impl.keyMapperString(forPreCocoaEvent: event)
        DLog("return \(result?.debugDescription ?? "nil")")
        return result
    }

    func keyMapperData(forPostCocoaEvent nsevent: NSEvent) -> Data? {
        DLog("keyMapperData(forPostCocoaEvent \(nsevent)")
        let event = updateConfiguration(event: nsevent)
        let result = impl.keyMapperData(forPostCocoaEvent: event)
        DLog("return \(result?.debugDescription ?? "nil")")
        return result
    }

    func keyMapperSetEvent(_ nsevent: NSEvent) {
        DLog("keyMapperSetEvent \(nsevent)")
        let event = updateConfiguration(event: nsevent)
        impl.keyMapperSetEvent(event)
    }

    func keyMapperWantsKeyEquivalent(_ nsevent: NSEvent) -> Bool {
        DLog("keyMapperWantsKeyEquivalent \(nsevent)")
        // Let command-key behave normally. Otherwise, we'll take it. For example,
        // control-shift-arrow takes this path.
        let event = updateConfiguration(event: nsevent)
        let result = impl.keyMapperWantsKeyEquivalent(event)
        DLog("return \(result)")
        return result
    }

    func keyMapperDictionaryValue() -> [AnyHashable : Any] {
        DLog("keyMapperDictionaryValue")
        let result = impl.keyMapperDictionaryValue()
        DLog("return \(result)")
        return result
    }

    func wouldReportControlReturn() -> Bool {
        return !flags.intersection([.reportAllEventTypes, .reportAllKeysAsEscapeCodes]).isEmpty
    }

    func keyMapperData(forKeyUp nsevent: NSEvent) -> Data? {
        DLog("keyMapperData(forKeyUp \(nsevent)")
        let event = updateConfiguration(event: nsevent)
        let result = impl.keyMapperData(forKeyUp: event)
        DLog("return \(result?.debugDescription ?? "nil")")
        return result
    }

    private func updateConfiguration(event: NSEvent) -> KeyEventInfo {
        let configuration =
            if let delegate {
                delegate.modernKeyMapperWillMapKey().value
            } else {
                ModernKeyMapperConfiguration(leftOptionKey: .OPT_NORMAL,
                                             rightOptionKey: .OPT_NORMAL)
            }
        impl.configuration = configuration
        let eventInfo = KeyEventInfo(event: event,
                                     configuration: configuration,
                                     flags: impl.flags)
        impl.event = eventInfo
        return eventInfo
    }
}

// Public interfaces of the impl that mirror iTermKeyMapper.
fileprivate class ModernKeyMapperImpl {
    var flags = VT100TerminalKeyReportingFlags(rawValue: 0)
    weak var delegate: ModernKeyMapperDelegate?
    var configuration = ModernKeyMapperConfiguration(leftOptionKey: .OPT_NORMAL,
                                                             rightOptionKey: .OPT_NORMAL)
    var event: KeyEventInfo?
    private var lastDeadKey: KeyEventInfo?

    var keyMapperWantsKeyUp: Bool {
        return flags.contains(.reportAllEventTypes)
    }

    func keyMapperSetEvent(_ event: KeyEventInfo) {
        DLog("keyMapperSetEvent \(event)")
        if let report = keyReport(for: event), report.isDeadKey {
            DLog("is dead key")
            lastDeadKey = event
        } else {
            lastDeadKey = nil
        }
    }

    func keyMapperShouldBypassPreCocoa(for event: KeyEventInfo) -> Bool {
        DLog("keyMapperShouldBypassPreCocoa \(event)")

        if NSEvent.it_isFunctionOrNumericKeypad(modifierFlags: event.modifierFlags) {
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

        if NSEvent.it_shouldSendOptionModifiedKey(
            modifierFlags: event.modifierFlags,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            leftOptionConfig: configuration.leftOptionKey,
            rightOptionConfig: configuration.rightOptionKey) {
            // Treating option as Esc+ (or its CSI u equivalent)
            DLog("true: should send option-modified key")
            return true
        }

        if NSEvent.it_isControlCodeWithOption(
            modifierFlags: event.modifierFlags,
            keyCode: event.virtualKeyCode,
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers) {
            // You pressed ctrl-option-[key that sends a control like c or 6]
            // We don't want Cocoa to handle it and call insertText: or performKeyEquivalent:.
            // Note that this is a departure from what the ModifyOtherKeys mapper does.
            // I believe it may be buggy.
            DLog("true: control+option control code")
            return true
        }

        if flags.contains(.reportAllKeysAsEscapeCodes) {
            // We never want it to get to insertText:.
            // This breaks IMEs but I don't see how it could support them. My
            // conclusion is that this is close to a raw mode that deals with
            // physical keys, not input methods.
            DLog("true: reporting all keys as escape codes")
            return true
        }
        return false
    }

    func keyMapperString(forPreCocoaEvent event: KeyEventInfo) -> String? {
        DLog("keyMapperString(forPreCocoaEvent \(event)")
        switch event.eventType {
        case .keyDown:
            DLog("keyDown")
            if event.modifierFlags.contains(.numericPad) {
                DLog("numPad")
                return handle(event: event)?.lossyString
            }
            if event.modifierFlags.intersection([.control, .command, .option]) != [.control] {
                // If you're holding a modifier other than control (and optionally shift) let it go
                // to cocoa. Other keymappers are a little more selective, choosing to handle
                // only valid controls pre-cocoa, but I don't think it matters. I could be wrong.
                DLog("non-control modifier should go to Cocoa")
                return nil
            }
        case .flagsChanged:
            DLog("flags changed")
            break
        default:
            DLog("unexpected event type")
            return nil
        }

        return handle(event: event)?.lossyString
    }

    func keyMapperData(forPostCocoaEvent event: KeyEventInfo) -> Data? {
        DLog("keyMapperData(forPostCocoaEvent \(event)")
        return handle(event: event)
    }

    private func shouldIgnore(event: KeyEventInfo) -> Bool {
        DLog("shouldIgnore \(event)")
        if event.modifierFlags.subtracting(.function) == event.previousFlags.subtracting(.function) {
            DLog("only function changed")
            return true
        }
        let cmdKeycodes = [kVK_Command, kVK_RightCommand]
        return (event.modifierFlags.contains(.command) ||
                cmdKeycodes.contains(Int(event.virtualKeyCode)))
    }

    func keyMapperWantsKeyEquivalent(_ event: KeyEventInfo) -> Bool {
        DLog("keyMapperWantsKeyEquivalent \(event)")
        return !shouldIgnore(event: event)
    }

    func keyMapperDictionaryValue() -> [AnyHashable : Any] {
        return ["flags": NSNumber(value: flags.rawValue)]
    }

    func keyMapperData(forKeyUp event: KeyEventInfo) -> Data? {
        DLog("keyMapperData(forKeyUp \(event)")
        guard keyMapperWantsKeyUp else {
            DLog("Don't want key up")
            return nil
        }
        if lastDeadKey?.virtualKeyCode == event.virtualKeyCode && event.eventType == .keyUp {
            // Ignore KeyUp of dead key. macOS makes it impossible to tell that
            // a key up is of a dead key because it fills in characters with the
            // combining mark the dead key adds.
            DLog("key-up of dead key")
            lastDeadKey = nil
            return nil
        }
        return handle(event: event)
    }
}

// Implementation details.
private extension ModernKeyMapperImpl {
    private var modifiers: KeyboardProtocolModifers {
        return KeyboardProtocolModifers(rawValue: UInt32(flags.rawValue))
    }

    private func handle(event: KeyEventInfo) -> Data? {
        DLog("handle \(event)")
        if shouldIgnore(event: event) {
            DLog("Ignore")
            return nil
        }
        let encoding = delegate?.modernKeyMapperDelegateStringEncoding() ?? String.Encoding.utf8.rawValue
        let s = string(for: event, preCocoa: false)
        if s.isEmpty {
            DLog("Returning nil")
            return nil
        }
        DLog("Returning \(s)")
        return s.data(using: String.Encoding(rawValue: encoding))
    }

    private func modifiersByRemovingOption(
        modifiers original: NSEvent.ModifierFlags,
        leftBehavior: iTermOptionKeyBehavior,
        rightBehavior: iTermOptionKeyBehavior) -> NSEvent.ModifierFlags {
            DLog("original=\(original) left=\(leftBehavior) right=\(rightBehavior)")
            var modifierFlags = original
            var optionCount = (modifierFlags.contains(.leftOption) ? 0 : 1) + (modifierFlags.contains(.rightOption) ? 0 : 1)
            if leftBehavior == .OPT_NORMAL
                && modifierFlags.contains(.leftOption) {
                optionCount -= 1
                modifierFlags.subtract(.leftOption)
            }
            if rightBehavior == .OPT_NORMAL  && modifierFlags.contains(.rightOption) {
                optionCount -= 1
                modifierFlags.subtract(.rightOption)
            }
            if optionCount == 0 {
                modifierFlags.subtract(.option)
            }
            DLog("\(modifierFlags)")
            return modifierFlags
        }

    private func string(for event: KeyEventInfo, preCocoa: Bool) -> String {
        DLog("event=\(event) preCocoa=\(preCocoa)")
        var modifiedEvent = event
        if !flags.contains(.reportAllKeysAsEscapeCodes) {
            DLog("do NOT report all keys as escape codes")
            // If option is treated as a native key, remove it from the event.
            if configuration.leftOptionKey == .OPT_NORMAL &&
                event.virtualKeyCode == kVK_Option {
                DLog("pressed option with normal option behavior")
                return ""
            }
            if configuration.rightOptionKey == .OPT_NORMAL &&
                event.virtualKeyCode == kVK_RightOption {
                DLog("pressed option with normal option behavior")
                return ""
            }
            if event.eventType == .flagsChanged {
                modifiedEvent.modifierFlags = modifiersByRemovingOption(
                    modifiers: event.modifierFlags,
                    leftBehavior: configuration.leftOptionKey,
                    rightBehavior: configuration.rightOptionKey)
                modifiedEvent.previousFlags = modifiersByRemovingOption(
                    modifiers: event.previousFlags,
                    leftBehavior: configuration.leftOptionKey,
                    rightBehavior: configuration.rightOptionKey)
            }
        }
        guard let report = keyReport(for: modifiedEvent) else {
            DLog("no key report")
            return ""
        }
        switch report.encoded(enhancementFlags: flags) {
        case .fallbackToAmbiguous:
            DLog("encode returned fallbackToAmbiguous")
            return ambiguousString(keyReport: report,
                                   preCocoa: preCocoa,
                                   event: modifiedEvent)
        case .nonReportable:
            DLog("encode returned nonReportable")
            return ""
        case .string(let value):
            DLog("encode returned \(value)")
            return value
        }
    }
    private func keyReport(for event: KeyEventInfo) -> KeyReport? {
        switch event.eventType {
        case .keyDown:
            return regularReport(type: .press, event: event)
        case .keyUp:
            if !flags.contains(.reportAllEventTypes) {
                DLog("Ignoring key-up when not reporting all event types")
                return nil
            }
            return regularReport(type: .release, event: event)
        case .flagsChanged:
            if !flags.contains(.reportAllKeysAsEscapeCodes) {
                DLog("Ignore flags changed when not reporting all keys as escape codes")
                return nil
            }
            let mask: NSEvent.ModifierFlags = [
                .shift, .control, .option, .command, .leftOption, .rightOption]
            let before = event.previousFlags.intersection(mask)
            let after = event.modifierFlags.intersection(mask)
            let pressed = after.subtracting(before)
            let isRelease = pressed.isEmpty
            if isRelease && !flags.contains(.reportAllEventTypes) {
                // This progressive enhancement (0b10) causes the terminal to
                // report key repeat and key release events.
                DLog("Ignoring flags-changed on release without report all event types")
                return nil
            }
            return KeyReport(type: isRelease ? .release : .press,
                             event: event,
                             modifiers: KeyboardProtocolModifers(
                                event,
                                leftOptionNormal: leftOptionNormal,
                                rightOptionNormal: rightOptionNormal))
        default:
            DLog("Unexpected event type \(event.eventType)")
            return nil
        }
    }

    private func regularReport(type: KeyReport.EventType, event: KeyEventInfo) -> KeyReport {
        let modifiers = KeyboardProtocolModifers(
            event,
            leftOptionNormal: leftOptionNormal,
            rightOptionNormal: rightOptionNormal)
        return KeyReport(type: type,
                         event: event,
                         modifiers: modifiers)
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

    private var leftOptionNormal: Bool {
        if flags.contains(.reportAllKeysAsEscapeCodes) {
            return false
        }
        return configuration.leftOptionKey == .OPT_NORMAL
    }

    private var rightOptionNormal: Bool {
        if flags.contains(.reportAllKeysAsEscapeCodes) {
            return false
        }
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

    private func ambiguousString(keyReport: KeyReport,
                                 preCocoa: Bool,
                                 event: KeyEventInfo) -> String {
        if keyReport.event.eventType == .flagsChanged {
            DLog("Empty ambiguous string for flagsChanged")
            return ""
        }
        if keyReport.type == .release {
            DLog("Empty ambiguous string for release")
            return ""
        }
        guard let nsevent = event.nsevent else {
            DLog("Empty ambiguous string for nil event")
            return ""
        }
        DLog("Send to standard mapper")
        let mapper = iTermStandardKeyMapper()
        mapper.delegate = delegate
        mapper.keyMapperSetEvent(nsevent)

        let data = if preCocoa {
            mapper.keyMapperData(forPostCocoaEvent: nsevent)
        } else {
            mapper.keyMapperData(forPostCocoaEvent: nsevent)
        }
        DLog("Result is \(data?.lossyString ?? "")")
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

    var encoded: UInt32 {
        if rawValue == 0 {
            return 1
        }
        return rawValue + 1
    }
}

extension KeyboardProtocolModifers {
    init(_ event: KeyEventInfo,
         leftOptionNormal: Bool,
         rightOptionNormal: Bool) {
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
    var event: KeyEventInfo
    var modifiers: KeyboardProtocolModifers  // won't include alt if alt has native functionality (i.e., not esc+)
    private var numpad: Bool {
        event.modifierFlags.contains(.numericPad)
    }

    private let csi = "\u{001B}["

    init(type: EventType, 
         event: KeyEventInfo,
         modifiers: KeyboardProtocolModifers) {
        self.type = type
        self.event = event
        self.modifiers = modifiers
    }

    private var eligibleForCSI: Bool {
        if !modifiers.isEmpty {
            return true
        }
        return ![UInt32("\r"),
                 UInt32("\t"),
                 UInt32(0x7f)].contains(event.unicodeKeyCode)
    }

    private var legacyUnderDisambiguateEscape: EncodedKeypress {
        DLog("legacyUnderDisambiguateEscape")
        let onlyLegacyCompatibleModifiers = modifiers.subtracting([.ctrl, .shift, .num_lock, .caps_lock]).isEmpty
        if !onlyLegacyCompatibleModifiers {
            DLog("Non-legacy compatible modifiers found")
            return .nonReportable
        }

        // Turning on this flag will cause the terminal to report the Esc, alt+key, ctrl+key,
        // ctrl+alt+key, shift+alt+key keys using CSI u sequences instead of legacy ones.
        // Here key is any ASCII key as described in Legacy text keys. 
        if event.unicodeKeyCode == 27 {
            // esc must be reported with CSI u
            DLog("Is esc")
            return .nonReportable
        }
        let nonLockModifiers = modifiers.subtracting([.caps_lock, .num_lock])
        guard nonLockModifiers == [] else {
            // keys with reportable modifiers must be reported with CSI u
            DLog("no nonlock modifiers")
            return .nonReportable
        }

        // Additionally, all keypad keys will be reported as separate keys with CSI u
        // encoding, using dedicated numbers from the table below.
        if numpad {
            DLog("numpad")
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
        // However, Kitty's implementation also allows backspace (but not delete-forwards) through.
        // I am interpreting this as referring to the unicode-key-code.
        // I am not confident this will work well with non-US keyboards.
        let sets = [CharacterSet(charactersIn: Unicode.Scalar("a")...Unicode.Scalar("z")),
                    CharacterSet(charactersIn: Unicode.Scalar("0")...Unicode.Scalar("9")),
                    CharacterSet(charactersIn: "`-=[]\\;',./"),
                    CharacterSet(charactersIn: "\n\r\t")]
        let legacyKeys = sets.reduce(CharacterSet()) {
            $0.union($1)
        }
        if !legacyKeys.contains(codePoint: event.unicodeKeyCode) && !isBackspace(event) {
            DLog("keycode nonlegacy")
            return .nonReportable
        }

        DLog("Return \(event.characters ?? "")")
        return .string(event.characters ?? "")
    }

    private func isBackspace(_ event: KeyEventInfo) -> Bool {
        if event.unicodeKeyCode != 0x7f {
            return false
        }
        guard let chars = event.charactersIgnoringModifiers else {
            return false
        }
        guard let firstChar = chars.it_firstUnicodeScalarValue else {
            return false
        }
        let result = Int(firstChar) != NSDeleteFunctionKey
        DLog("isBackspace=\(result)")
        return result
    }

    private var legacyControl: String? {
        let code = switch event.characters {
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

    private func shouldUseCSIuForRepeat(_ enhancementFlags: VT100TerminalKeyReportingFlags) -> Bool {
        guard enhancementFlags.contains(.reportAllEventTypes) else {
            DLog("No CSI u for repeat because we want to report all event types")
            return false
        }
        if enhancementFlags.contains(.reportAllKeysAsEscapeCodes) {
            DLog("Use CSI u for repeat because report all keys as escape codes")
            return true
        }
        switch FunctionalKeyDefinition(virtualKeyCode: event.virtualKeyCode) {
        case .none:
            DLog("No CSI u for repeat because non functional")
            return false
        case .BACKSPACE, .ENTER, .TAB:
            DLog("CSI u for repeat only if there is a modifier in \(modifiers)")
            return !modifiers.isEmpty
        default:
            DLog("CSI u for repeat because functional, not special case")
            return true
        }
    }
    // This is tried first. If it should be reported as CSI U then return .nonReportable.
    private func legacyEncodedKeypress(_ enhancementFlags: VT100TerminalKeyReportingFlags) -> EncodedKeypress {
        if type == .repeat && shouldUseCSIuForRepeat(enhancementFlags) {
            DLog("Use CSI for repeat")
            return .nonReportable
        }
        if enhancementFlags.contains(.reportAllEventTypes) &&
            [UnicodeScalar("\t").value,
             UnicodeScalar("\n").value,
             UnicodeScalar("\r").value,
             0x7f,
             8,
             27].contains(event.unicodeKeyCode) &&
            !modifiers.intersection([.alt, .ctrl, .shift]).isEmpty {
            // Use CSI u for tab, newline, backspace, and escape when combined
            // with a modifier. This isn't in the spec as far as I can see but
            // kitty does this.
            DLog("Use CSI u for special case key without mods")
            return .nonReportable
        }
        if type == .release {
            // Release is never reportable as legacy.
            DLog("Use CSI u for release")
            return .nonReportable
        }
        if enhancementFlags.contains(.reportAllKeysAsEscapeCodes) {
            // Flag means to never use legacy.
            DLog("Use CSI u when reporting all keys as escape codes")
            return .nonReportable
        }
        if enhancementFlags.contains(.reportAlternateKeys) &&
            modifiers.contains(.shift) &&
            !modifiers.intersection([.ctrl, .alt]).isEmpty {
            // This seems to be what Kitty does. It's not in the spec.
            DLog("Use CSI u when reporting alternate keys with shift and without ctl/alt")
            return .nonReportable
        }
        if enhancementFlags.contains(.disambiguateEscape) {
            // Return a legacy string unless it would be ambiguous
            DLog("Use disambiguate escape")
            return legacyUnderDisambiguateEscape
        }
        // Actually report as legacy. It's up to the client of ModernKeyMapper to implement
        // this.
        DLog("Fallback to ambiguous")
        return .fallbackToAmbiguous
    }

    func encoded(enhancementFlags: VT100TerminalKeyReportingFlags) -> EncodedKeypress {
        if type == .release && !enhancementFlags.contains(.reportAllEventTypes) {
            DLog("Don't report key-up unless reportEventType is on.")
            return .nonReportable
        }
        switch legacyEncodedKeypress(enhancementFlags) {
        case .string(let string):
            DLog("legacy encoded keypress returned \(string)")
            return .string(string)
        case .fallbackToAmbiguous:
            DLog("legacy encoded keypress returned .fallbackToAmbiguous")
            return .fallbackToAmbiguous
        case .nonReportable:
            DLog("legacy encoded keypress returned .nonReportable, get CSI u string")
            return csiU(enhancementFlags: enhancementFlags)
        }

    }

    private var isFunctional: Bool {
        return FunctionalKeyDefinition(virtualKeyCode: event.virtualKeyCode) != nil
    }

    var isDeadKey: Bool {
        return (!isFunctional &&
                event.eventType != .flagsChanged &&
                event.characters == "")
    }
    private func csiU(enhancementFlags: VT100TerminalKeyReportingFlags) -> EncodedKeypress {
        DLog("csiU flags=\(enhancementFlags)")
        let exceptions = [UnicodeScalar("\n").value,
                          UnicodeScalar("\r").value,
                          UnicodeScalar("\t").value,
                          8, 0x7f]  // backspace
        if (type == .release || type == .repeat) &&
            exceptions.contains(event.unicodeKeyCode) &&
            !enhancementFlags.contains(.reportAllKeysAsEscapeCodes) {
            // The Enter, Tab and Backspace keys will not have release events unless Report all
            // keys as escape codes is also set, so that the user can still type reset at a
            // shell prompt when a program that sets this mode ends without resetting it.
            if !enhancementFlags.contains(.reportAllEventTypes) || modifiers.isEmpty {
                // The spec neglects to mention that in report all event types
                // Enter, Tab, Backspace, and Tab report release (Kitty does).
                DLog("No CSI u for special key release/repeat when not reporting all keys as escape codes")
                return .nonReportable
            }
        }
        if isDeadKey && !enhancementFlags.contains(.reportAllKeysAsEscapeCodes) {
            DLog("Dead key \(event.debugDescription)")
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
                // Remove trailing empty parameters
                let dropCount = parameters
                    .reversed()
                    .prefix { $0.encoded.isEmpty }
                    .count
                let cleanParams = parameters.dropLast(dropCount)

                return pre + cleanParams.map { $0.encoded }.joined(separator: ";") + post
            }
        }

        // Number (unicode-key-code:alternate-key-codes)
        let numberComponents = { () -> [UInt32?]? in
            if event.csiUNumber == 0 {
                // Arrow keys: they have no number, they just use a letter.
                return nil
            } else if enhancementFlags.contains(.reportAlternateKeys) {
                // Note that the shifted key must be present only if shift is also
                // present in the modifiers.
                // We don't bother reporting shifted and base if they're the
                // same as the unicode code.
                if modifiers.contains(.shift) {
                    if (event.csiUNumber == event.baseLayoutKeyCode &&
                        (event.shiftedKeyCode == nil ||
                         event.csiUNumber == event.shiftedKeyCode)) {
                        return [event.csiUNumber]
                    } else {
                        return [event.csiUNumber, event.shiftedKeyCode, event.baseLayoutKeyCode]
                    }
                } else {
                    if (event.csiUNumber == event.baseLayoutKeyCode || event.baseLayoutKeyCode == 0) {
                        return [event.csiUNumber]
                    } else {
                        return [event.csiUNumber, nil, event.baseLayoutKeyCode]
                    }
                }
            } else {
                return [event.csiUNumber]
            }
        }()

        // Prepare modifier subparams early because we need it to decide
        // whether to encode a leading 1 in the second functional form.
        var modifierSubparams = [UInt32?]()
        if let encodedType = type.encoded {
            DLog("Add type")
            modifierSubparams.append(encodedType)
        }
        if modifiers.encoded != 1 || !modifierSubparams.isEmpty {
            DLog("Insert modifiers")
            modifierSubparams.insert(modifiers.encoded, at: 0)
        }

        var controlSequence = ControlSequence()
        if let functional = FunctionalKeyDefinition(virtualKeyCode: event.virtualKeyCode),
           let suffix = functional.rawValue.last {
            controlSequence.post = String(suffix)
            if ["u", "~"].contains(suffix) {
                // CSI number ; modifiers [u~]
                // The number in the first form above will be either the Unicode codepoint for a
                // key, such as 97 for the a key, or one of the numbers from the Functional key
                // definitions table below. The modifiers optional parameter encodes any
                // modifiers active for the key event. The encoding is described in the
                // Modifiers section.
                DLog("u/~")
                if let numberComponents {
                    controlSequence.parameters.append(.init(values: numberComponents))
                }
            } else {
                // CSI 1; modifiers [ABCDEFHPQS]
                // The second form is used for a few functional keys, such as the Home, End,
                // Arrow keys and F1 … F4, they are enumerated in the Functional key definitions
                // table below.
                // Note that if no modifiers are present the parameters are
                // omitted entirely giving an escape code of the form CSI [ABCDEFHPQS].
                DLog("CSI 1; mods [letter] case")
                if !modifierSubparams.isEmpty {
                    DLog("Actually include leading 1")
                    controlSequence.parameters.append(.init(values: [1]))
                }
            }
        } else if let numberComponents {
            // See note above about `CSI number ; modifiers [u~]` form.
            DLog("non functional or missing suffix")
            controlSequence.parameters.append(.init(values: numberComponents))
        }

        // Modifiers (modifiers:event-type)
        controlSequence.parameters.append(.init(values: modifierSubparams))

        // Associated values (text-as-codepoints)
        if enhancementFlags.contains(.reportAssociatedText) &&
            !event.textAsCodepoints.isEmpty &&
            event.textAsCodepoints != [event.unicodeKeyCode] {
            DLog("Add textAsCodepoints")
            controlSequence.parameters.append(.init(values: event.textAsCodepoints))
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
    case FORWARD_DELETE="3~"
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

    var number: UInt32 {
        switch self {
        case .INSERT, .FORWARD_DELETE, .F1, .F2, .F3, .F4, .F5, .F6, .F7, .F8, .F9, .F10, .F11, .F12:
            return 0
        default:
            break
        }
        return csiUNumber
    }

    var csiUNumber: UInt32 {
        let scanner = Scanner(string: rawValue)
        var number = UInt64(0)
        _ = scanner.scanUnsignedLongLong(&number)
        return UInt32(number)
    }
}

fileprivate extension FunctionalKeyDefinition {
    init?(virtualKeyCode: UInt16) {
        switch Int(virtualKeyCode) {
        case kVK_Escape:
            self = .ESCAPE
        case kVK_Return:
            self = .ENTER
        case kVK_Tab:
            self = .TAB
        case kVK_Delete:
            self = .BACKSPACE
        case kVK_Help:
            self = .INSERT
        case kVK_ForwardDelete:
            self = .FORWARD_DELETE
        case kVK_LeftArrow:
            self = .LEFT
        case kVK_RightArrow:
            self = .RIGHT
        case kVK_UpArrow:
            self = .UP
        case kVK_DownArrow:
            self = .DOWN
        case kVK_PageUp:
            self = .PAGE_UP
        case kVK_PageDown:
            self = .PAGE_DOWN
        case kVK_Home:
            self = .HOME
        case kVK_End:
            self = .END
        case kVK_CapsLock:
            self = .CAPS_LOCK
        case kVK_F1:
            self = .F1
        case kVK_F2:
            self = .F2
        case kVK_F3:
            self = .F3
        case kVK_F4:
            self = .F4
        case kVK_F5:
            self = .F5
        case kVK_F6:
            self = .F6
        case kVK_F7:
            self = .F7
        case kVK_F8:
            self = .F8
        case kVK_F9:
            self = .F9
        case kVK_F10:
            self = .F10
        case kVK_F11:
            self = .F11
        case kVK_F12:
            self = .F12
        case kVK_F13:
            self = .F13
        case kVK_F14:
            self = .F14
        case kVK_F15:
            self = .F15
        case kVK_F16:
            self = .F16
        case kVK_F17:
            self = .F17
        case kVK_F18:
            self = .F18
        case kVK_F19:
            self = .F19
        case kVK_F20:
            self = .F20
        case kVK_ANSI_Keypad0:
            self = .KP_0
        case kVK_ANSI_Keypad1:
            self = .KP_1
        case kVK_ANSI_Keypad2:
            self = .KP_2
        case kVK_ANSI_Keypad3:
            self = .KP_3
        case kVK_ANSI_Keypad4:
            self = .KP_4
        case kVK_ANSI_Keypad5:
            self = .KP_5
        case kVK_ANSI_Keypad6:
            self = .KP_6
        case kVK_ANSI_Keypad7:
            self = .KP_7
        case kVK_ANSI_Keypad8:
            self = .KP_8
        case kVK_ANSI_Keypad9:
            self = .KP_9
        case kVK_ANSI_KeypadDecimal:
            self = .KP_DECIMAL
        case kVK_ANSI_KeypadDivide:
            self = .KP_DIVIDE
        case kVK_ANSI_KeypadMultiply:
            self = .KP_MULTIPLY
        case kVK_ANSI_KeypadMinus:
            self = .KP_SUBTRACT
        case kVK_ANSI_KeypadPlus:
            self = .KP_ADD
        case kVK_ANSI_KeypadEnter:
            self = .KP_ENTER
        case kVK_ANSI_KeypadEquals:
            self = .KP_EQUAL
        case kVK_ANSI_KeypadClear:
            self = .KP_SEPARATOR  // This is a blind guess
        case kVK_RightShift:
            self = .RIGHT_SHIFT
        case kVK_RightControl:
            self = .RIGHT_CONTROL
        case kVK_RightOption:
            self = .RIGHT_ALT
        case kVK_RightCommand:
            self = .RIGHT_SUPER

        default:
            return nil
        }
    }

}
extension OptionSet where RawValue == UInt {
    func compactMap<T>(_ closure: (Self) throws -> (T?)) rethrows -> [T] {
        var result = [T]()
        for i in 0..<UInt.bitWidth {
            let value = UInt(1) << UInt(i)
            if (rawValue & value) != 0 {
                if let mapped = try closure(Self(rawValue: value)) {
                    result.append(mapped)
                }
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

extension String {
    var it_firstUnicodeScalarValue: UInt32? {
        return first?.unicodeScalars.first?.value
    }
    var it_ucs4CodePoints: [UInt32] {
        return flatMap { character in
            character.unicodeScalars.map { scalar in
                scalar.value
            }
        }
    }
}

extension NSEvent {
    private var it_functionalKeyCode: UInt32? {
        if let functional = FunctionalKeyDefinition(virtualKeyCode: keyCode) {
            // There are many keys that don’t correspond to letters from human
            // languages, and thus aren’t represented in Unicode. Think of
            // functional keys, such as Escape, Play, Pause, F1, Home, etc.
            // These are encoded using Unicode code points from the Private Use
            // Area (57344 - 63743). The mapping of key names to code points for
            // these keys is in the Functional key definition table below.
            return functional.number
        }
        return nil
    }

    func it_textAsCodePoints(useNativeOptionBehavior: Bool) -> [UInt32] {
        if it_functionalKeyCode != nil {
            return []
        }
        let string =
            if useNativeOptionBehavior {
                characters
            } else {
                characters(
                    byApplyingModifiers: modifierFlags
                        .subtracting([.option, .leftOption, .rightOption]))
            }
        // The associated text must not contain control codes (control codes are
        // code points below U+0020 and codepoints in the C0 and C1 blocks).
        return (string ?? "").it_ucs4CodePoints.filter { $0 >= 32 }
    }

    func it_csiUNumber(useNativeOptionBehavior: Bool) -> UInt32 {
        if let functional = FunctionalKeyDefinition(virtualKeyCode: keyCode) {
            return functional.csiUNumber
        }
        return it_unicodeKeyCode(useNativeOptionBehavior: useNativeOptionBehavior)
    }

    // The unicode-key-code above is the Unicode codepoint representing the key,
    // as a decimal number. For example, the A key is represented as 97 which is
    // the unicode code for lowercase a. Note that the codepoint used is always
    // the lower-case (or more technically, un-shifted) version of the key. If
    // the user presses, for example, ctrl+shift+a the escape code would be CSI
    // 97;modifiers u. It must not be CSI 65; modifiers u.
    func it_unicodeKeyCode(useNativeOptionBehavior: Bool) -> UInt32 {
        if let functional = it_functionalKeyCode {
            return functional
        }
        let optionalModifiersToIgnore: NSEvent.ModifierFlags =
            if useNativeOptionBehavior {
                []
            } else {
                [.option, .leftOption, .rightOption]
            }

        if let s = characters(
            byApplyingModifiers: modifierFlags
                .subtracting([.shift, .control])
                .subtracting(optionalModifiersToIgnore)),
           let code = s.it_firstUnicodeScalarValue {
            return code
        }
        if let code = charactersIgnoringModifiers?.it_firstUnicodeScalarValue {
            return code
        }
        return 0
    }

    func it_shiftedKeyCode(useNativeOptionBehavior: Bool) -> UInt32 {
        if let functional = it_functionalKeyCode {
            return functional
        }
        let optionalModifiersToIgnore: NSEvent.ModifierFlags =
            if useNativeOptionBehavior {
                []
            } else {
                [.option, .leftOption, .rightOption]
            }
        if let s = characters(
            byApplyingModifiers: modifierFlags
                .subtracting(optionalModifiersToIgnore)
                .subtracting([.control])
                .union([.shift])),
           let code = s.it_firstUnicodeScalarValue {
            return code
        }
        if let code = charactersIgnoringModifiers?.it_firstUnicodeScalarValue {
            return code
        }
        return 0
    }

    var it_baseLayoutKeyCode: UInt32 {
        if let functional = it_functionalKeyCode {
            return functional
        }
        let optionModifiers: NSEvent.ModifierFlags = [
            .option, .leftOption, .rightOption]
        if let s = characters(
            byApplyingModifiers: modifierFlags
                .subtracting(optionModifiers)
                .subtracting([.shift, .control])),
           let c = s.it_firstUnicodeScalarValue {
            return c
        }
        if let code = charactersIgnoringModifiers?.it_firstUnicodeScalarValue {
            return code
        }
        return 0
    }
}
