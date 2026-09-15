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
}
