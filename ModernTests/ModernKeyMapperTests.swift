//
//  ModernKeyMapperTests.swift
//  iTerm2
//

import Carbon.HIToolbox
import XCTest
@testable import iTerm2SharedARC

final class ModernKeyMapperTests: XCTestCase {
    func testPC101BaseLayoutMapsANSIKeys() {
        let expected: [(virtualKeyCode: Int, scalar: Unicode.Scalar)] = [
            (kVK_ANSI_A, "a"),
            (kVK_ANSI_S, "s"),
            (kVK_ANSI_D, "d"),
            (kVK_ANSI_F, "f"),
            (kVK_ANSI_H, "h"),
            (kVK_ANSI_G, "g"),
            (kVK_ANSI_Z, "z"),
            (kVK_ANSI_X, "x"),
            (kVK_ANSI_C, "c"),
            (kVK_ANSI_V, "v"),
            (kVK_ANSI_B, "b"),
            (kVK_ANSI_Q, "q"),
            (kVK_ANSI_W, "w"),
            (kVK_ANSI_E, "e"),
            (kVK_ANSI_R, "r"),
            (kVK_ANSI_Y, "y"),
            (kVK_ANSI_T, "t"),
            (kVK_ANSI_1, "1"),
            (kVK_ANSI_2, "2"),
            (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"),
            (kVK_ANSI_6, "6"),
            (kVK_ANSI_5, "5"),
            (kVK_ANSI_Equal, "="),
            (kVK_ANSI_9, "9"),
            (kVK_ANSI_7, "7"),
            (kVK_ANSI_Minus, "-"),
            (kVK_ANSI_8, "8"),
            (kVK_ANSI_0, "0"),
            (kVK_ANSI_RightBracket, "]"),
            (kVK_ANSI_O, "o"),
            (kVK_ANSI_U, "u"),
            (kVK_ANSI_LeftBracket, "["),
            (kVK_ANSI_I, "i"),
            (kVK_ANSI_P, "p"),
            (kVK_ANSI_L, "l"),
            (kVK_ANSI_J, "j"),
            (kVK_ANSI_Quote, "'"),
            (kVK_ANSI_K, "k"),
            (kVK_ANSI_Semicolon, ";"),
            (kVK_ANSI_Backslash, "\\"),
            (kVK_ANSI_Comma, ","),
            (kVK_ANSI_Slash, "/"),
            (kVK_ANSI_N, "n"),
            (kVK_ANSI_M, "m"),
            (kVK_ANSI_Period, "."),
            (kVK_Space, " "),
            (kVK_ANSI_Grave, "`")
        ]

        for item in expected {
            XCTAssertEqual(
                pc101BaseLayoutKeyCode(for: UInt16(item.virtualKeyCode)),
                item.scalar.value,
                "virtual key code \(item.virtualKeyCode)"
            )
        }
    }

    func testPC101BaseLayoutRejectsNonANSIKey() {
        XCTAssertNil(pc101BaseLayoutKeyCode(for: UInt16(kVK_ISO_Section)))
    }

    // MARK: - kittyAlternateKeyComponents

    // Regression: an ISO/JIS-only key has no PC-101 position, so its
    // base-layout code is 0. With shift held it must not be emitted as a
    // literal 0 in the third subparam.
    func testAlternateKeysOmitsZeroBaseWithShift() {
        // § key: primary 167, shifted 177, no base-layout position.
        XCTAssertEqual(
            kittyAlternateKeyComponents(csiUNumber: 167,
                                        shiftedKeyCode: 177,
                                        baseLayoutKeyCode: 0,
                                        shiftReported: true),
            [167, 177])
    }

    func testAlternateKeysOmitsZeroBaseWithShiftAndNoShifted() {
        XCTAssertEqual(
            kittyAlternateKeyComponents(csiUNumber: 167,
                                        shiftedKeyCode: nil,
                                        baseLayoutKeyCode: 0,
                                        shiftReported: true),
            [167])
    }

    func testAlternateKeysOmitsZeroBaseWithoutShift() {
        XCTAssertEqual(
            kittyAlternateKeyComponents(csiUNumber: 167,
                                        shiftedKeyCode: nil,
                                        baseLayoutKeyCode: 0,
                                        shiftReported: false),
            [167])
    }

    // Non-US layout: the physical C key on a Russian layout produces с
    // (primary) but its base-layout position is c (99). Without shift, the
    // base alternate is reported in the third subparam with the shifted slot
    // left empty.
    func testAlternateKeysReportsBaseWithoutShift() {
        XCTAssertEqual(
            kittyAlternateKeyComponents(csiUNumber: 1089,
                                        shiftedKeyCode: nil,
                                        baseLayoutKeyCode: 99,
                                        shiftReported: false),
            [1089, nil, 99])
    }

    // With shift, both the shifted alternate and the differing base are
    // reported.
    func testAlternateKeysReportsShiftedAndBaseWithShift() {
        XCTAssertEqual(
            kittyAlternateKeyComponents(csiUNumber: 1089,
                                        shiftedKeyCode: 1057,
                                        baseLayoutKeyCode: 99,
                                        shiftReported: true),
            [1089, 1057, 99])
    }

    // A US-layout letter: primary equals base, so no base alternate. With
    // shift held the shifted alternate is still reported.
    func testAlternateKeysReportsOnlyShiftedWhenBaseMatchesPrimary() {
        XCTAssertEqual(
            kittyAlternateKeyComponents(csiUNumber: 99,
                                        shiftedKeyCode: 67,
                                        baseLayoutKeyCode: 99,
                                        shiftReported: true),
            [99, 67])
    }

    // Nothing to add: primary equals base and there is no distinct shifted
    // code, so only the primary is reported.
    func testAlternateKeysReportsOnlyPrimaryWhenNothingDiffers() {
        XCTAssertEqual(
            kittyAlternateKeyComponents(csiUNumber: 99,
                                        shiftedKeyCode: 99,
                                        baseLayoutKeyCode: 99,
                                        shiftReported: true),
            [99])
    }
}

// Caps Lock under the Kitty protocol, including macOS's “Use the Caps Lock key
// to switch to and from the last used Latin input source” setting. With that
// setting on, the physical key (keyCode 57) is followed by synthetic
// flags-changed events with keyCode 255 that undo or redo the lock change. The
// event sequences below were recorded with the replay harness. Issue 13136.
final class ModernKeyMapperCapsLockTests: XCTestCase {
    private static let physical = UInt16(kVK_CapsLock)
    private static let synthetic: UInt16 = 255
    private static let modes8: VT100TerminalKeyReportingFlags = [.reportAllKeysAsEscapeCodes]
    private static let modes10: VT100TerminalKeyReportingFlags = [.reportAllKeysAsEscapeCodes, .reportAllEventTypes]

