//
//  RTLBidiCaseTests.swift
//  ModernTests
//
//  Characterization tests for specific right-to-left (Persian/Arabic) rendering
//  cases surfaced from real agent (Claude Code) output. Each test appends a line
//  like `cat` would and records its visual (drawn) order, so both regressions and
//  fixes are caught. Cases known to be WRONG today are marked and assert the
//  current behavior; when one is fixed, its assertion fails and gets updated.
//

import XCTest
@testable import iTerm2SharedARC

private class RTLCaseFakeSession: FakeSession {
    private let syncConfig: VT100MutableScreenConfiguration = {
        let c = VT100MutableScreenConfiguration()
        c.sessionGuid = "RTLBidiCaseTests"
        return c
    }()
    override func screenRestore(_ state: VT100ScreenState) { screen?.restore(state) }
    override func screenUpdateDisplay(_ redraw: Bool) {
        guard let screen else { return }
        _ = screen.synchronize(withConfig: syncConfig, expect: nil, checkTriggers: .none,
                               resetOverflow: false, mutableState: screen.mutableState)
    }
}

class RTLBidiCaseTests: XCTestCase {
    private var session = RTLCaseFakeSession()

    private func setBidi(_ on: Bool) {
        iTermPreferences.setBool(on, forKey: kPreferenceKeyBidi)
        let deadline = Date().addingTimeInterval(0.5)
        while iTermPreferences.bidiEnabled() != on && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
    }
    override func setUp() { super.setUp(); setBidi(true) }
    override func tearDown() { setBidi(false); super.tearDown() }

