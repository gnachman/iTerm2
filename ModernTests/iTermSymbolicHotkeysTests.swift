//
//  iTermSymbolicHotkeysTests.swift
//  ModernTests
//
//  macOS keeps the Shift (“slow”) variants of Mission Control and Spaces
//  shortcuts enabled even though they no longer do anything. Deferring to them
//  swallowed Ctrl-Shift-Arrow (issue 13202), so they must not count as bound.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermSymbolicHotkeysTests: XCTestCase {
    private let upArrow: UInt16 = 126
    private let ctrlFn = 8650752
    private let ctrlShiftFn = 8781824

    // Real event flags from the issue 13202 debug log: Fn, NumericPad,
    // Control, Shift, plus device-dependent bits.
    private let ctrlShiftUpEventFlags = NSEvent.ModifierFlags(rawValue: 10879235)

    private func entry(keyCode: UInt16, modifiers: Int, enabled: Bool = true) -> [String: Any] {
        return ["enabled": NSNumber(value: enabled),
                "value": ["parameters": [65535, Int(keyCode), modifiers],
                          "type": "standard"]]
    }

    private var ctrlUpEventFlags: NSEvent.ModifierFlags {
        return ctrlShiftUpEventFlags.subtracting(.shift)
    }

    func testShiftVariantOfMissionControlIsIgnored() {
        let hotkeys: [AnyHashable: Any] = ["32": entry(keyCode: upArrow, modifiers: ctrlFn),
                                           "34": entry(keyCode: upArrow, modifiers: ctrlShiftFn)]
        XCTAssertFalse(iTermSymbolicHotkeys.haveBoundKey(keyCode: upArrow,
                                                         modifiers: ctrlShiftUpEventFlags,
                                                         hotkeys: hotkeys))
    }

    func testBaseMissionControlShortcutIsStillBound() {
        let hotkeys: [AnyHashable: Any] = ["32": entry(keyCode: upArrow, modifiers: ctrlFn),
                                           "34": entry(keyCode: upArrow, modifiers: ctrlShiftFn)]
        XCTAssertTrue(iTermSymbolicHotkeys.haveBoundKey(keyCode: upArrow,
                                                        modifiers: ctrlUpEventFlags,
                                                        hotkeys: hotkeys))
    }

    func testAllShiftVariantsAreIgnored() {
        for id in ["34", "35", "37", "63", "80", "82"] {
            let hotkeys: [AnyHashable: Any] = [id: entry(keyCode: upArrow, modifiers: ctrlShiftFn)]
            XCTAssertFalse(iTermSymbolicHotkeys.haveBoundKey(keyCode: upArrow,
                                                             modifiers: ctrlShiftUpEventFlags,
                                                             hotkeys: hotkeys),
                           "id \(id)")
        }
    }

    func testOtherIDWithSameShortcutIsBound() {
        // A user-assigned shortcut on a real action still wins.
        let hotkeys: [AnyHashable: Any] = ["118": entry(keyCode: upArrow, modifiers: ctrlShiftFn)]
        XCTAssertTrue(iTermSymbolicHotkeys.haveBoundKey(keyCode: upArrow,
                                                        modifiers: ctrlShiftUpEventFlags,
                                                        hotkeys: hotkeys))
    }

    func testDisabledEntryIsNotBound() {
        let hotkeys: [AnyHashable: Any] = ["32": entry(keyCode: upArrow, modifiers: ctrlFn, enabled: false)]
        XCTAssertFalse(iTermSymbolicHotkeys.haveBoundKey(keyCode: upArrow,
                                                         modifiers: ctrlUpEventFlags,
                                                         hotkeys: hotkeys))
    }
}
