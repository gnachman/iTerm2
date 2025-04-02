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

extension iTermOptionKeyBehavior: Codable {}
extension iTermBuckyBit: Codable {}

struct ModernKeyMapperConfiguration: Codable {
    var leftOptionKey: iTermOptionKeyBehavior
    var rightOptionKey: iTermOptionKeyBehavior
    var leftControlKey: iTermBuckyBit
    var rightControlKey: iTermBuckyBit
    var leftCommandKey: iTermBuckyBit
    var rightCommandKey: iTermBuckyBit
    var functionKey: iTermBuckyBit
}

extension ModernKeyMapperConfiguration {
    func eventIncludesAlt(_ event: NSEvent) -> Bool {
        let leftOptionNormal = leftOptionKey == .OPT_NORMAL
        let rightOptionNormal = rightOptionKey == .OPT_NORMAL
        let optionAsAlt = ((event.it_modifierFlags.contains(.leftOption) && !leftOptionNormal) ||
                           (event.it_modifierFlags.contains(.rightOption) && !rightOptionNormal))
        return optionAsAlt
    }
}

@objc(iTermModernKeyMapperConfiguration)
class ObjCModernKeyMapperConfiguration: NSObject {
    let value: ModernKeyMapperConfiguration

    @objc
    init(leftOptionKey: iTermOptionKeyBehavior,
         rightOptionKey: iTermOptionKeyBehavior,
         leftControlKey: iTermBuckyBit,
         rightControlKey: iTermBuckyBit,
         leftCommandKey: iTermBuckyBit,
         rightCommandKey: iTermBuckyBit,
         functionKey: iTermBuckyBit) {
        value = ModernKeyMapperConfiguration(leftOptionKey: leftOptionKey,
                                             rightOptionKey: rightOptionKey,
                                             leftControlKey: leftControlKey,
                                             rightControlKey: rightControlKey,
                                             leftCommandKey: leftCommandKey,
                                             rightCommandKey: rightCommandKey,
                                             functionKey: functionKey)
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
        return "<KeyEventInfo: type=\(eventType) modifiers=\(modifiers) keyCode=\(virtualKeyCode) characters=\(characters ?? "") charactersIgnoringModifiers=\(charactersIgnoringModifiers ?? "")>"
    }
    var eventType: NSEvent.EventType
    var previousModifiers: UniversalModifierFlags
    var modifiers: UniversalModifierFlags
    private let configuration: ModernKeyMapperConfiguration
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

    var useNativeOptionBehavior: Bool

    var nsevent: NSEvent? {
        let event = NSEvent.keyEvent(with: eventType,
                                     location: .zero,
                                     modifierFlags: modifiers.raw.flags,
                                     timestamp: Date.timeIntervalSinceReferenceDate,
                                     windowNumber: 0,
                                     context: nil,
                                     characters: characters ?? "",
                                     charactersIgnoringModifiers: charactersIgnoringModifiers ?? "",
                                     isARepeat: isARepeat,
                                     keyCode: virtualKeyCode)
        event?.it_functionModifierPressed = modifiers.raw.functionKeyPressed
        return event
    }

