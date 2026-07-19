//
//  CompanionKeyInjectionTests.swift
//  iTerm2XCTests
//
//  Validates that a wire-level CompanionKeyEvent, once synthesized into an NSEvent
//  (CompanionKeyEvent.makeKeyDownEvent) and run through iTermStandardKeyMapper the
//  same way -[PTYSession injectSynthesizedKeyEvent:literalText:] does, produces the exact
//  terminal bytes a physical keypress would. The left/right Option cases are the
//  load-bearing ones: they prove the synthesized event carries the device-dependent
//  Option side bit, so the profile's per-side Option behavior is honored.
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionKeyInjectionTests: XCTestCase {
    /// Build a standard key mapper with an explicit configuration. The mapper's
    /// delegate is nil, so updateConfigurationWithEvent's standardKeyMapperWillMapKey:
    /// is a no-op and the configuration set here is what's used.
    private func makeMapper(leftOption: iTermOptionKeyBehavior,
                            rightOption: iTermOptionKeyBehavior,
                            cursorMode: Bool = false,
                            screenlike: Bool = false) -> iTermStandardKeyMapper {
        let output = VT100Output()
        output.cursorMode = cursorMode
        let config = iTermStandardKeyMapperConfiguration()
        config.outputFactory = output
        config.encoding = String.Encoding.utf8.rawValue
        config.leftOptionKey = leftOption
        config.rightOptionKey = rightOption
        config.screenlike = screenlike
        let mapper = iTermStandardKeyMapper()
        mapper.configuration = config
        return mapper
    }

    /// Mirror the mapped path of -[PTYSession injectSynthesizedKeyEvent:literalText:]:
    /// pre-Cocoa string (as
    /// Latin-1 bytes) if present, else post-Cocoa data. Single-key events only.
    private func bytes(for event: CompanionKeyEvent, mapper: iTermStandardKeyMapper) -> [UInt8] {
        guard let nsEvent = event.makeKeyDownEvents().first else { return [] }
        if let pre = mapper.keyMapperString(forPreCocoaEvent: nsEvent), !pre.isEmpty {
            return [UInt8](pre.data(using: .isoLatin1) ?? Data())
        }
        return [UInt8](mapper.keyMapperData(forPostCocoaEvent: nsEvent) ?? Data())
    }

    /// Encode a single-key event through the modern (Kitty/CSI-u) mapper with the
    /// given reporting flags, the way injection would.
    private func modernString(for event: CompanionKeyEvent,
                              flags: VT100TerminalKeyReportingFlags) -> String {
        let mapper = ModernKeyMapper()
        mapper.flags = flags
        guard let nsEvent = event.makeKeyDownEvents().first,
              let data = mapper.keyMapperData(forPostCocoaEvent: nsEvent) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    func testPlainCharacter() {
        let mapper = makeMapper(leftOption: .OPT_NORMAL, rightOption: .OPT_NORMAL)
        XCTAssertEqual(bytes(for: CompanionKeyEvent(key: .text("a")), mapper: mapper), [0x61])
    }

    func testControlC() {
        let mapper = makeMapper(leftOption: .OPT_NORMAL, rightOption: .OPT_NORMAL)
        let event = CompanionKeyEvent(key: .text("c"), modifiers: CompanionKeyModifiers(control: true))
        XCTAssertEqual(bytes(for: event, mapper: mapper), [0x03])
    }

    // The software keyboard's Return arrives as "\n"; it must reach the terminal as
    // CR (0x0d), via a synthesized Return keypress, not a literal LF.
    func testReturnSendsCarriageReturn() {
        let mapper = makeMapper(leftOption: .OPT_NORMAL, rightOption: .OPT_NORMAL)
        XCTAssertEqual(bytes(for: CompanionKeyEvent(key: .text("\n")), mapper: mapper), [0x0d])
        XCTAssertEqual(bytes(for: CompanionKeyEvent(key: .text("\r")), mapper: mapper), [0x0d])
    }

    func testReturnSynthesizesReturnKey() {
        let event = CompanionKeyEvent(key: .text("\n")).makeKeyDownEvents().first
        XCTAssertEqual(event?.characters, "\r")
        XCTAssertEqual(event.map { Int($0.keyCode) }, kVK_Return)
    }

    // A CRLF pair must collapse to one Return, not submit the line twice.
    func testCRLFCollapsesToSingleReturn() {
        let events = CompanionKeyEvent(key: .text("a\r\nb")).makeKeyDownEvents()
        XCTAssertEqual(events.map { $0.characters }, ["a", "\r", "b"])
    }

    // An armed ⌥ dead-key on a letter must NOT be misrouted to a literal write - it
    // has to reach the mapper so the profile's Esc+/Meta encoding is applied. The
    // device-dependent Option side bit is what distinguishes it from a layout-Option
    // character (which would legitimately be a different glyph).
    func testArmedOptionLetterIsNotLiteralFallback() {
        for mods in [CompanionKeyModifiers(leftOption: true), CompanionKeyModifiers(rightOption: true)] {
            let events = CompanionKeyEvent(key: .text("a"), modifiers: mods).makeKeyDownEvents()
            XCTAssertNil(events.first.flatMap { CompanionKeyEvent.literalFallback(for: $0) },
                         "armed Option letter must go through the mapper, not a literal write")
        }
        let upper = CompanionKeyEvent(key: .text("A"),
                                      modifiers: CompanionKeyModifiers(leftOption: true)).makeKeyDownEvents()
        XCTAssertNil(upper.first.flatMap { CompanionKeyEvent.literalFallback(for: $0) })
    }

    func testEscapeAndTab() {
        let mapper = makeMapper(leftOption: .OPT_NORMAL, rightOption: .OPT_NORMAL)
        XCTAssertEqual(bytes(for: CompanionKeyEvent(key: .special(.escape)), mapper: mapper), [0x1b])
        XCTAssertEqual(bytes(for: CompanionKeyEvent(key: .special(.tab)), mapper: mapper), [0x09])
    }

    func testArrowNormalVsApplicationCursorMode() {
        let normal = makeMapper(leftOption: .OPT_NORMAL, rightOption: .OPT_NORMAL, cursorMode: false)
        XCTAssertEqual(bytes(for: CompanionKeyEvent(key: .special(.up)), mapper: normal),
                       [0x1b, 0x5b, 0x41])  // ESC [ A
        let application = makeMapper(leftOption: .OPT_NORMAL, rightOption: .OPT_NORMAL, cursorMode: true)
        XCTAssertEqual(bytes(for: CompanionKeyEvent(key: .special(.up)), mapper: application),
                       [0x1b, 0x4f, 0x41])  // ESC O A
    }

    func testFunctionKeyStartsWithEscape() {
        let mapper = makeMapper(leftOption: .OPT_NORMAL, rightOption: .OPT_NORMAL)
        let f5 = bytes(for: CompanionKeyEvent(key: .special(.f5)), mapper: mapper)
        XCTAssertFalse(f5.isEmpty)
        XCTAssertEqual(f5.first, 0x1b)
    }

    func testNavigationKeysNonEmpty() {
        let mapper = makeMapper(leftOption: .OPT_NORMAL, rightOption: .OPT_NORMAL)
        for key in [CompanionSpecialKey.home, .end, .pageUp, .pageDown, .forwardDelete] {
            let data = bytes(for: CompanionKeyEvent(key: .special(key)), mapper: mapper)
            XCTAssertFalse(data.isEmpty, "\(key) produced no bytes")
        }
    }

    // The load-bearing distinction: identical 'a', but the Option SIDE picks the
    // profile behavior. Left=Normal passes 'a' through; Right=Esc+ prepends ESC.
    func testLeftVsRightOptionRespectProfileSides() {
        let mapper = makeMapper(leftOption: .OPT_NORMAL, rightOption: .OPT_ESC)

        let left = CompanionKeyEvent(key: .text("a"), modifiers: CompanionKeyModifiers(leftOption: true))
        XCTAssertEqual(bytes(for: left, mapper: mapper), [0x61],
                       "left Option is Normal here, so 'a' passes through unchanged")

        let right = CompanionKeyEvent(key: .text("a"), modifiers: CompanionKeyModifiers(rightOption: true))
        XCTAssertEqual(bytes(for: right, mapper: mapper), [0x1b, 0x61],
                       "right Option is Esc+ here, so it prepends ESC")
    }

    func testOptionMetaSetsHighBit() {
        let mapper = makeMapper(leftOption: .OPT_META, rightOption: .OPT_NORMAL)
        let event = CompanionKeyEvent(key: .text("a"), modifiers: CompanionKeyModifiers(leftOption: true))
        XCTAssertEqual(bytes(for: event, mapper: mapper), [0xe1])  // 'a' | 0x80
    }

    // A character with no single-keystroke mapping (emoji - true on every layout) must
    // be flagged for a literal write, so the CSI-u mapper can't mis-derive its key
    // code 0 as 'a'. Ordinary ASCII round-trips and is synthesized as a key event.
    func testNonLayoutCharacterFallsBackToLiteral() {
        let emoji = CompanionKeyEvent(key: .text("🎉")).makeKeyDownEvents()
        XCTAssertEqual(emoji.first.flatMap { CompanionKeyEvent.literalFallback(for: $0) }, "🎉")

        let ascii = CompanionKeyEvent(key: .text("a")).makeKeyDownEvents()
        XCTAssertNil(ascii.first.flatMap { CompanionKeyEvent.literalFallback(for: $0) })

        let upper = CompanionKeyEvent(key: .text("A")).makeKeyDownEvents()
        XCTAssertNil(upper.first.flatMap { CompanionKeyEvent.literalFallback(for: $0) })
    }

    // Special keys (arrows/function) carry a real key code and must NOT be treated as
    // literal fallbacks even though their private-use characters are non-ASCII.
    func testSpecialKeysAreNotLiteralFallbacks() {
        for key in [CompanionSpecialKey.up, .f5, .home, .escape, .tab] {
            let events = CompanionKeyEvent(key: .special(key)).makeKeyDownEvents()
            XCTAssertNil(events.first.flatMap { CompanionKeyEvent.literalFallback(for: $0) },
                         "\(key) should not be a literal fallback")
        }
    }

    func testTextSplitsIntoPerCharacterEvents() {
        let events = CompanionKeyEvent(key: .text("ls\n")).makeKeyDownEvents()
        XCTAssertEqual(events.count, 3)
        // The trailing "\n" is synthesized as a Return keypress (characters "\r").
        XCTAssertEqual(events.map { $0.characters }, ["l", "s", "\r"])
    }

    // The modern (Kitty) mapper is entirely virtual-key-code driven, so special keys
    // must carry their physical key code or CSI-u modes encode garbage.
    func testSpecialKeysCarryVirtualKeyCodes() {
        func keyCode(_ key: CompanionSpecialKey) -> Int? {
            CompanionKeyEvent(key: .special(key)).makeKeyDownEvents().first.map { Int($0.keyCode) }
        }
        XCTAssertEqual(keyCode(.up), kVK_UpArrow)
        XCTAssertEqual(keyCode(.escape), kVK_Escape)
        XCTAssertEqual(keyCode(.f5), kVK_F5)
        XCTAssertEqual(keyCode(.pageUp), kVK_PageUp)
        XCTAssertEqual(keyCode(.forwardDelete), kVK_ForwardDelete)
        XCTAssertEqual(keyCode(.home), kVK_Home)
    }

    // Layout-independent (works whatever keyboard the test host uses): upper and lower
    // 'a' share a physical key, and only the uppercase form carries Shift.
    func testUppercaseLetterAddsShiftOnSameKey() {
        let lower = CompanionKeyEvent(key: .text("a")).makeKeyDownEvents().first
        let upper = CompanionKeyEvent(key: .text("A")).makeKeyDownEvents().first
        XCTAssertNotNil(lower)
        XCTAssertNotNil(upper)
        XCTAssertEqual(lower?.keyCode, upper?.keyCode)
        XCTAssertEqual(lower?.modifierFlags.contains(.shift), false)
        XCTAssertEqual(upper?.modifierFlags.contains(.shift), true)
    }

    // End-to-end through the real modern mapper: these are the modes writeTask: would
    // have gotten wrong.
    func testModernMapperReportAllKeysAsEscapeCodes() {
        let flags = VT100TerminalKeyReportingFlags.reportAllKeysAsEscapeCodes
        XCTAssertEqual(modernString(for: CompanionKeyEvent(key: .special(.up)), flags: flags),
                       "\u{1b}[A")
        XCTAssertEqual(modernString(for: CompanionKeyEvent(key: .special(.f5)), flags: flags),
                       "\u{1b}[15~")
        XCTAssertEqual(modernString(for: CompanionKeyEvent(key: .text("a")), flags: flags),
                       "\u{1b}[97u")
    }

    // A dead-key modifier (Ctrl/Option armed in the accessory) must modify special
    // keys too - Ctrl+Up, Option+PageUp, etc.
    func testDeadKeyModifierAppliesToSpecialKeys() {
        let mapper = makeMapper(leftOption: .OPT_NORMAL, rightOption: .OPT_NORMAL)
        let plain = bytes(for: CompanionKeyEvent(key: .special(.up)), mapper: mapper)
        let control = bytes(for: CompanionKeyEvent(key: .special(.up),
                                                   modifiers: CompanionKeyModifiers(control: true)),
                            mapper: mapper)
        XCTAssertFalse(control.isEmpty)
        XCTAssertNotEqual(plain, control, "Ctrl should change the arrow's encoding")
        XCTAssertEqual(control.first, 0x1b)
    }

    // In "report all event types" mode a discrete tap must produce BOTH a press and a
    // release, or the app thinks the key is held down forever. Injection synthesizes
    // the key-up the same way this test does.
    func testModernMapperReportsPressAndReleaseForEventTypesMode() {
        let flags: VT100TerminalKeyReportingFlags = [.reportAllKeysAsEscapeCodes, .reportAllEventTypes]
        let mapper = ModernKeyMapper()
        mapper.flags = flags
        guard let down = CompanionKeyEvent(key: .text("a")).makeKeyDownEvents().first else {
            return XCTFail("no key-down event")
        }
        let press = mapper.keyMapperData(forPostCocoaEvent: down).map { String(decoding: $0, as: UTF8.self) }
        XCTAssertEqual(press, "\u{1b}[97u")

        XCTAssertTrue(mapper.keyMapperWantsKeyUp, "event-types mode must want key-up")
        let up = NSEvent.keyEvent(with: .keyUp,
                                  location: .zero,
                                  modifierFlags: down.modifierFlags,
                                  timestamp: 0,
                                  windowNumber: 0,
                                  context: nil,
                                  characters: down.characters ?? "",
                                  charactersIgnoringModifiers: down.charactersIgnoringModifiers ?? "",
                                  isARepeat: false,
                                  keyCode: down.keyCode)!
        let release = mapper.keyMapperData(forKeyUp: up).map { String(decoding: $0, as: UTF8.self) }
        // CSI 97 ; 1:3 u - key 97, event type 3 (release).
        XCTAssertEqual(release, "\u{1b}[97;1:3u")
    }

    // Without event-types mode there is no release - a real key-up produces nothing.
    func testModernMapperNoKeyUpWithoutEventTypesMode() {
        let mapper = ModernKeyMapper()
        mapper.flags = .reportAllKeysAsEscapeCodes
        XCTAssertFalse(mapper.keyMapperWantsKeyUp)
    }

    func testModernMapperDisambiguateEscape() {
        let flags = VT100TerminalKeyReportingFlags.disambiguateEscape
        // Esc becomes CSI u so it can't be confused with the start of a sequence.
        XCTAssertEqual(modernString(for: CompanionKeyEvent(key: .special(.escape)), flags: flags),
                       "\u{1b}[27u")
        // An ordinary letter stays legacy.
        XCTAssertEqual(modernString(for: CompanionKeyEvent(key: .text("a")), flags: flags),
                       "a")
    }
}
