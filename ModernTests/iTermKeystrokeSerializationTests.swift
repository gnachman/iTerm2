//
//  iTermKeystrokeSerializationTests.swift
//  iTerm2
//
//  Tests for the four-part keystroke serialization and the interpretation of the old three-part
//  format, whose keycode 0 can mean either kVK_ANSI_A or "unknown". Bindings with an unknown
//  keycode must not match the A key when key bindings match by physical key (issue 13110).
//

import XCTest
@testable import iTerm2SharedARC

final class iTermKeystrokeSerializationTests: XCTestCase {
    private let keyCodeA: Int32 = 0x00            // kVK_ANSI_A
    private let keyCodeT: Int32 = 0x11            // kVK_ANSI_T
    private let keyCodeForwardDelete: Int32 = 0x75
    private let forwardDelete: UInt32 = 0xf728    // NSDeleteFunctionKey
    private var originalLanguageAgnostic = false

    override func setUp() {
        super.setUp()
        originalLanguageAgnostic = iTermPreferences.bool(forKey: kPreferenceKeyLanguageAgnosticKeyBindings)
        // Don't depend on the keyboard layouts enabled on this machine.
        iTermKeyCodeZeroCharacters.testingOverride = []
    }

    override func tearDown() {
        iTermPreferences.setBool(originalLanguageAgnostic, forKey: kPreferenceKeyLanguageAgnosticKeyBindings)
        iTermKeyCodeZeroCharacters.testingOverride = nil
        super.tearDown()
    }

    private func keystroke(keyCode: Int32,
                           character: UInt32,
                           modifiers: NSEvent.ModifierFlags = []) -> iTermKeystroke {
        return iTermKeystroke(virtualKeyCode: keyCode,
                              hasKeyCode: true,
                              modifierFlags: modifiers,
                              character: character,
                              modifiedCharacter: character)
    }

    private func dictionary(_ keys: String...) -> [String: [AnyHashable: Any]] {
        var result = [String: [AnyHashable: Any]]()
        for key in keys {
            result[key] = ["Action": 11, "Text": key]
        }
        return result
    }

    // MARK: - Parsing

    func testThreePartKeyCodeZeroWithFunctionKeyCharacterHasNoKeyCode() {
        let k = iTermKeystroke(serialized: "0xf728-0x0-0x0")
        XCTAssertFalse(k.hasVirtualKeyCode)
        XCTAssertEqual(k.character, forwardDelete)
    }

    func testThreePartKeyCodeZeroWithLetterAIsTrusted() {
        let k = iTermKeystroke(serialized: "0x61-0x40000-0x0")
        XCTAssertTrue(k.hasVirtualKeyCode)
        XCTAssertEqual(k.virtualKeyCode, keyCodeA)
    }

    func testThreePartKeyCodeZeroWithCapitalAIsTrusted() {
        XCTAssertTrue(iTermKeystroke(serialized: "0x41-0x120000-0x0").hasVirtualKeyCode)
    }

    func testThreePartKeyCodeZeroWithOtherLetterDependsOnEnabledLayouts() {
        XCTAssertFalse(iTermKeystroke(serialized: "0x71-0x40000-0x0").hasVirtualKeyCode)
        // As though AZERTY, where the A key types q, were enabled.
        iTermKeyCodeZeroCharacters.testingOverride = [NSNumber(value: 0x71)]
        XCTAssertTrue(iTermKeystroke(serialized: "0x71-0x40000-0x0").hasVirtualKeyCode)
    }

    func testThreePartKeyCodeZeroOnNumericKeypadHasNoKeyCode() {
        XCTAssertFalse(iTermKeystroke(serialized: "0x61-0x200000-0x0").hasVirtualKeyCode)
        XCTAssertFalse(iTermKeystroke(serialized: "0x30-0x200000-0x0").hasVirtualKeyCode)
    }

    func testThreePartNonzeroKeyCodeIsTrusted() {
        let k = iTermKeystroke(serialized: "0xf728-0x0-0x75")
        XCTAssertTrue(k.hasVirtualKeyCode)
        XCTAssertEqual(k.virtualKeyCode, keyCodeForwardDelete)
    }

    func testFourPartKeyCodeZeroIsTrustedRegardlessOfCharacter() {
        let k = iTermKeystroke(serialized: "0x3b-0x40000-0x0-0x1")
        XCTAssertTrue(k.hasVirtualKeyCode)
        XCTAssertEqual(k.virtualKeyCode, keyCodeA)
        XCTAssertEqual(k.character, 0x3b)
    }

    func testTwoPartHasNoKeyCode() {
        XCTAssertFalse(iTermKeystroke(serialized: "0x61-0x40000").hasVirtualKeyCode)
    }

    // MARK: - Serialization