    init(event: NSEvent,
         configuration: ModernKeyMapperConfiguration,
         flags: VT100TerminalKeyReportingFlags) {
        eventType = event.type
        self.configuration = configuration
        virtualKeyCode = event.keyCode

        let optionAsAlt = configuration.eventIncludesAlt(event)
        useNativeOptionBehavior = if event.type == .keyDown || event.type == .keyUp {
            !flags.contains(.reportAllKeysAsEscapeCodes) && !optionAsAlt
        } else {
            true
        }
        unicodeKeyCode = if event.type == .keyDown || event.type == .keyUp {
            event.it_unicodeKeyCode(
                useNativeOptionBehavior: useNativeOptionBehavior)
        } else {
            switch Int(virtualKeyCode) {
            case kVK_Shift:
                57441
            case kVK_RightShift:
                57447
            case kVK_Control:
                57442
            case kVK_RightControl:
                57448
            case kVK_Option:
                57443
            case kVK_RightOption:
                57449
            case kVK_Command:
                57444
            case kVK_RightCommand:
                57450
            default:
                0
            }
        }

        modifiers = UniversalModifierFlags(
            flags: event.it_modifierFlags,
            functionKeyPressed: event.it_functionModifierPressed,
            unicodeKeyCode: unicodeKeyCode,
            configuration: configuration)

        previousModifiers = UniversalModifierFlags(
            flags: event.it_previousFlags,
            functionKeyPressed: event.it_functionModifierPreviouslyPressed,
            unicodeKeyCode: unicodeKeyCode,
            configuration: configuration)

        if event.type == .keyDown || event.type == .keyUp {
            characters = event.characters
            charactersIgnoringModifiers = event.charactersIgnoringModifiers
            isARepeat = event.isARepeat
            useNativeOptionBehavior = !flags.contains(.reportAllKeysAsEscapeCodes) && !optionAsAlt
            csiUNumber = event.it_csiUNumber(useNativeOptionBehavior: useNativeOptionBehavior)
            shiftedKeyCode = event.it_shiftedKeyCode(
                useNativeOptionBehavior: useNativeOptionBehavior)
            baseLayoutKeyCode = event.it_baseLayoutKeyCode

            let textUsesNativeOptionBehavior = modifiers.cooked.contains(.option) && !modifiers.cooked.contains(.alt)
            textAsCodepoints = event.it_textAsCodePoints(
                useNativeOptionBehavior: textUsesNativeOptionBehavior)
        } else {
            characters = ""
            charactersIgnoringModifiers = ""
            isARepeat = false
            useNativeOptionBehavior = true

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

    func shouldHandleBuckyBits() -> Bool {
        return true
    }

    func handleKeyDown(withBuckyBits nsevent: NSEvent) -> String? {
        DLog("handleKeyDown(withBuckyBits \(nsevent)")
        let event = updateConfiguration(event: nsevent)
        let result = impl.keyMapperData(forPostCocoaEvent: event)
        DLog("return \(result?.debugDescription ?? "nil")")
        return result.map { String(decoding: $0, as: UTF8.self) }
    }

    func handleKeyUp(withBuckyBits nsevent: NSEvent) -> String? {
        DLog("handleKeyUp(withBuckyBits \(nsevent)")
        let event = updateConfiguration(event: nsevent)
        let result = impl.keyMapperData(forKeyUp: event)
        DLog("return \(result?.debugDescription ?? "nil")")
        return result.map { String(decoding: $0, as: UTF8.self) }
    }

    func handleFlagsChanged(withBuckyBits nsevent: NSEvent) -> String? {
        DLog("handleFlagsChanged(withBuckyBits \(nsevent)")
        let event = updateConfiguration(event: nsevent)
        let result = impl.keyMapperString(forPreCocoaEvent: event)
        DLog("return \(result?.debugDescription ?? "nil")")
        return result
    }

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

    func transformedText(toInsert text: String) -> String {
        return impl.transformedText(toInsert: text)
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
                                             rightOptionKey: .OPT_NORMAL,
                                             leftControlKey: .regular,
                                             rightControlKey: .regular,
                                             leftCommandKey: .regular,
                                             rightCommandKey: .regular,
                                             functionKey: .regular)
            }
        impl.configuration = configuration
        let eventInfo = KeyEventInfo(event: event,
                                     configuration: configuration,
                                     flags: impl.flags)
        impl.event = eventInfo
        return eventInfo
    }
}

