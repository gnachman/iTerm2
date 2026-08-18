//
//  iTermKeystrokePhysicalKeyMatchTests.swift
//  iTerm2
//
//  Tests for -[iTermKeystroke hasPhysicalKeyMatchInDictionary:], which detects
//  that a keystroke would match a binding on the same physical key + modifiers
//  even though its character differs (e.g. after an input-method change). This is
//  the signal used to offer to enable physical-key ("language agnostic") bindings.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermKeystrokePhysicalKeyMatchTests: XCTestCase {

    private let graveKeyCode: Int32 = 0x32   // kVK_ANSI_Grave
    private let cmd: NSEvent.ModifierFlags = .command   // 0x100000

    private func keystroke(keyCode: Int32,
                           hasKeyCode: Bool = true,
                           character: UInt32,
                           modifiers: NSEvent.ModifierFlags) -> iTermKeystroke {
        return iTermKeystroke(virtualKeyCode: keyCode,
                              hasKeyCode: hasKeyCode,
                              modifierFlags: modifiers,
                              character: character,
                              modifiedCharacter: character)
    }

    private func dictionary(_ key: String) -> [String: [AnyHashable: Any]] {
        return [key: ["Action": 30]]
    }

    // Same physical key + modifiers, different character -> match.
    func testMatchesIgnoringCharacter() {
        let dict = dictionary("0x60-0x100000-0x32")
        let pressed = keystroke(keyCode: graveKeyCode, character: 0xb7, modifiers: cmd)
        XCTAssertTrue(pressed.hasPhysicalKeyMatch(in: dict))
    }

    // Different physical key -> no match.
    func testRequiresSameKeycode() {
        let dict = dictionary("0x60-0x100000-0x32")
        let pressed = keystroke(keyCode: 0x12, character: 0xb7, modifiers: cmd)
        XCTAssertFalse(pressed.hasPhysicalKeyMatch(in: dict))
    }

    // Different modifiers -> no match.
    func testRequiresSameModifiers() {
        let dict = dictionary("0x60-0x100000-0x32")
        let pressed = keystroke(keyCode: graveKeyCode, character: 0x60, modifiers: .control)
        XCTAssertFalse(pressed.hasPhysicalKeyMatch(in: dict))
    }

    // A legacy binding with no keycode component can't be a physical-key match.
    func testIgnoresLegacyKeycodelessBindings() {
        let dict = dictionary("0xb7-0x100000")
        let pressed = keystroke(keyCode: graveKeyCode, character: 0xb7, modifiers: cmd)
        XCTAssertFalse(pressed.hasPhysicalKeyMatch(in: dict))
    }

    // A keystroke without a virtual key code never matches.
    func testKeystrokeWithoutKeycodeNeverMatches() {
        let dict = dictionary("0x60-0x100000-0x32")
        let pressed = keystroke(keyCode: 0, hasKeyCode: false, character: 0x60, modifiers: cmd)
        XCTAssertFalse(pressed.hasPhysicalKeyMatch(in: dict))
    }

    // An exact-character binding is still a physical-key match (the caller only
    // invokes this after character matching already failed, but the predicate
    // itself is character-agnostic).
    func testExactCharacterAlsoCountsAsPhysicalMatch() {
        let dict = dictionary("0x60-0x100000-0x32")
        let pressed = keystroke(keyCode: graveKeyCode, character: 0x60, modifiers: cmd)
        XCTAssertTrue(pressed.hasPhysicalKeyMatch(in: dict))
    }
}