    // Feeds flags-changed events to a mapper the way iTermApplication does,
    // carrying the previous event's flags forward.
    private final class Driver {
        let mapper = ModernKeyMapper()
        private var previousFlags: NSEvent.ModifierFlags

        init(flags: VT100TerminalKeyReportingFlags, switchesInputSource: Bool, locked: Bool) {
            mapper.flags = flags
            mapper.capsLockSwitchesInputSource = { switchesInputSource }
            previousFlags = Driver.modifierFlags(locked: locked)
        }

        private static func modifierFlags(locked: Bool) -> NSEvent.ModifierFlags {
            // 0x100 is set on every recorded event.
            return NSEvent.ModifierFlags(rawValue: locked ? 0x10100 : 0x100)
        }

        func send(_ keyCode: UInt16, locked: Bool) -> String {
            let flags = Driver.modifierFlags(locked: locked)
            let event = NSEvent.keyEvent(with: .flagsChanged,
                                         location: .zero,
                                         modifierFlags: flags,
                                         timestamp: 0,
                                         windowNumber: 0,
                                         context: nil,
                                         characters: "",
                                         charactersIgnoringModifiers: "",
                                         isARepeat: false,
                                         keyCode: keyCode)!
            event.it_previousFlags = previousFlags
            previousFlags = flags
            return mapper.keyMapperString(forPreCocoaEvent: event) ?? ""
        }
    }

    private func driver(_ flags: VT100TerminalKeyReportingFlags = modes10,
                        switchesInputSource: Bool = true,
                        locked: Bool) -> Driver {
        return Driver(flags: flags, switchesInputSource: switchesInputSource, locked: locked)
    }

    private let lockReport = "\u{1b}[57358;65u\u{1b}[57358;65:3u"
    private let unlockReport = "\u{1b}[57358u\u{1b}[57358;1:3u"