// Public interfaces of the impl that mirrors iTermKeyMapper.
fileprivate class ModernKeyMapperImpl {
    var flags = VT100TerminalKeyReportingFlags(rawValue: 0)
    weak var delegate: ModernKeyMapperDelegate?
    var configuration = ModernKeyMapperConfiguration(leftOptionKey: .OPT_NORMAL,
                                                     rightOptionKey: .OPT_NORMAL,
                                                     leftControlKey: .regular,
                                                     rightControlKey: .regular,
                                                     leftCommandKey: .regular,
                                                     rightCommandKey: .regular,
                                                     functionKey: .regular)
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

        if NSEvent.it_isFunctionOrNumericKeypad(modifierFlags: event.modifiers.excludingBuckyBits.flags) {
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
            modifierFlags: event.modifiers.excludingBuckyBits.flags,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            leftOptionConfig: configuration.leftOptionKey,
            rightOptionConfig: configuration.rightOptionKey) {
            // Treating option as Esc+ (or its CSI u equivalent)
            DLog("true: should send option-modified key")
            return true
        }

        if NSEvent.it_isControlCodeWithOption(
            modifierFlags: event.modifiers.excludingBuckyBits.flags,
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
        return false
    }

    func keyMapperString(forPreCocoaEvent event: KeyEventInfo) -> String? {
        DLog("keyMapperString(forPreCocoaEvent \(event)")
        switch event.eventType {
        case .keyDown:
            DLog("keyDown")
            if event.modifiers.excludingBuckyBits.flags.contains(.numericPad) {
                DLog("numPad")
                return handle(event: event)?.lossyString
            }
            if event.modifiers.excludingBuckyBits.flags.intersection([.control, .command, .option]) != [.control] {
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
        if event.eventType == .flagsChanged &&
            event.modifiers.forcingOptionToAlt.reportableFlags == event.previousModifiers.forcingOptionToAlt.reportableFlags {
            DLog("flags changed but none are reportable")
            return true
        }
        let leftCommandShouldReport = configuration.leftCommandKey != .regular
        let leftCommandInvolved = event.modifiers.raw.flags.contains(.leftCommand) || event.virtualKeyCode == kVK_Command
        if !leftCommandShouldReport && leftCommandInvolved {
            DLog("Ignore because left command involved but not reporting")
            return true
        }
        let rightCommandShouldReport = configuration.rightCommandKey != .regular
        let rightCommandInvolved = event.modifiers.raw.flags.contains(.rightCommand) || event.virtualKeyCode == kVK_RightCommand
        if !rightCommandShouldReport && rightCommandInvolved {
            DLog("Ignore because right command involved but not reporting")
            return true
        }
        return false
    }

    func keyMapperWantsKeyEquivalent(_ event: KeyEventInfo) -> Bool {
        DLog("keyMapperWantsKeyEquivalent \(event)")
        return !shouldIgnore(event: event)
    }

    func keyMapperDictionaryValue() -> [AnyHashable : Any] {
        return ["flags": NSNumber(value: flags.rawValue)]
    }

    func transformedText(toInsert text: String) -> String {
        if !flags.contains(.reportAllKeysAsEscapeCodes) {
            return text
        }
        let phonyEvent = NSEvent.keyEvent(with: .keyDown,
                                          location: .zero,
                                          modifierFlags: NSApp.currentEvent?.modifierFlags ?? [],
                                          timestamp: Date.timeIntervalSinceReferenceDate,
                                          windowNumber: 0,
                                          context: nil,
                                          characters: text,
                                          charactersIgnoringModifiers: text,
                                          isARepeat: false,
                                          keyCode: NSApp.currentEvent?.keyCode ?? 0)
        guard let phonyEvent else {
            return text
        }
        let event = KeyEventInfo(event: phonyEvent, configuration: configuration, flags: flags)
        let keyReport = KeyReport(type: .press, event: event)
        let encoded = keyReport.encoded(enhancementFlags: flags)
        switch encoded {
        case .string(let value):
            return value
        case .fallbackToAmbiguous, .nonReportable:
            DLog("Unexpected result from csiU: \(encoded)")
            return text
        }
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

    private func string(for event: KeyEventInfo, preCocoa: Bool) -> String {
        DLog("event=\(event) preCocoa=\(preCocoa)")
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
        }
        guard let report = keyReport(for: event) else {
            DLog("no key report")
            return ""
        }
        switch report.encoded(enhancementFlags: flags) {
        case .fallbackToAmbiguous:
            DLog("encode returned fallbackToAmbiguous")
            return ambiguousString(keyReport: report,
                                   preCocoa: preCocoa,
                                   event: event)
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
            if event.isARepeat {
                return regularReport(type: .repeat, event: event)
            } else {
                return regularReport(type: .press, event: event)
            }
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
            let isRelease = event.modifiers.cooked.subtracting(event.previousModifiers.cooked).isEmpty
            if isRelease && !flags.contains(.reportAllEventTypes) {
                // This progressive enhancement (0b10) causes the terminal to
                // report key repeat and key release events.
                DLog("Ignoring flags-changed on release without report all event types")
                return nil
            }
            return KeyReport(type: isRelease ? .release : .press,
                             event: event)
        default:
            DLog("Unexpected event type \(event.eventType)")
            return nil
        }
    }

    private func regularReport(type: KeyReport.EventType, event: KeyEventInfo) -> KeyReport {
        return KeyReport(type: type,
                         event: event)
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

    private var numpad: Bool {
        event.modifiers.cooked.contains(.numericKeypad)
    }

    private let csi = "\u{001B}["

    init(type: EventType,
         event: KeyEventInfo) {
        self.type = type
        self.event = event
    }

    private var eligibleForCSI: Bool {
        if !event.modifiers.cooked.reportableFlags.isEmpty {
            return true
        }
        return ![UInt32("\r"),
                 UInt32("\t"),
                 UInt32(0x7f)].contains(event.unicodeKeyCode)
    }

    private var legacyUnderDisambiguateEscape: EncodedKeypress {
        DLog("legacyUnderDisambiguateEscape")
        let hasNonlegacyFlags = !event.modifiers.cooked.nonLegacyCompatibleFlags.isEmpty
        if hasNonlegacyFlags {
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
        let nonLockModifiers = event.modifiers.cooked.nonLockFlags
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
            // Forward Delete, Home, End, Page Up, Page Down, and function keys take this code path.
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
            DLog("CSI u for repeat only if there is a reportable modifier in \(event.modifiers)")
            return !event.modifiers.cooked.reportableFlags.isEmpty
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
            event.modifiers.cooked.reportableFlags.overlaps([.alt, .control, .shift]) {
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
            event.modifiers.cooked.contains(.shift) &&
            event.modifiers.cooked.overlaps([.control, .alt]) {
            // This seems to be what Kitty does. It's not in the spec.
            DLog("Use CSI u when reporting alternate keys with shift and one of ctl/alt")
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
        let optionPressed = event.modifiers.raw.flags.contains(.option)
        if optionPressed && !event.useNativeOptionBehavior {
            return false
        }
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
        if type == .release &&
            exceptions.contains(event.unicodeKeyCode) &&
            !enhancementFlags.contains(.reportAllKeysAsEscapeCodes) {
            // The Enter, Tab and Backspace keys will not have release events unless Report all
            // keys as escape codes is also set, so that the user can still type reset at a
            // shell prompt when a program that sets this mode ends without resetting it.
            if !enhancementFlags.contains(.reportAllEventTypes) || event.modifiers.cooked.reportableFlags.isEmpty {
                // The spec neglects to mention that in Report All Event Types
                // Enter, Tab, Backspace, and Tab report release (Kitty does).
                DLog("No CSI u for special key release when not reporting all keys as escape codes")
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
        let alt = event.modifiers.cooked.contains(.alt)

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
                if event.modifiers.cooked.reportableFlags.contains(.shift) {
                    if (event.csiUNumber == event.baseLayoutKeyCode &&
                        (event.shiftedKeyCode == nil ||
                         event.csiUNumber == event.shiftedKeyCode)) {
                        return [event.csiUNumber]
                    } else if event.csiUNumber == event.baseLayoutKeyCode {
                        return [event.csiUNumber, event.shiftedKeyCode]
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
        if enhancementFlags.contains(.reportAllEventTypes) {
            if let encodedType = type.encoded {
                DLog("Add type")
                modifierSubparams.append(encodedType)
            }
        }
        let modeSpecificModifiers = if enhancementFlags.contains(.reportAllKeysAsEscapeCodes) {
            // This is approximately Kitty's behavior. I have a feeling it's an emergent property
            // of some spaghetti, but it certainly isn't in the spec.
            event.modifiers.forcingOptionToAlt
        } else {
            event.modifiers.cooked
        }
        if modeSpecificModifiers.encoded != 1 || !modifierSubparams.isEmpty {
            DLog("Insert modifiers")
            modifierSubparams.insert(modeSpecificModifiers.encoded, at: 0)
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
        // This progressive enhancement (0b10000) additionally causes key events that generate text
        // to be reported as CSI u escape codes with the text embedded in the escape code. See Text
        // as code points above for details on the mechanism. Note that this flag is an enhancement
        // to Report all keys as escape codes and is undefined if used without it.
        if enhancementFlags.contains(.reportAssociatedText) &&
            enhancementFlags.contains(.reportAllKeysAsEscapeCodes) &&  // reportAssociatedText is an enhacment to reportAllKeys
            !event.textAsCodepoints.isEmpty &&  // key would not generate text
            !alt &&  // When option sends esc+, the character wouldn't send text, so there is no associated text (matches Kitty's behavior)
            event.eventType == .keyDown {  // only key-down generaets text
            DLog("Add textAsCodepoints: \(event.textAsCodepoints)")
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
    case HOME="H"
    case END="F"
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
        if modifierFlags.contains(.control) {
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

extension OptionSet where Self == Self.Element {
    public func overlaps(_ other: Self) -> Bool {
        return !intersection(other).isEmpty
    }
}

fileprivate struct UniversalModifierFlags: Codable, CustomDebugStringConvertible {
    var debugDescription: String {
        return "raw=\(raw) cooked=\(cooked)"
    }
    struct UnambiguousEventModifierFlags: Codable, CustomDebugStringConvertible {
        var debugDescription: String {
            "flags=\(flags) functionKey=\(functionKeyPressed)"
        }
        var flags: NSEvent.ModifierFlags
        var functionKeyPressed: Bool

        init(_ event: NSEvent) {
            flags = event.it_modifierFlags
            functionKeyPressed = event.it_functionModifierPressed
        }

        init(flags: NSEvent.ModifierFlags, functionKeyPressed: Bool) {
            self.flags = flags
            self.functionKeyPressed = functionKeyPressed
        }

        var isEmpty: Bool {
            flags.isEmpty && !functionKeyPressed
        }

        func intersection(_ rhs: UnambiguousEventModifierFlags) -> UnambiguousEventModifierFlags {
            return UnambiguousEventModifierFlags(flags: flags.intersection(rhs.flags),
                                                 functionKeyPressed: functionKeyPressed && rhs.functionKeyPressed)
        }

        func subtracting(_ rhs: UnambiguousEventModifierFlags) -> UnambiguousEventModifierFlags {
            return UnambiguousEventModifierFlags(flags: flags.subtracting(rhs.flags),
                                                 functionKeyPressed: functionKeyPressed && !rhs.functionKeyPressed)
        }
    }

    private var buckyBitGenerators: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if configuration.leftCommandKey != .regular {
            flags.insert(.leftCommand)
        }
        if configuration.rightCommandKey != .regular {
            flags.insert(.rightCommand)
        }
        if configuration.leftControlKey != .regular {
            flags.insert(.leftControl)
        }
        if configuration.rightControlKey != .regular {
            flags.insert(.rightControl)
        }
        return flags
    }

    // Just what we got from the NSEvent unmodified.
    var raw: UnambiguousEventModifierFlags

    // Raw, but with bits unset when they correspond to buckybits (hyper, super, meta).
    // This should not be used often.
    var excludingBuckyBits: UnambiguousEventModifierFlags {
        UnambiguousEventModifierFlags(
            flags: raw.flags.subtracting(buckyBitGenerators),
            functionKeyPressed: raw.functionKeyPressed && configuration.functionKey != .regular)
    }

    let configuration: ModernKeyMapperConfiguration

    // A CookedModifierFlags describes which semantic modifiers are pressed. If right command is
    // mapped to hyper, then command will *not* be set but hyper will.
    struct CookedModifierFlags: OptionSet, Codable {
        static let control = CookedModifierFlags(rawValue: 0b100)
        static let shift = CookedModifierFlags(rawValue: 0b1)
        // Only set if reportable
        static let alt = CookedModifierFlags(rawValue: 0b10)
        static let hyper = CookedModifierFlags(rawValue: 0b10000)
        static let meta = CookedModifierFlags(rawValue: 0b100000)
        static let `super` = CookedModifierFlags(rawValue: 0b1000)

        static let capsLock = CookedModifierFlags(rawValue: 0b1000000)
        static let numLock =  CookedModifierFlags(rawValue: 0b10000000)

        static let command = CookedModifierFlags(rawValue: 0b1000000000)

        // Physical option key (not configuration-dependent)
        static let option = CookedModifierFlags(rawValue: 0b10000000000)
        static let numericKeypad = CookedModifierFlags(rawValue: 0b100000000000)

        var rawValue: UInt32

        private var nonreportableFlags: CookedModifierFlags {
            [.command, .option, .numericKeypad]
        }

        // Encoding for CSI u
        var encoded: UInt32 {
            let masked = subtracting(nonreportableFlags).rawValue
            if masked == 0 {
                return 1
            }
            return masked + 1
        }

        var reportableFlags: CookedModifierFlags {
            return subtracting(nonreportableFlags)
        }

        var nonLegacyCompatibleFlags: CookedModifierFlags {
            return intersection([.hyper, .meta, .`super`, .command, .alt, .option])
        }

        var nonLockFlags: CookedModifierFlags {
            return subtracting([.numLock, .capsLock])
        }

        private static func from(deviceIndependentFlag: NSEvent.ModifierFlags,
                                 leftFlagSet: Bool,
                                 rightFlagSet: Bool,
                                 leftBuckyBit: iTermBuckyBit,
                                 rightBuckyBit: iTermBuckyBit) -> CookedModifierFlags {
            // Translate a buckybit configuration to a CookedModifierFlags, using the normal behavior
            // if the buckybit is set to `regular`.
            func from(buckyBit: iTermBuckyBit,
                      defaultFlag: NSEvent.ModifierFlags) -> CookedModifierFlags? {
                func from(nsEventFlag: NSEvent.ModifierFlags) -> CookedModifierFlags? {
                    return switch nsEventFlag {
                    case .command: .command
                    case .control: .control
                    case .shift: .shift
                    case .option: .option
                    case .function: nil
                    default: it_fatalError("Bogus default flag \(nsEventFlag)")
                    }
                }

                switch buckyBit {
                case .regular:
                    return from(nsEventFlag: defaultFlag)
                case .hyper:
                    return .hyper
                case .meta:
                    return .meta
                case .`super`:
                    return .`super`
                @unknown default:
                    it_fatalError("Bogus bucky bit \(buckyBit.rawValue)")
                }
            }

            var result = CookedModifierFlags()

            if deviceIndependentFlag.contains(.command) {
                if leftFlagSet, let cooked = from(buckyBit: leftBuckyBit, defaultFlag: deviceIndependentFlag) {
                    result.insert(cooked)
                }
                if rightFlagSet, let cooked = from(buckyBit: rightBuckyBit, defaultFlag: deviceIndependentFlag) {
                    result.insert(cooked)
                }
                return result
            }
            if deviceIndependentFlag.contains(.control) {
                if leftFlagSet, let cooked = from(buckyBit: leftBuckyBit, defaultFlag: deviceIndependentFlag) {
                    result.insert(cooked)
                }
                if rightFlagSet, let cooked = from(buckyBit: rightBuckyBit, defaultFlag: deviceIndependentFlag) {
                    result.insert(cooked)
                }
                return result
            }
            if deviceIndependentFlag.contains(.function) {
                if leftFlagSet, let cooked = from(buckyBit: leftBuckyBit, defaultFlag: deviceIndependentFlag) {
                    result.insert(cooked)
                }
                if rightFlagSet, let cooked = from(buckyBit: rightBuckyBit, defaultFlag: deviceIndependentFlag) {
                    result.insert(cooked)
                }
                return result
            }
            it_fatalError("Unexpected device independent flag \(deviceIndependentFlag)")
        }

        static func create(eventModifierFlags: UnambiguousEventModifierFlags,
                           configuration: ModernKeyMapperConfiguration,
                           unicodeKeyCode: UInt32) -> CookedModifierFlags {
            var result = CookedModifierFlags()
            if eventModifierFlags.flags.contains(.control) {
                result.insert(Self.from(deviceIndependentFlag: .control,
                                        leftFlagSet: eventModifierFlags.flags.contains(.leftControl),
                                        rightFlagSet: eventModifierFlags.flags.contains(.rightControl),
                                        leftBuckyBit: configuration.leftControlKey,
                                        rightBuckyBit: configuration.rightControlKey))
            }
            if eventModifierFlags.flags.contains(.command) {
                result.insert(Self.from(deviceIndependentFlag: .command,
                                        leftFlagSet: eventModifierFlags.flags.contains(.leftCommand),
                                        rightFlagSet: eventModifierFlags.flags.contains(.rightCommand),
                                        leftBuckyBit: configuration.leftCommandKey,
                                        rightBuckyBit: configuration.rightCommandKey))
            }
            if eventModifierFlags.functionKeyPressed {
                result.insert(Self.from(deviceIndependentFlag: .function,
                                        leftFlagSet: true,
                                        rightFlagSet: false,
                                        leftBuckyBit: configuration.functionKey,
                                        rightBuckyBit: .regular))
            }
            if eventModifierFlags.flags.contains(.shift) {
                result.insert(.shift)
            }
            if eventModifierFlags.flags.contains(.option) {
                result.insert(.option)
            }
            let exceptions = [UnicodeScalar("\n").value,
                              UnicodeScalar("\r").value,
                              UnicodeScalar("\t").value,
                              8, 0x7f]  // backspace
            let mustUseAlt = eventModifierFlags.flags.contains(.function) || exceptions.contains(unicodeKeyCode)
            if eventModifierFlags.flags.contains(.leftOption) && (mustUseAlt || configuration.leftOptionKey != .OPT_NORMAL) {
                result.insert(.alt)
            }
            if eventModifierFlags.flags.contains(.rightOption) && (mustUseAlt || configuration.rightOptionKey != .OPT_NORMAL) {
                result.insert(.alt)
            }
            if eventModifierFlags.flags.contains(.capsLock) {
                result.insert(.capsLock)
            }
            if eventModifierFlags.flags.contains(.numericPad) {
                result.insert(.numericKeypad)
            }
            return result
        }
    }
    let cooked: CookedModifierFlags

    // For some reason Kitty reports the option key even when it is not acting as alt. These
    // are very special reporting flags used only for modifier reporting.
    var forcingOptionToAlt: CookedModifierFlags {
        if cooked.contains(.option) {
            return cooked.union([.alt])
        }
        return cooked
    }

    init(flags: NSEvent.ModifierFlags,
         functionKeyPressed: Bool,
         unicodeKeyCode: UInt32,
         configuration: ModernKeyMapperConfiguration) {
        raw = UnambiguousEventModifierFlags(flags: flags, functionKeyPressed: functionKeyPressed)
        self.configuration = configuration
        cooked = CookedModifierFlags.create(eventModifierFlags: raw,
                                            configuration: configuration,
                                            unicodeKeyCode: unicodeKeyCode)
    }
}