    func testKeystrokeWithKeyCodeSerializesAsFourParts() {
        let k = keystroke(keyCode: keyCodeA, character: 0x61, modifiers: .control)
        XCTAssertEqual(k.serialized, "0x61-0x40000-0x0-0x1")
        XCTAssertTrue(iTermKeystroke(serialized: k.serialized).hasVirtualKeyCode)
    }

    func testKeystrokeWithoutKeyCodeSerializesAsTwoParts() {
        let k = iTermKeystroke(virtualKeyCode: 0,
                               hasKeyCode: false,
                               modifierFlags: .control,
                               character: 0x61,
                               modifiedCharacter: 0x61)
        XCTAssertEqual(k.serialized, "0x61-0x40000")
    }

    // Older versions parse keys with sscanf("%x-%llx-%x"), so the fourth part must not confuse them.
    func testOldParserReadsFirstThreePartsOfFourPartKey() {
        var character: UInt32 = 0
        var flags: UInt64 = 0
        var keyCode: UInt32 = 0xffff
        let count = withUnsafeMutablePointer(to: &character) { c in
            withUnsafeMutablePointer(to: &flags) { f in
                withUnsafeMutablePointer(to: &keyCode) { k in
                    "0x3b-0x40000-0x0-0x1".withCString { s in
                        withVaList([c, f, k]) { vsscanf(s, "%x-%llx-%x", $0) }
                    }
                }
            }
        }
        XCTAssertEqual(count, 3)
        XCTAssertEqual(character, 0x3b)
        XCTAssertEqual(flags, 0x40000)
        XCTAssertEqual(keyCode, 0)
    }

    func testModernSerializationForThreePartKey() {
        XCTAssertEqual(iTermKeystroke.modernSerialization(forThreePartKey: "0xf728-0x0-0x0"), "0xf728-0x0")
        XCTAssertEqual(iTermKeystroke.modernSerialization(forThreePartKey: "0x61-0x40000-0x0"), "0x61-0x40000-0x0-0x1")
        XCTAssertEqual(iTermKeystroke.modernSerialization(forThreePartKey: "0xf728-0x0-0x75"), "0xf728-0x0-0x75-0x1")
        XCTAssertNil(iTermKeystroke.modernSerialization(forThreePartKey: "0x61-0x40000"))
        XCTAssertNil(iTermKeystroke.modernSerialization(forThreePartKey: "0x61-0x40000-0x0-0x1"))
        XCTAssertNil(iTermKeystroke.modernSerialization(forThreePartKey: ":0x21:0x0"))
        XCTAssertNil(iTermKeystroke.modernSerialization(forThreePartKey: "touchbar:abc"))
    }

    // Whether to trust keycode 0 with a letter other than a/A depends on the enabled layouts, so
    // it must not be made permanent: the same settings may be used on another machine.
    func testModernSerializationLeavesLayoutDependentKeyCodeZeroAlone() {
        XCTAssertNil(iTermKeystroke.modernSerialization(forThreePartKey: "0x71-0x40000-0x0"))
        iTermKeyCodeZeroCharacters.testingOverride = [NSNumber(value: 0x71)]
        XCTAssertNil(iTermKeystroke.modernSerialization(forThreePartKey: "0x71-0x40000-0x0"))
        XCTAssertNil(iTermKeystroke.modernSerialization(forThreePartKey: "0x444-0x40000-0x0"))
    }

    func testModernSerializationDropsKeyCodeZeroForCharactersTheAKeyCannotType() {
        XCTAssertEqual(iTermKeystroke.modernSerialization(forThreePartKey: "0xf729-0x40000-0x0"), "0xf729-0x40000")
        XCTAssertEqual(iTermKeystroke.modernSerialization(forThreePartKey: "0x3-0x200000-0x0"), "0x3-0x200000")
        XCTAssertEqual(iTermKeystroke.modernSerialization(forThreePartKey: "0x30-0x200000-0x0"), "0x30-0x200000")
        XCTAssertEqual(iTermKeystroke.modernSerialization(forThreePartKey: "0x7f-0x80000-0x0"), "0x7f-0x80000")
    }

    // MARK: - Matching by physical key (issue 13110)