    // MARK: - Setting on

    // A tap switches the input source. It is not a Caps Lock key press as far
    // as the application is concerned, so nothing is reported.
    func testTapThatSwitchesInputSourceReportsNothing() {
        let d = driver(locked: false)
        XCTAssertEqual(d.send(Self.physical, locked: true), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: false), "")
        XCTAssertEqual(d.send(Self.physical, locked: false), "")
    }

    // Holding locks after about 500 ms via a second synthetic event. There is
    // no key-up event, so the press and release are both sent then.
    func testHoldThatLocksReportsPressAndReleaseWhenLockEngages() {
        let d = driver(locked: false)
        XCTAssertEqual(d.send(Self.physical, locked: true), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: false), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: true), lockReport)
    }

    // A tap while locked always unlocks. The unlock arrives after the
    // physical key-up.
    func testTapWhileLockedReportsUnlock() {
        let d = driver(locked: true)
        XCTAssertEqual(d.send(Self.physical, locked: false), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: true), "")
        XCTAssertEqual(d.send(Self.physical, locked: true), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: false), unlockReport)
    }

    // Recorded once: a lock with no physical key events at all.
    func testLockWithOnlySyntheticEventsReportsLock() {
        let d = driver(locked: false)
        XCTAssertEqual(d.send(Self.synthetic, locked: false), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: true), lockReport)
    }

    func testHoldThatUnlocksReportsPressAndReleaseWhenLockReleases() {
        let d = driver(locked: true)
        XCTAssertEqual(d.send(Self.physical, locked: false), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: true), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: false), unlockReport)
    }

    func testHoldThatLocksReportsOnlyPressWithoutEventTypes() {
        let d = driver(Self.modes8, locked: false)
        XCTAssertEqual(d.send(Self.physical, locked: true), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: false), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: true), "\u{1b}[57358;65u")
    }

    func testHoldThatUnlocksReportsOnlyPressWithoutEventTypes() {
        let d = driver(Self.modes8, locked: true)
        XCTAssertEqual(d.send(Self.physical, locked: false), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: true), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: false), "\u{1b}[57358u")
    }

    // The same sequence as the replay harness: each gesture starts where the
    // previous one left off.
    func testConsecutiveGestures() {
        let d = driver(locked: false)
        // Tap switches input source.
        XCTAssertEqual(d.send(Self.physical, locked: true), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: false), "")
        XCTAssertEqual(d.send(Self.physical, locked: false), "")
        // Hold locks.
        XCTAssertEqual(d.send(Self.physical, locked: true), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: false), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: true), lockReport)
        // Tap unlocks.
        XCTAssertEqual(d.send(Self.physical, locked: false), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: true), "")
        XCTAssertEqual(d.send(Self.physical, locked: true), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: false), unlockReport)
        // Lock with only synthetic events.
        XCTAssertEqual(d.send(Self.synthetic, locked: false), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: true), lockReport)
        // Hold unlocks.
        XCTAssertEqual(d.send(Self.physical, locked: false), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: true), "")
        XCTAssertEqual(d.send(Self.synthetic, locked: false), unlockReport)
    }

    // MARK: - Setting off

    // Unchanged behavior: each toggle is a single physical event. Reporting an
    // unlock as a release is a known issue to be fixed separately.
    func testSettingOffLockReportsPress() {
        let d = driver(switchesInputSource: false, locked: false)
        XCTAssertEqual(d.send(Self.physical, locked: true), "\u{1b}[57358;65u")
    }

    func testSettingOffUnlockReportsRelease() {
        let d = driver(switchesInputSource: false, locked: true)
        XCTAssertEqual(d.send(Self.physical, locked: false), "\u{1b}[57358;1:3u")
    }

    // A lock change from a key code that isn't a modifier key is reported as
    // Caps Lock rather than with no key number (\e[65u or \e[1:3u).
    func testSettingOffSyntheticLockChangeReportsCapsLockKeyNumber() {
        let d = driver(switchesInputSource: false, locked: false)
        XCTAssertEqual(d.send(Self.synthetic, locked: true), "\u{1b}[57358;65u")
        XCTAssertEqual(d.send(Self.synthetic, locked: false), "\u{1b}[57358;1:3u")
    }
}
