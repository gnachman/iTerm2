//
//  BidiIslandMirrorTests.swift
//  ModernTests
//
//  Covers the Latin-island feature (isolateLatinRunsInRTL) with paragraph
//  direction auto-detection on. An island holds an English word or phrase, its
//  interior spaces, and any brackets that wrap Latin content, so those stay
//  left-to-right and un-mirrored. A bracket that opens the following Persian
//  phrase must be left OUT of the island so it mirrors like any other bracket
//  in right-to-left text — the "School of Hip Hop (فصل …" case, where the open
//  paren was being pulled into the island and drawn un-mirrored.
//

import XCTest
@testable import iTerm2SharedARC

class BidiIslandMirrorTests: XCTestCase {
    private var savedIsolate: Any?
    private var savedDetect: Any?

    private func setBidiPreference(_ enabled: Bool) {
        iTermPreferences.setBool(enabled, forKey: kPreferenceKeyBidi)
        let deadline = Date().addingTimeInterval(0.5)
        while iTermPreferences.bidiEnabled() != enabled && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
    }

    override func setUp() {
        super.setUp()
        setBidiPreference(true)
        savedIsolate = iTermUserDefaults.userDefaults().object(forKey: "IsolateLatinRunsInRTL")
        savedDetect = iTermUserDefaults.userDefaults().object(forKey: "DetectParagraphDirection")
        iTermUserDefaults.userDefaults().set(true, forKey: "IsolateLatinRunsInRTL")
        iTermUserDefaults.userDefaults().set(true, forKey: "DetectParagraphDirection")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
    }

    override func tearDown() {
        restore("IsolateLatinRunsInRTL", savedIsolate)
        restore("DetectParagraphDirection", savedDetect)
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        setBidiPreference(false)
        super.tearDown()
    }

    private func restore(_ key: String, _ value: Any?) {
        if let value {
            iTermUserDefaults.userDefaults().set(value, forKey: key)
        } else {
            iTermUserDefaults.userDefaults().removeObject(forKey: key)
        }
    }

    // For an all-BMP, no-combining string, cell index == UTF-16 index.
    private func info(_ s: String) -> BidiDisplayInfoObjc? {
        let sca = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        return BidiDisplayInfoObjc(sca)
    }

    // Parens are drawn as typed everywhere now (never bidi-mirrored), so a paren
    // opening a Persian phrase after an English island stays «(فصل تابستان)»
    // rather than flipping to «)فصل تابستان(».
    func testParenOpeningPersianAfterIslandIsNotMirrored() {
        let s = "School of Hip Hop (فصل تابستان) در شهر"
        guard let info = info(s) else { return XCTFail("no bidi info") }
        let ns = s as NSString
        let open = Int32(ns.range(of: "(").location)
        let close = Int32(ns.range(of: ")").location)
        XCTAssertFalse(info.mirrorsSourceCell(open),
                       "paren opening a Persian phrase must not mirror (drawn as typed)")
        XCTAssertFalse(info.mirrorsSourceCell(close),
                       "paren closing a Persian phrase must not mirror (drawn as typed)")
    }

    // A parenthetical that wraps English is part of the island and stays LTR, so
    // its brackets must NOT mirror.
    func testParenWrappingEnglishDoesNotMirror() {
        let s = "مرورگر (Google Chrome) را باز کن"
        guard let info = info(s) else { return XCTFail("no bidi info") }
        let ns = s as NSString
        let open = Int32(ns.range(of: "(").location)
        let close = Int32(ns.range(of: ")").location)
        XCTAssertFalse(info.mirrorsSourceCell(open),
                       "paren wrapping English must not mirror")
        XCTAssertFalse(info.mirrorsSourceCell(close),
                       "paren wrapping English must not mirror")
    }

    // One line with both: parens draw as typed for English AND Persian content —
    // neither mirrors.
    func testEnglishAndPersianParentheticalsOnOneLine() {
        // Plain Persian words only (no combining marks) so cell == UTF-16 index.
        let s = "متن (English) و متن (فارسی)"
        guard let info = info(s) else { return XCTFail("no bidi info") }
        let ns = s as NSString
        let enOpen = Int32(ns.range(of: "(English").location)
        let faOpen = Int32(ns.range(of: "(فارسی").location)
        XCTAssertFalse(info.mirrorsSourceCell(enOpen), "English parenthetical must not mirror")
        XCTAssertFalse(info.mirrorsSourceCell(faOpen), "Persian parenthetical must not mirror (as typed)")
    }
}
