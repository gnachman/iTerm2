//
//  BidiSelectionHighlightTests.swift
//  ModernTests
//
//  The selection is stored in LOGICAL coordinates. On a right-to-left line the
//  background highlight must decide whether a cell is selected from its logical
//  index and then draw it at its visual column, so the highlight lands on the
//  cells the user actually selected instead of their mirror images (which showed
//  up as highlighting the wrong words and empty space on the left).
//
//  This drives the real backgroundRunsInLine path, so it fails if the selected
//  flag is ever taken from the visual column again.
//

import XCTest
@testable import iTerm2SharedARC

class BidiSelectionHighlightTests: XCTestCase {
    private func setBidiPreference(_ enabled: Bool) {
        iTermPreferences.setBool(enabled, forKey: kPreferenceKeyBidi)
        let deadline = Date().addingTimeInterval(0.5)
        while iTermPreferences.bidiEnabled() != enabled && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
    }

    override func setUp() { super.setUp(); setBidiPreference(true) }
    override func tearDown() { setBidiPreference(false); super.tearDown() }

    func testSelectionHighlightFollowsLogicalMembership() {
        // Four right-to-left letters: visual order is the reverse of logical.
        let s = "ابجد"
        let sca = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        guard let bidi = BidiDisplayInfoObjc(sca) else { return XCTFail("no bidi info") }
        let width = Int(sca.length)
        XCTAssertGreaterThanOrEqual(width, 4)

        // Select the first two LOGICAL cells. This is asymmetric under the
        // reversal, so testing the visual column (the old bug) and the logical
        // index (the fix) give different answers, cell 0 lives at the far right.
        var selected = IndexSet()
        selected.insert(integersIn: 0..<2)

        var anyBlink: ObjCBool = false
        let runsInLine = iTermBackgroundColorRunsInLine.backgroundRuns(
            inLine: sca.line,
            lineLength: Int32(width),
            sourceLineNumber: 0,
            displayLineNumber: 0,
            selectedIndexes: selected,
            within: NSRange(location: 0, length: width),
            matches: nil,
            anyBlink: &anyBlink,
            y: 0,
            bidi: bidi,
            eaIndex: nil,
            darkMode: false)
        guard let runsInLine else { return XCTFail("no background runs") }

        var selectedRuns = 0
        for boxed in runsInLine.array {
            let run = boxed.valuePointer.pointee
            let logical = Int(run.modelRange.location)
            let expected = selected.contains(logical)
            XCTAssertEqual(run.selected.boolValue, expected,
                           "logical cell \(logical) drawn at visual \(run.visualRange.location): selected=\(run.selected.boolValue), expected \(expected)")
            if run.selected.boolValue {
                selectedRuns += 1
                // A selected run must draw at the visual column of a selected
                // logical cell, never at an unrelated (mirror-image) column.
                XCTAssertTrue(selected.contains(logical),
                              "selected run at visual \(run.visualRange.location) maps to unselected logical \(logical)")
            }
        }
        XCTAssertEqual(selectedRuns, 2, "exactly the two selected logical cells should be highlighted")
    }

    // The user's screenshot case: an English island inside Persian, with the
    // Latin-islands setting on. Selecting the English word's logical cells must
    // highlight the visual cells where that word is drawn, not the mirror on the
    // left. Uses a manual logical IndexSet (what the mouse path stores) so it
    // isolates the highlight math from the selection model.
    func testIslandLineHighlight() {
        let saved = iTermUserDefaults.userDefaults().object(forKey: "IsolateLatinRunsInRTL")
        let savedD = iTermUserDefaults.userDefaults().object(forKey: "DetectParagraphDirection")
        iTermUserDefaults.userDefaults().set(true, forKey: "IsolateLatinRunsInRTL")
        iTermUserDefaults.userDefaults().set(true, forKey: "DetectParagraphDirection")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            if let v = saved { iTermUserDefaults.userDefaults().set(v, forKey: "IsolateLatinRunsInRTL") } else { iTermUserDefaults.userDefaults().removeObject(forKey: "IsolateLatinRunsInRTL") }
            if let v = savedD { iTermUserDefaults.userDefaults().set(v, forKey: "DetectParagraphDirection") } else { iTermUserDefaults.userDefaults().removeObject(forKey: "DetectParagraphDirection") }
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
        let s = "متن abc دیگر"                    // Persian, English island, Persian
        let ns = s as NSString
        let sca = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        guard let bidi = BidiDisplayInfoObjc(sca) else { return XCTFail("no bidi info") }
        let width = Int(sca.length)
        let abcStart = ns.range(of: "abc").location   // logical index of the island

        var selected = IndexSet()
        selected.insert(integersIn: abcStart..<(abcStart + 3))  // select "abc"

        var anyBlink: ObjCBool = false
        guard let runs = iTermBackgroundColorRunsInLine.backgroundRuns(
            inLine: sca.line, lineLength: Int32(width), sourceLineNumber: 0, displayLineNumber: 0,
            selectedIndexes: selected, within: NSRange(location: 0, length: width),
            matches: nil, anyBlink: &anyBlink, y: 0, bidi: bidi, eaIndex: nil, darkMode: false) else {
            return XCTFail("no runs")
        }
        var highlighted = Set<Int>()
        for boxed in runs.array where boxed.valuePointer.pointee.selected.boolValue {
            let r = boxed.valuePointer.pointee.visualRange
            for v in r.location..<(r.location + r.length) { highlighted.insert(v) }
        }
        let expected = Set(selected.map { Int(bidi.visualForLogical(Int32($0))) })
        XCTAssertEqual(highlighted, expected,
                       "island “abc” highlight landed on visual \(highlighted.sorted()), expected \(expected.sorted())")
    }
}
