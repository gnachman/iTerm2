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

    func testLongMixedSentencesKeepFourOrMoreDirectionChangesReadable() {
        let defaults = iTermUserDefaults.userDefaults()
        let savedDetect = defaults.object(forKey: "DetectParagraphDirection")
        let savedJustify = defaults.object(forKey: "RightJustifyRTLLines")
        defaults.set(false, forKey: "DetectParagraphDirection")
        defaults.set(false, forKey: "RightJustifyRTLLines")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            if let savedDetect {
                defaults.set(savedDetect, forKey: "DetectParagraphDirection")
            } else {
                defaults.removeObject(forKey: "DetectParagraphDirection")
            }
            if let savedJustify {
                defaults.set(savedJustify, forKey: "RightJustifyRTLLines")
            } else {
                defaults.removeObject(forKey: "RightJustifyRTLLines")
            }
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }

        func visualColumns(of island: String,
                           occurrence: Int = 1,
                           in input: String,
                           using bidi: BidiDisplayInfoObjc) -> [Int32] {
            let nsInput = input as NSString
            var searchRange = NSRange(location: 0, length: nsInput.length)
            var range = NSRange(location: NSNotFound, length: 0)
            for _ in 0..<occurrence {
                range = nsInput.range(of: island, options: [], range: searchRange)
                guard range.location != NSNotFound else { return [] }
                let next = NSMaxRange(range)
                searchRange = NSRange(location: next, length: nsInput.length - next)
            }
            return (range.location..<NSMaxRange(range)).map {
                bidi.visualForLogical(Int32($0))
            }
        }

        func assertLTRIsland(_ island: String,
                             occurrence: Int = 1,
                             in input: String,
                             using bidi: BidiDisplayInfoObjc,
                             file: StaticString = #filePath,
                             line: UInt = #line) -> Int32 {
            let columns = visualColumns(of: island, occurrence: occurrence, in: input, using: bidi)
            XCTAssertFalse(columns.isEmpty, "missing island \(island)", file: file, line: line)
            if let first = columns.first {
                XCTAssertEqual(columns,
                               Array(first..<(first + Int32(columns.count))),
                               "\(island) must remain contiguous and left-to-right",
                               file: file,
                               line: line)
                return first
            }
            return -1
        }

        let hebrewPayload = "ראית ש iTerm2 הוסיפו תמיכה ב RTL ועכשיו אפשר לעבוד בצורה נוחה ונעימה, it's awesome, במיוחד עם README.md בעברית"
        let hebrewPrefix = "➜ ~ echo "
        let hebrewCommand = hebrewPrefix + "\"" + hebrewPayload + "\""
        guard let hebrewBidi = BidiDisplayInfoObjc(
            screenCharArrayWithDefaultStyle(hebrewCommand, eol: EOL_HARD)) else {
            return XCTFail("long Hebrew command must produce bidi display information")
        }
        XCTAssertFalse(hebrewBidi.paragraphIsRTL)
        for logical in 0..<(hebrewPrefix as NSString).length {
            XCTAssertEqual(hebrewBidi.visualForLogical(Int32(logical)), Int32(logical),
                           "the prompt and command must remain anchored at the left edge")
        }
        let hebrewIslandPositions = [
            assertLTRIsland("iTerm2", in: hebrewCommand, using: hebrewBidi),
            assertLTRIsland("RTL", in: hebrewCommand, using: hebrewBidi),
            assertLTRIsland("it's awesome", in: hebrewCommand, using: hebrewBidi),
            assertLTRIsland("README.md", in: hebrewCommand, using: hebrewBidi),
        ]
        XCTAssertEqual(hebrewIslandPositions, hebrewIslandPositions.sorted(by: >),
                       "LTR islands must follow the logical reading order from right to left")

        let arabicCommand = "➜ ~ echo \"Did you see أن iTerm2 now supports النص العربي and keeps README.md readable داخل Nano?\""
        guard let arabicBidi = BidiDisplayInfoObjc(
            screenCharArrayWithDefaultStyle(arabicCommand, eol: EOL_HARD)) else {
            return XCTFail("long English/Arabic command must produce bidi display information")
        }
        XCTAssertFalse(arabicBidi.paragraphIsRTL)
        let englishIslands = ["Did you see", "iTerm2 now supports", "and keeps README.md readable", "Nano"]
        let englishPositions = englishIslands.map {
            assertLTRIsland($0, in: arabicCommand, using: arabicBidi)
        }
        XCTAssertEqual(englishPositions, englishPositions.sorted(),
                       "an English-first sentence must keep its LTR reading order")

        for (label, bidi) in [("Hebrew", hebrewBidi), ("Arabic", arabicBidi)] {
            for logical in 0..<Int(bidi.numberOfCells) {
                let visual = bidi.visualForLogical(Int32(logical))
                XCTAssertEqual(bidi.logicalForVisual(visual), Int32(logical),
                               "\(label) logical/visual mapping must round-trip at cell \(logical)")
            }
        }
    }

    func testLTRShellCommandPrefixStaysAnchoredLeft() {
        let defaults = iTermUserDefaults.userDefaults()
        let savedDetect = defaults.object(forKey: "DetectParagraphDirection")
        let savedJustify = defaults.object(forKey: "RightJustifyRTLLines")
        defaults.set(false, forKey: "DetectParagraphDirection")
        defaults.set(false, forKey: "RightJustifyRTLLines")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            if let savedDetect {
                defaults.set(savedDetect, forKey: "DetectParagraphDirection")
            } else {
                defaults.removeObject(forKey: "DetectParagraphDirection")
            }
            if let savedJustify {
                defaults.set(savedJustify, forKey: "RightJustifyRTLLines")
            } else {
                defaults.removeObject(forKey: "RightJustifyRTLLines")
            }
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }

        let input = "➜ ~ echo \"מה קורה חבר HELOO אתה בסדר?\""
        let base = screenCharArrayWithDefaultStyle(input, eol: EOL_HARD)
        guard let bidi = BidiDisplayInfoObjc(base) else {
            return XCTFail("mixed Hebrew command must produce bidi display information")
        }
        XCTAssertFalse(bidi.paragraphIsRTL)

        let prefixRange = (input as NSString).range(of: "➜ ~ echo ")
        let prefixVisualColumns = (prefixRange.location..<NSMaxRange(prefixRange)).map {
            bidi.visualForLogical(Int32($0))
        }
        XCTAssertEqual(prefixVisualColumns,
                       Array(Int32(prefixRange.location)..<Int32(NSMaxRange(prefixRange))),
                       "the prompt and command must remain anchored at the left edge")

        let output = visual(input).trimmingCharacters(in: .whitespaces)
        XCTAssertTrue(output.hasPrefix("➜ ~ echo "), "command moved away from the left edge: \(output)")
        XCTAssertTrue(output.contains("?רדסב התא HELOO רבח הרוק המ"),
                      "mixed argument did not keep natural RTL order: \(output)")

        let commandPrefixes = [
            "➜ Documents echo ",
            "➜ Documents printf \"%s\\n\" ",
            "➜ Documents git commit -m ",
            "➜ Documents python3 script.py --message ",
        ]
        for commandPrefix in commandPrefixes {
            let command = commandPrefix + "\"מה קורה מותק, how are you\""
            let commandBase = screenCharArrayWithDefaultStyle(command, eol: EOL_HARD)
            guard let commandBidi = BidiDisplayInfoObjc(commandBase) else {
                return XCTFail("mixed argument must produce bidi display information: \(command)")
            }
            let commandPrefixRange = NSRange(location: 0, length: (commandPrefix as NSString).length)
            let commandPrefixColumns = (commandPrefixRange.location..<NSMaxRange(commandPrefixRange)).map {
                commandBidi.visualForLogical(Int32($0))
            }
            XCTAssertEqual(commandPrefixColumns,
                           Array(Int32(commandPrefixRange.location)..<Int32(NSMaxRange(commandPrefixRange))),
                           "command prefix must remain at the left edge: \(command)")
            let commandOutput = visual(command).trimmingCharacters(in: .whitespaces)
            XCTAssertTrue(commandOutput.hasPrefix(commandPrefix),
                          "command moved away from the left edge: \(commandOutput)")
            XCTAssertTrue(commandOutput.contains("how are you ,קתומ הרוק המ"),
                          "argument must show Hebrew on the right and English on the left: \(commandOutput)")
            XCTAssertFalse(commandOutput.contains(commandPrefix + "\"\""),
                           "opening and closing quotes collapsed beside command: \(commandOutput)")
        }

        let englishFirst = "➜ Documents echo \"hello מה קורה friend\""
        XCTAssertEqual(visual(englishFirst).trimmingCharacters(in: .whitespaces),
                       "➜ Documents echo \"hello הרוק המ friend\"",
                       "an English-first argument must keep its LTR paragraph order")

        let arabicFirst = "➜ Documents echo \"مرحبا يا صديقي, how are you\""
        XCTAssertEqual(visual(arabicFirst).trimmingCharacters(in: .whitespaces),
                       "➜ Documents echo \"how are you ,يقيدص اي ابحرم\"",
                       "Arabic must use the same RTL-suffix behavior as Hebrew")

        let englishThenArabic = "➜ Documents echo \"hello مرحبا صديقي friend\""
        XCTAssertEqual(visual(englishThenArabic).trimmingCharacters(in: .whitespaces),
                       "➜ Documents echo \"hello يقيدص ابحرم friend\"",
                       "an English-first Arabic argument must remain LTR")

        let spacedRTLArgument = "➜ Documents echo \"  מה קורה, how are you\""
        XCTAssertEqual(visual(spacedRTLArgument).trimmingCharacters(in: .whitespaces),
                       "➜ Documents echo \"how are you ,הרוק המ  \"",
                       "leading neutral characters must stay with an RTL-first argument")

        let bare = "מה קורה מותק, how are you"
        XCTAssertEqual(visual(bare).trimmingCharacters(in: .whitespaces),
                       "how are you ,קתומ הרוק המ",
                       "a bare output line must use natural RTL order without right justification")

        let bareEnglishFirst = "hello מה קורה friend"
        XCTAssertEqual(visual(bareEnglishFirst).trimmingCharacters(in: .whitespaces),
                       "hello הרוק המ friend",
                       "an exposed English-first line must keep standard LTR order")

        let bareEnglishThenArabic = "hello مرحبا صديقي friend"
        XCTAssertEqual(visual(bareEnglishThenArabic).trimmingCharacters(in: .whitespaces),
                       "hello يقيدص ابحرم friend",
                       "an exposed English-first Arabic line must keep standard LTR order")

        let symbolicPrompt = "➜ ~ "
        let typedContent = "מה קורה מותק, HOW ARE YOU"
        var typed = symbolicPrompt
        for character in typedContent {
            typed.append(character)
            let typedBase = screenCharArrayWithDefaultStyle(typed, eol: EOL_HARD)
            guard let typedBidi = BidiDisplayInfoObjc(typedBase) else {
                return XCTFail("each Hebrew typing stage must produce bidi info: \(typed)")
            }
            for logical in 0..<Int(typedBidi.numberOfCells) {
                let visual = typedBidi.visualForLogical(Int32(logical))
                XCTAssertEqual(typedBidi.logicalForVisual(visual), Int32(logical),
                               "typing-stage LUT must round-trip at \(logical): \(typed)")
            }
            for logical in 0..<(symbolicPrompt as NSString).length {
                XCTAssertEqual(typedBidi.visualForLogical(Int32(logical)), Int32(logical),
                               "symbol-only prompt moved while typing: \(typed)")
            }
        }
        let typedOutput = visual(symbolicPrompt + typedContent).trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(typedOutput, symbolicPrompt + "HOW ARE YOU ,קתומ הרוק המ",
                       "final typed line must keep the prompt left, English left, and Hebrew right")
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

    // The RTL isolate must stop at the closing delimiter, not run to the end of
    // the line: anything typed after the quoted argument stays where it was typed.
    func testCommandTailAfterQuotedRTLArgumentStaysAtLineEnd() {
        withShippedDefaults {
            let input = "echo 'سلام دنیا' && ls"
            let expected = "echo '" + rev("دنیا") + " " + rev("سلام") + "' && ls"
            XCTAssertEqual(visual(input).trimmingCharacters(in: .whitespaces), expected,
                           "text after the closing quote must not join the RTL isolate")
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

    // An apostrophe glued to a letter (possessive, inch mark) is punctuation,
    // not an opening shell quote, and must not move the isolate boundary.
    func testPossessiveApostropheBeforeRTLDoesNotOpenAQuote() {
        withShippedDefaults {
            let input = "teachers' سلام okay"
            let expected = "teachers' " + rev("سلام") + " okay"
            XCTAssertEqual(visual(input).trimmingCharacters(in: .whitespaces), expected,
                           "a possessive apostrophe must stay glued to its word")
        }
    }

    // CoreText both repositions AND mirrors a bracket pair around an LTR island
    // inside an RTL context; the two cancel out to a correct-facing (hello).
    // The LUT keeps the swapped positions, so the mirror flags must stay set —
    // suppressing them draws )hello(.
    func testParenthesesAroundLatinIslandKeepMirrorCancellation() {
        withShippedDefaults {
            let input = "echo 'سلام (hello) دنیا'"
            let ns = input as NSString
            let openIndex = Int32(ns.range(of: "(").location)
            let closeIndex = Int32(ns.range(of: ")").location)
            guard let bidi = BidiDisplayInfoObjc(
                screenCharArrayWithDefaultStyle(input, eol: EOL_HARD)) else {
                return XCTFail("mixed parenthesized argument must produce bidi info")
            }
            XCTAssertGreaterThan(bidi.visualForLogical(openIndex),
                                 bidi.visualForLogical(closeIndex),
                                 "CoreText swaps the bracket positions in an RTL context")
            XCTAssertTrue(bidi.mirrorsSourceCell(openIndex),
                          "the repositioned ( must keep its mirror flag or it faces outward")
            XCTAssertTrue(bidi.mirrorsSourceCell(closeIndex),
                          "the repositioned ) must keep its mirror flag or it faces outward")
        }
    }

    // A leading RLM (U+200F) is a formatting mark, not text: it must not cause
    // an otherwise-Latin line to be wrapped in an RTL isolate.
    func testLeadingRLMDoesNotWrapLatinLine() {
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

    // With Latin-run isolation ON, a quote glued to an option (--message=") sits
    // inside an LRI island; splicing the RLI at that quote used to cross-nest the
    // isolates and re-scramble the payload.
    func testGluedQuoteInsideLatinIslandDoesNotCrossNestIsolates() {
        let d = iTermUserDefaults.userDefaults()
        let keys = ["DetectParagraphDirection", "RightJustifyRTLLines", "IsolateLatinRunsInRTL"]
        let saved = keys.map { d.object(forKey: $0) }
        d.set(false, forKey: "DetectParagraphDirection")
        d.set(false, forKey: "RightJustifyRTLLines")
        d.set(true, forKey: "IsolateLatinRunsInRTL")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
            }
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }

        let input = "git commit --message=\"سلام iTerm2 دنیا\""
        let output = visual(input).trimmingCharacters(in: .whitespaces)
        XCTAssertTrue(output.hasPrefix("git commit --message=\""),
                      "command and glued quote must stay anchored left: \(output)")
        XCTAssertTrue(output.contains(rev("دنیا") + " iTerm2 " + rev("سلام")),
                      "RTL-first payload must read right-to-left around the island: \(output)")
    }
}
