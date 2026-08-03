//
//  BidiMirrorSelectionTests.swift
//  ModernTests
//
//  UBA rule L4 mirroring must be driven by CoreText's real per-character
//  bidi resolution, not by run direction. A bracket that brackets an embedded
//  left-to-right run (e.g. Persian «(English)») sits in an RTL run for
//  positioning but must NOT be mirrored, whereas a bracket in pure RTL text
//  must be. These tests check the per-cell mirror decision directly.
//

import XCTest
@testable import iTerm2SharedARC

class BidiMirrorSelectionTests: XCTestCase {
    private func setBidiPreference(_ enabled: Bool) {
        iTermPreferences.setBool(enabled, forKey: kPreferenceKeyBidi)
        let deadline = Date().addingTimeInterval(0.5)
        while iTermPreferences.bidiEnabled() != enabled && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
    }

    override func setUp() { super.setUp(); setBidiPreference(true) }
    override func tearDown() { setBidiPreference(false); super.tearDown() }

    // For an all-BMP, no-combining string, cell index == UTF-16 index.
    private func info(_ s: String) -> BidiDisplayInfoObjc? {
        let sca = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        return BidiDisplayInfoObjc(sca)
    }

    func testPureRTLParensAreMirrored() {
        // «(بله)» — parens in pure RTL context must mirror.
        let s = "متن (بله) دیگر"
        guard let info = info(s) else { return XCTFail("no bidi info") }
        let open = Int32((s as NSString).range(of: "(").location)
        let close = Int32((s as NSString).range(of: ")").location)
        XCTAssertTrue(info.mirrorsSourceCell(open), "open paren in RTL must mirror")
        XCTAssertTrue(info.mirrorsSourceCell(close), "close paren in RTL must mirror")
    }

    func testParensAroundEnglishAreNotMirrored() {
        // Persian «(English)» — the brackets wrap an LTR run and must NOT mirror.
        let s = "توی (Tempelhofer) قدیمی"
        guard let info = info(s) else { return XCTFail("no bidi info") }
        let open = Int32((s as NSString).range(of: "(").location)
        let close = Int32((s as NSString).range(of: ")").location)
        XCTAssertFalse(info.mirrorsSourceCell(open),
                       "open paren bracketing English must not mirror")
        XCTAssertFalse(info.mirrorsSourceCell(close),
                       "close paren bracketing English must not mirror")
    }

    func testBothInSameLine() {
        // A pure-RTL paren pair and an English-bracketing pair on one line.
        let s = "متن (بله) و (Feld) تمام"
        guard let info = info(s) else { return XCTFail("no bidi info") }
        let ns = s as NSString
        let rtlOpen = Int32(ns.range(of: "(بله").location)
        let enOpen = Int32(ns.range(of: "(Feld").location)
        XCTAssertTrue(info.mirrorsSourceCell(rtlOpen), "RTL paren mirrors")
        XCTAssertFalse(info.mirrorsSourceCell(enOpen), "English paren does not mirror")
    }
}
