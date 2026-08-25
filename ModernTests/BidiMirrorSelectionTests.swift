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

    private var savedDetect: Any?
    override func setUp() {
        super.setUp()
        setBidiPreference(true)
        // The assertions below describe the detect-OFF configuration (see the
        // NOTE); force it so a leaked default from another suite (or a crashed
        // run's skipped tearDown) can't flip the expected mirroring.
        savedDetect = iTermUserDefaults.userDefaults().object(forKey: "DetectParagraphDirection")
        iTermUserDefaults.userDefaults().set(false, forKey: "DetectParagraphDirection")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
    }
    override func tearDown() {
        if let v = savedDetect { iTermUserDefaults.userDefaults().set(v, forKey: "DetectParagraphDirection") }
        else { iTermUserDefaults.userDefaults().removeObject(forKey: "DetectParagraphDirection") }
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        setBidiPreference(false)
        super.tearDown()
    }

    // NOTE ON CONFIGURATION: correctness here is an INVARIANT, not a fixed
    // flag. CoreText both repositions a bracket pair and mirrors its glyphs
    // when the pair resolves RTL; the two cancel out to a correct-facing
    // pair. So the mirror flag must equal "the pair was repositioned",
    // whatever CoreText decides for a given base direction. (An RTL-first
    // line gets an RTL base from the payload isolate even with auto-detect
    // OFF, so English-bracketing pairs may legitimately reposition+mirror.)
    private func assertMirrorMatchesRepositioning(_ info: BidiDisplayInfoObjc,
                                                  open: Int32,
                                                  close: Int32,
                                                  file: StaticString = #filePath,
                                                  line: UInt = #line) {
        let swapped = info.visualForLogical(open) > info.visualForLogical(close)
        XCTAssertEqual(info.mirrorsSourceCell(open), swapped,
                       "open paren mirror flag must match repositioning",
                       file: file, line: line)
        XCTAssertEqual(info.mirrorsSourceCell(close), swapped,
                       "close paren mirror flag must match repositioning",
                       file: file, line: line)
    }

    // For an all-BMP, no-combining string, cell index == UTF-16 index.
    private func info(_ s: String) -> BidiDisplayInfoObjc? {
        let sca = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        return BidiDisplayInfoObjc(sca)
    }

    func testPureRTLParensAreMirrored() {
        // «(بله)»: parens in pure RTL context must mirror.
        let s = "متن (بله) دیگر"
        guard let info = info(s) else { return XCTFail("no bidi info") }
        let open = Int32((s as NSString).range(of: "(").location)
        let close = Int32((s as NSString).range(of: ")").location)
        XCTAssertTrue(info.mirrorsSourceCell(open), "open paren in RTL must mirror")
        XCTAssertTrue(info.mirrorsSourceCell(close), "close paren in RTL must mirror")
        assertMirrorMatchesRepositioning(info, open: open, close: close)
    }

    func testParensAroundEnglishMatchRepositioning() {
        // Persian «(English)»: whether the pair repositions depends on the
        // base direction CoreText resolves; the mirror flag must track it.
        let s = "توی (Tempelhofer) قدیمی"
        guard let info = info(s) else { return XCTFail("no bidi info") }
        let open = Int32((s as NSString).range(of: "(").location)
        let close = Int32((s as NSString).range(of: ")").location)
        assertMirrorMatchesRepositioning(info, open: open, close: close)
    }

    func testBothInSameLine() {
        // A pure-RTL paren pair and an English-bracketing pair on one line.
        let s = "متن (بله) و (Feld) تمام"
        guard let info = info(s) else { return XCTFail("no bidi info") }
        let ns = s as NSString
        let rtlOpen = Int32(ns.range(of: "(بله").location)
        let rtlClose = rtlOpen + 4
        let enOpen = Int32(ns.range(of: "(Feld").location)
        let enClose = enOpen + 5
        XCTAssertTrue(info.mirrorsSourceCell(rtlOpen), "RTL paren mirrors")
        assertMirrorMatchesRepositioning(info, open: rtlOpen, close: rtlClose)
        assertMirrorMatchesRepositioning(info, open: enOpen, close: enClose)
    }
}
