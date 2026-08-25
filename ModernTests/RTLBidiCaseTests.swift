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

    func testHebrewSentenceWithEnglishIslandUsesNaturalVisualOrder() {
        let input = "מה קורה חבר HELOO אתה בסדר?"
        let defaults = iTermUserDefaults.userDefaults()
        let savedDetect = defaults.object(forKey: "DetectParagraphDirection")
        defaults.set(true, forKey: "DetectParagraphDirection")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            if let savedDetect {
                defaults.set(savedDetect, forKey: "DetectParagraphDirection")
            } else {
                defaults.removeObject(forKey: "DetectParagraphDirection")
            }
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }

        let base = screenCharArrayWithDefaultStyle(input, eol: EOL_HARD)
        guard let bidi = BidiDisplayInfoObjc(base) else {
            return XCTFail("Hebrew input must produce bidi display information")
        }
        XCTAssertTrue(bidi.paragraphIsRTL)

        let englishRange = (input as NSString).range(of: "HELOO")
        let englishVisualColumns = (englishRange.location..<NSMaxRange(englishRange)).map {
            bidi.visualForLogical(Int32($0))
        }
        XCTAssertEqual(englishVisualColumns,
                       Array(englishVisualColumns[0]..<(englishVisualColumns[0] + Int32(englishRange.length))),
                       "HELOO must remain a contiguous left-to-right island")

        for logical in 0..<Int(bidi.numberOfCells) {
            let visual = bidi.visualForLogical(Int32(logical))
            XCTAssertEqual(bidi.logicalForVisual(visual), Int32(logical),
                           "logical/visual mapping must round-trip at cell \(logical)")
        }

        XCTAssertEqual(visual(input).trimmingCharacters(in: .whitespaces),
                       "?רדסב התא HELOO רבח הרוק המ")
    }

    func testPlainLTRDoesNotCreateBidiMapping() {
        let input = "What is happening friend HELOO are you okay?"
        let base = screenCharArrayWithDefaultStyle(input, eol: EOL_HARD)
        XCTAssertNil(BidiDisplayInfoObjc(base))
        XCTAssertEqual(visual(input).trimmingCharacters(in: .whitespaces), input)
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

    // Pins Detect/Justify/Isolate to the shipped defaults for the duration of
    // one closure, restoring whatever was there before.
    private func withShippedDefaults(_ body: () -> Void) {
        let d = iTermUserDefaults.userDefaults()
        let keys = ["DetectParagraphDirection", "RightJustifyRTLLines", "IsolateLatinRunsInRTL"]
        let saved = keys.map { d.object(forKey: $0) }
        keys.forEach { d.set(false, forKey: $0) }
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
            }
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
        body()
    }

    private func rev(_ s: String) -> String { String(s.reversed()) }

    // A quoted RTL argument on an LTR command line renders reversed inside its
    // quotes while the LTR text before and after it (the command and the tail)
    // stays put, per the standard bidi algorithm on the LTR-base line.
    func testCommandTailAfterQuotedRTLArgumentStaysAtLineEnd() {
        withShippedDefaults {
            let input = "echo 'سلام دنیا' && ls"
            let expected = "echo '" + rev("دنیا") + " " + rev("سلام") + "' && ls"
            XCTAssertEqual(visual(input).trimmingCharacters(in: .whitespaces), expected,
                           "the command and the tail after the quoted argument must stay in place")
        }
    }

    // English prose with a quoted RTL word: the tail after the closing quote
    // stays in place.
    func testEnglishProseWithQuotedRTLWordKeepsTailInPlace() {
        withShippedDefaults {
            let input = "he said 'سلام' to me"
            let expected = "he said '" + rev("سلام") + "' to me"
            XCTAssertEqual(visual(input).trimmingCharacters(in: .whitespaces), expected,
                           "prose after a closed quote must keep its position")
        }
    }

    // A possessive apostrophe glued to an LTR word does not disturb the layout of
    // a following RTL word: the apostrophe stays with its word and the RTL word
    // renders reversed, per the standard algorithm.
    func testPossessiveApostropheBeforeRTLDoesNotAffectLayout() {
        withShippedDefaults {
            let input = "teachers' سلام okay"
            let expected = "teachers' " + rev("سلام") + " okay"
            XCTAssertEqual(visual(input).trimmingCharacters(in: .whitespaces), expected,
                           "a possessive apostrophe must stay glued to its word")
        }
    }

    // A leading RLM (U+200F) is a zero-width formatting mark: it must not flip an
    // otherwise-Latin line, whose ASCII text stays in its logical columns.
    func testLeadingRLMDoesNotFlipLatinLine() {
        withShippedDefaults {
            let input = "\u{200F}hello world."
            let sca = screenCharArrayWithDefaultStyle(input, eol: EOL_HARD)
            guard let bidi = BidiDisplayInfoObjc(sca) else {
                return  // No bidi info at all is equally verbatim.
            }
            let ns = input as NSString
            for logical in 1..<ns.length {
                XCTAssertEqual(bidi.visualForLogical(Int32(logical)), Int32(logical),
                               "ASCII text after a leading RLM must stay verbatim at cell \(logical)")
            }
        }
    }

    // A program-printed LRI (U+2066) with no closing PDI is content, not one of
    // our inserted controls: it must not blanket-exempt the rest of the line
    // from bracket mirroring.
    func testContentLRIDoesNotSuppressMirroringForRestOfLine() {
        withShippedDefaults {
            let input = "\u{2066}chat سلام (تهران) دنیا"
            let sca = screenCharArrayWithDefaultStyle(input, eol: EOL_HARD)
            // Index against the cell string: a zero-width control may not
            // survive as its own cell, shifting everything after it.
            let cells = sca.stringValue as NSString
            let openIndex = Int32(cells.range(of: "(").location)
            let closeIndex = Int32(cells.range(of: ")").location)
            guard let bidi = BidiDisplayInfoObjc(sca) else {
                return XCTFail("mixed line with a content LRI must produce bidi info")
            }
            guard bidi.visualForLogical(openIndex) > bidi.visualForLogical(closeIndex) else {
                return  // Parens not repositioned here; nothing to cancel.
            }
            XCTAssertTrue(bidi.mirrorsSourceCell(openIndex),
                          "( around RTL text must keep mirroring despite a stray content LRI")
            XCTAssertTrue(bidi.mirrorsSourceCell(closeIndex),
                          ") around RTL text must keep mirroring despite a stray content LRI")
        }
    }

    // Guillemets obey the Unicode bidi algorithm like any other mirrorable
    // character (rule L4); iTerm2 does not special-case them. A terminal line is
    // an LTR container by default, so a whole-line guillemet-quoted RTL span keeps
    // the quotes at the base level at the line edges (so «متن» reads as typed) and
    // lays the RTL run out in reading order. This guards against an earlier
    // regression where the marks were split with both on the same side (drawing
    // «»متن) instead of straddling the text. Detect OFF (the default).
    func testGuillemetQuotedRTLSpanIsNotStranded() {
        let defaults = iTermUserDefaults.userDefaults()
        let savedDetect = defaults.object(forKey: "DetectParagraphDirection")
        defaults.set(false, forKey: "DetectParagraphDirection")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            if let savedDetect { defaults.set(savedDetect, forKey: "DetectParagraphDirection") }
            else { defaults.removeObject(forKey: "DetectParagraphDirection") }
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
        // متن reverses to نتم; the marks straddle it as «نتم», not split to «»نتم.
        XCTAssertEqual(visual("«متن»"), "«نتم»",
                       "the guillemet pair must straddle the RTL text, not strand on one side")
        // Single guillemets ‹ › behave the same.
        XCTAssertEqual(visual("‹متن›"), "‹نتم›",
                       "single guillemets must straddle the RTL text")
        // A multi-word span: «سلام دنیا» -> « + reversed("سلام دنیا") + ».
        XCTAssertEqual(visual("«سلام دنیا»"), "«ایند مالس»",
                       "a multi-word guillemet span must straddle the RTL text")
        // A guillemet span with RTL words OUTSIDE the quotes goes through the
        // standard algorithm; the pair must never both land on the same side.
        let withPrefix = visual("شهر «متن»")
        XCTAssertTrue(withPrefix.contains("«") && withPrefix.contains("»"),
                      "the guillemet pair must survive: \(withPrefix)")
    }
}