    private func makeScreen(width: Int32, height: Int32 = 4) -> VT100Screen {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, m, _ in
            m.terminalEnabled = true
            m.terminal!.termType = "xterm"
            screen.destructivelySetScreenWidth(width, height: height, mutableState: m)
        })
        return screen
    }

    // The visual (drawn) order of a single appended line, read via the bidi
    // reorder map the way the renderer does.
    private func visual(_ line: String, width: Int32 = 90) -> String {
        let screen = makeScreen(width: width)
        screen.performBlock(joinedThreads: { _, m, _ in
            m.appendString(atCursor: line)
            m.populateRTLStateIfNeeded()
        })
        let sca = screen.screenCharArray(forLine: 0)
        let logical = Array(sca.stringValue)
        guard let bidi = screen.bidiInfo(forLine: 0) else { return sca.stringValue }
        var s = ""
        for v in 0..<Int(bidi.numberOfCells) {
            let lg = Int(bidi.logicalForVisual(Int32(v)))
            if lg >= 0 && lg < logical.count { s.append(logical[lg]) }
        }
        return s
    }

    // Number of occupied cells (up to the last non-empty) of an appended line.
    private func cellCount(_ line: String, width: Int32 = 40) -> Int {
        let screen = makeScreen(width: width)
        screen.performBlock(joinedThreads: { _, m, _ in m.appendString(atCursor: line) })
        let sca = screen.screenCharArray(forLine: 0)
        let l = sca.line
        var last = 0
        for i in 0..<Int(sca.length) where UInt32(l[i].code) != 0 { last = i + 1 }
        return last
    }

    // The CELL layer is correct: an above-letter combining mark merges into its
    // base cell and takes zero extra columns. Checked here for fathatan (ً U+064B),
    // hamza (ٔ U+0654), kasra (ِ U+0650), shadda (ّ U+0651), sukun (ْ U+0652) and
    // superscript-alef (ٰ U+0670). So the extra space seen with words like
    // "دقیقاً"/"قهوهٔ" is NOT a cell/bidi bug — it's a DRAWING-layer issue (the mark's
    // glyph advance in iTermTextDrawingHelper), which these bidi/cell tests cannot
    // observe. Tracked separately; needs a rendering-level test.
    func testCombiningMarksMergeIntoBaseCell() {
        let words = ["دقیقاً", "قهوهٔ", "علیّ", "کتابِ", "مِنْ", "رَحْمٰن"]
        for w in words {
            XCTAssertEqual(cellCount(w), w.count,
                           "combining mark(s) in «\(w)» must add 0 cells (cells==graphemes)")
        }
    }

    // KNOWN BUG (bidi, still open): a period after an English island lands on the
    // island's left (".burnout") instead of hugging the word ("burnout."). macOS
    // Terminal keeps it with the word. Asserts the current WRONG behavior; the day
    // it's fixed this fails — update it to assert "burnout." is contiguous.
    func testPeriodAfterEnglishIslandIsWrong() {
        let out = visual("۱. burnout. من دیگه که feel نمیشه.")
        XCTAssertTrue(out.contains(".burnout"),
                      "documents current wrong '.burnout'; fix should make it 'burnout.'. got: \(out)")
    }

    // KNOWN BUG (bidi, still open): in a mixed Persian/English/number run the ٪
    // detaches from its digits — "۷۰٪" splits so ٪ lands after "من". Correct output
    // keeps ۷۰ and ٪ together. Asserts the current WRONG behavior.
    func testPercentDetachesInMixedRunIsWrong() {
        let out = visual("۳. personality. من الان ۷۰٪ caffeine و ۲۰٪ اضطراب.")
        XCTAssertTrue(out.contains("نم٪"),
                      "documents current wrong detached ٪ after من; fix should keep ۷۰٪ together. got: \(out)")
    }

    // Regression: with Latin-run isolation ON (the setting that keeps English
    // words readable in RTL), a list marker "۱. Motivation — …" used to have its
    // period swallowed by the English island, tearing "۱." apart and drawing
    // "Motivation۱ .". The marker must stay with its number.
    func testListMarkerStaysWithNumberWhenLatinIslandsOn() {
        let d = iTermUserDefaults.userDefaults()
        let savedIso = d.object(forKey: "IsolateLatinRunsInRTL")
        let savedDet = d.object(forKey: "DetectParagraphDirection")
        d.set(true, forKey: "IsolateLatinRunsInRTL")
        d.set(true, forKey: "DetectParagraphDirection")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            if let savedIso { d.set(savedIso, forKey: "IsolateLatinRunsInRTL") } else { d.removeObject(forKey: "IsolateLatinRunsInRTL") }
            if let savedDet { d.set(savedDet, forKey: "DetectParagraphDirection") } else { d.removeObject(forKey: "DetectParagraphDirection") }
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }

        // Persian-heavy line (paragraph resolves RTL), like a real list item.
        let out = visual("۵. Small — یک تغییر در هر درخواست، پانصد خطی را فقط تأیید میکنی")
        XCTAssertFalse(out.contains("Small۵"),
                       "list marker ۵ must not glue after the English word. got: \(out)")
        // In the RTL visual the marker "۵." reads as ".۵" (۵ at the start, period
        // to its left) sitting right after the title: "Small .۵".
        XCTAssertTrue(out.contains(".۵"),
                      "marker period must stay attached to its number ۵. got: \(out)")
        // other islands unchanged
        let g = visual("متن Google Chrome باقی")
        XCTAssertTrue(g.contains("Google Chrome"), "multi-word island must stay intact. got: \(g)")
    }

    // Diagnostic: print the current visual order for each case so the expected
    // strings above can be filled in / updated.
    func testDumpCurrentBehavior() {
        let cases = [
            "period-after-english": "۱. burnout. من دیگه که feel نمیشه.",
            "percent-in-mixed":     "۳. personality. من الان ۷۰٪ caffeine و ۲۰٪ اضطراب.",
            "combining-hamza":      "مغزم تو حالت loading و تا قهوهٔ دوم ۷۰٪ خالی مانده.",
            "english-paren-period": "بگو بازم بریزم، یا رگه‌ی مشخصی می‌خوای (کاری/burnout، عشقی/situationship، یا کامل/nihilist).",
        ]
        for (name, line) in cases.sorted(by: { $0.key < $1.key }) {
            print("RTLCASE \(name)")
            print("RTLCASE   in =[\(line)]")
            print("RTLCASE   out=[\(visual(line))]")
        }
    }
}