    func testPlainAMatchesNothingWhenOnlyUntrustedKeyCodeZeroBindingExists() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyLanguageAgnosticKeyBindings)
        let dict = dictionary("0xf728-0x0-0x0")
        XCTAssertNil(keystroke(keyCode: keyCodeA, character: 0x61).key(inBindingDictionary: dict))
    }

    func testUntrustedKeyCodeZeroBindingStillMatchesByCharacterWithPhysicalKeys() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyLanguageAgnosticKeyBindings)
        let dict = dictionary("0xf728-0x80000-0x0")
        let pressed = keystroke(keyCode: keyCodeForwardDelete, character: forwardDelete, modifiers: .option)
        XCTAssertEqual(pressed.key(inBindingDictionary: dict), "0xf728-0x80000-0x0")
    }

    func testUntrustedKeyCodeZeroBindingStillMatchesByCharacterWithoutPhysicalKeys() {
        iTermPreferences.setBool(false, forKey: kPreferenceKeyLanguageAgnosticKeyBindings)
        let dict = dictionary("0xf728-0x80000-0x0")
        let pressed = keystroke(keyCode: keyCodeForwardDelete, character: forwardDelete, modifiers: .option)
        XCTAssertEqual(pressed.key(inBindingDictionary: dict), "0xf728-0x80000-0x0")
    }

    func testThreePartABindingMatchesPhysicalAOnAnotherLayout() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyLanguageAgnosticKeyBindings)
        let dict = dictionary("0x61-0x40000-0x0")
        // The A key on a Russian layout.
        let pressed = keystroke(keyCode: keyCodeA, character: 0x444, modifiers: .control)
        XCTAssertEqual(pressed.key(inBindingDictionary: dict), "0x61-0x40000-0x0")
    }

    func testFourPartBindingOnKeyCodeZeroMatchesPhysicalA() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyLanguageAgnosticKeyBindings)
        let dict = dictionary("0x71-0x40000-0x0-0x1")
        let pressed = keystroke(keyCode: keyCodeA, character: 0x61, modifiers: .control)
        XCTAssertEqual(pressed.key(inBindingDictionary: dict), "0x71-0x40000-0x0-0x1")
    }

    func testNewABindingMatchesWithPhysicalKeys() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyLanguageAgnosticKeyBindings)
        let pressed = keystroke(keyCode: keyCodeA, character: 0x61, modifiers: .control)
        let dict = dictionary(pressed.serialized)
        XCTAssertEqual(pressed.key(inBindingDictionary: dict), pressed.serialized)
    }

    func testCtrlAIsNotAPhysicalMatchForUntrustedCtrlHome() {
        let dict = dictionary("0xf729-0x40000-0x0")
        let pressed = keystroke(keyCode: keyCodeA, character: 0x61, modifiers: .control)
        XCTAssertFalse(pressed.hasPhysicalKeyMatch(in: dict))
    }

    // MARK: - Matching by character

    func testFourPartKeystrokeFindsThreePartBinding() {
        iTermPreferences.setBool(false, forKey: kPreferenceKeyLanguageAgnosticKeyBindings)
        let dict = dictionary("0x74-0x100000-0x11")
        let pressed = keystroke(keyCode: keyCodeT, character: 0x74, modifiers: .command)
        XCTAssertEqual(pressed.key(inBindingDictionary: dict), "0x74-0x100000-0x11")
    }

    func testFourPartKeystrokeFindsFourPartBinding() {
        iTermPreferences.setBool(false, forKey: kPreferenceKeyLanguageAgnosticKeyBindings)
        let dict = dictionary("0x74-0x100000-0x11-0x1")
        let pressed = keystroke(keyCode: keyCodeT, character: 0x74, modifiers: .command)
        XCTAssertEqual(pressed.key(inBindingDictionary: dict), "0x74-0x100000-0x11-0x1")
    }

    // MARK: - Migration

    func testMigrationRewritesThreePartKeys() {
        let input: [String: Any] = [
            "0xf728-0x0-0x0": "forward delete",
            "0x61-0x40000-0x0": "ctrl-a",
            "0x5a-0x120000-0x0": "cmd-shift-z",
            "0x74-0x100000-0x11": "cmd-t",
            "0x62-0x40000": "legacy",
            "0x63-0x40000-0x8-0x1": "modern",
            ":0x21:0x0": "modified",
            "touchbar:abc": "touchbar"
        ]
        let migrated = iTermKeyBindingFormatMigration.migratedKeyMappings(input)
        let expected: [String: String] = [
            "0xf728-0x0": "forward delete",
            "0x61-0x40000-0x0-0x1": "ctrl-a",
            "0x5a-0x120000-0x0": "cmd-shift-z",
            "0x74-0x100000-0x11-0x1": "cmd-t",
            "0x62-0x40000": "legacy",
            "0x63-0x40000-0x8-0x1": "modern",
            ":0x21:0x0": "modified",
            "touchbar:abc": "touchbar"
        ]
        XCTAssertEqual(migrated as? [String: String], expected)
    }

    func testMigrationPrefersExistingModernKey() {
        let input: [String: Any] = [
            "0xf728-0x0-0x0": "old",
            "0xf728-0x0": "existing"
        ]
        let migrated = iTermKeyBindingFormatMigration.migratedKeyMappings(input)
        XCTAssertEqual(migrated as? [String: String], ["0xf728-0x0": "existing"])
    }

    func testMigrationReturnsNilWhenNothingToDo() {
        let input: [String: Any] = [
            "0x62-0x40000": "legacy",
            "0x63-0x40000-0x8-0x1": "modern"
        ]
        XCTAssertNil(iTermKeyBindingFormatMigration.migratedKeyMappings(input))
        XCTAssertNil(iTermKeyBindingFormatMigration.migratedKeyMappings(nil))
    }
}
