//
//  iTermKeystrokeBindingTests.swift
//  iTerm2
//
//  Test for key binding matching when charactersIgnoringModifiers differs
//  from the recorded binding due to keyboard layout / input method state.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermKeystrokeBindingTests: XCTestCase {

    /// kVK_ANSI_Grave = 0x32 (50), the physical backtick/tilde key on US keyboards.
    /// On Chinese/Pinyin layouts the same physical key reports a different
    /// charactersIgnoringModifiers value (0xb7 = middle dot ·) in some input
    /// modes and 0x60 (backtick `) in others.
    private let graveKeyCode: Int32 = 0x32
    private let cmdModifier: Int64 = 0x100000  // NSEventModifierFlagCommand

    // MARK: - Binding created with Chinese-layout character (0xb7)

    func testBindingRecordedWithChineseCharMatchesUSCharPress() {
        // Simulate binding created when keyboard reports 0xb7 for the backtick key.
        let bindingKey = "0xb7-0x100000-0x32"
        let bindingValue: NSDictionary = [
            "Version": 2,
            "Apply Mode": 0,
            "Action": 30,
            "Text": "",
            "Escaping": 0
        ]
        let dict: NSDictionary = [bindingKey: bindingValue]

        // Simulate the same key pressed later when charactersIgnoringModifiers
        // returns 0x60 (standard US backtick) — e.g. after text input changed
        // the input method state.
        let keystroke = iTermKeystroke(
            virtualKeyCode: Int(graveKeyCode),
            hasKeyCode: true,
            modifierFlags: UInt(cmdModifier),
            character: 0x60,         // US backtick character
            modifiedCharacter: 0x60
        )

        let foundKey = keystroke.keyInBindingDictionary(dict as! [String: NSDictionary])

        // Before the fix this returned nil because the serialized key
        // 0x60-0x100000-0x32 did not match the stored 0xb7-0x100000-0x32.
        // After the fix the portableSerialized fallback (*-0x100000-0x32)
        // matches regardless of the character field.
        XCTAssertNotNil(foundKey,
            "Keystroke (char=0x60) should match binding (char=0xb7) " +
            "via portableSerialized fallback. If this fails, the " +
            "language-agnostic fallback in keyInBindingDictionary: is broken.")
        XCTAssertEqual(foundKey, bindingKey)
    }

    // MARK: - Exact match still works (regression guard)

    func testExactMatchStillWorks() {
        let bindingKey = "0xb7-0x100000-0x32"
        let dict: NSDictionary = [bindingKey: ["Action": 30]]

        let keystroke = iTermKeystroke(
            virtualKeyCode: Int(graveKeyCode),
            hasKeyCode: true,
            modifierFlags: UInt(cmdModifier),
            character: 0xb7,
            modifiedCharacter: 0xb7
        )

        XCTAssertEqual(keystroke.keyInBindingDictionary(dict as! [String: NSDictionary]),
                       bindingKey)
    }

    // MARK: - Different virtual key code should NOT match

    func testDifferentKeyCodeDoesNotMatch() {
        let bindingKey = "0xb7-0x100000-0x32"
        let dict: NSDictionary = [bindingKey: ["Action": 30]]

        // Same character and modifiers, but different physical key (kVK_ANSI_1 = 0x12)
        let keystroke = iTermKeystroke(
            virtualKeyCode: 0x12,
            hasKeyCode: true,
            modifierFlags: UInt(cmdModifier),
            character: 0x60,
            modifiedCharacter: 0x60
        )

        XCTAssertNil(keystroke.keyInBindingDictionary(dict as! [String: NSDictionary]),
                     "Different virtual key code should never match")
    }

    // MARK: - Legacy binding (no virtual key code) still works

    func testLegacyBindingWithoutKeyCodeStillWorks() {
        // Binding stored without virtual key code component
        let bindingKey = "0xb7-0x100000"
        let dict: NSDictionary = [bindingKey: ["Action": 30]]

        let keystroke = iTermKeystroke(
            virtualKeyCode: Int(graveKeyCode),
            hasKeyCode: true,
            modifierFlags: UInt(cmdModifier),
            character: 0xb7,
            modifiedCharacter: 0xb7
        )

        XCTAssertEqual(keystroke.keyInBindingDictionary(dict as! [String: NSDictionary]),
                       bindingKey)
    }
}
