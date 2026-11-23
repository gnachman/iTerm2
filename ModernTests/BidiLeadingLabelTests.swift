//
//  BidiLeadingLabelTests.swift
//  ModernTests
//
//  A line that opens with a Latin label and a colon (“- UI-6: Deploy در دو
//  مرحله.”) and is laid out right-to-left by the Latin-first word minimum.
//  The label leads the line whether the word after the colon is Latin or
//  right-to-left.
//

import XCTest
@testable import iTerm2SharedARC

class BidiLeadingLabelTests: XCTestCase {
    private let keys = ["DetectParagraphDirection", "RtlParagraphMinimumWords"]

    private func withLatinFirstMinimum(_ minimum: Int, _ body: () -> Void) {
        let d = iTermUserDefaults.userDefaults()
        let saved = keys.map { d.object(forKey: $0) }
        d.set(true, forKey: "DetectParagraphDirection")
        d.set(minimum, forKey: "RtlParagraphMinimumWords")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
            }
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
        body()
    }

    // Every character in these lines is one cell wide, so a character's index
    // is its cell. Returns the visual cell of each logical cell.
    private func visual(_ line: String, file: StaticString = #filePath, fileLine: UInt = #line) -> [Int32] {
        // Not screenCharArrayWithDefaultStyle: it turns “-” into the right half
        // of a double-width character, and these lines hold real hyphens.
        let sca = ScreenCharArray.create(string: line,
                                         predecessor: nil,
                                         foreground: screen_char_t.defaultForeground,
                                         background: screen_char_t.defaultBackground,
                                         continuation: screen_char_t.defaultForeground.with(code: unichar(EOL_HARD)),
                                         metadata: iTermMetadataDefault(),
                                         ambiguousIsDoubleWidth: false,
                                         normalization: .none,
                                         unicodeVersion: 9).sca
        guard let info = BidiDisplayInfoObjc(sca) else {
            XCTFail("no bidi info for «\(line)»", file: file, line: fileLine)
            return []
        }
        return (0..<Int32(line.utf16.count)).map { info.visualForLogical($0) }
    }

    private func ascending(from first: Int32, count: Int) -> [Int32] {
        return (0..<Int32(count)).map { first + $0 }
    }

    //                                  000000000011111111112222222
    //                                  012345678901234567890123456
    private let labelThenLatin =       "- UI-6: Deploy در دو مرحله."
    private let labelThenPersian =     "- UI-5: دکمه های Logs"
    private let twoWordLabel =         "Root cause: VT100Grid کپی شد"

    func testLabelLeadsWhenALatinWordFollowsTheColon() {
        withLatinFirstMinimum(1) {
            let v = visual(labelThenLatin)
            guard v.count == 27 else { return }
            XCTAssertEqual(Array(v[0...1]), [26, 25], "the list marker is at the right edge")
            XCTAssertEqual(Array(v[2...5]), [21, 22, 23, 24], "UI-6 comes right after the marker")
            XCTAssertEqual(Array(v[6...7]), [20, 19], "then the colon and the space")
            XCTAssertEqual(Array(v[8...13]), ascending(from: 13, count: 6), "then Deploy")
            XCTAssertEqual(Array(v[14...26]), Array((0...12).reversed()), "then the Persian text")
        }
    }

    func testLabelBeforeAPersianWordIsWhereItAlwaysWas() {
        withLatinFirstMinimum(1) {
            let v = visual(labelThenPersian)
            guard v.count == 21 else { return }
            XCTAssertEqual(Array(v[0...1]), [20, 19])
            XCTAssertEqual(Array(v[2...5]), [15, 16, 17, 18], "UI-5 comes right after the marker")
            XCTAssertEqual(Array(v[6...7]), [14, 13])
            XCTAssertEqual(Array(v[8...16]), Array((4...12).reversed()))
            XCTAssertEqual(Array(v[17...20]), ascending(from: 0, count: 4), "Logs ends the line at the left")
        }
    }

    func testLabelOfTwoWords() {
        withLatinFirstMinimum(1) {
            let v = visual(twoWordLabel)
            guard v.count == 28 else { return }
            XCTAssertEqual(Array(v[0...9]), ascending(from: 18, count: 10), "Root cause leads")
            XCTAssertEqual(Array(v[10...11]), [17, 16])
            XCTAssertEqual(Array(v[12...20]), ascending(from: 7, count: 9), "then VT100Grid")
        }
    }

    // With the minimum at its default the line is left-to-right, as first-strong
    // says, and nothing about it changes.
    func testLeftToRightLineIsUntouched() {
        withLatinFirstMinimum(0) {
            let v = visual(labelThenLatin)
            guard v.count == 27 else { return }
            XCTAssertEqual(Array(v[0...14]), ascending(from: 0, count: 15))
        }
    }

    // A line that opens right-to-left is plain Unicode bidi: a Latin phrase
    // with a colon inside it stays in one piece.
    func testLineThatOpensRightToLeftIsUntouched() {
        withLatinFirstMinimum(1) {
            //                      0123456789012345678901
            let v = visual("سلام UI-6: Deploy است")
            guard v.count == 21 else { return }
            XCTAssertEqual(Array(v[5...16]), ascending(from: 4, count: 12), "UI-6: Deploy is one run")
        }
    }

    // Quotes and braces before the colon mean code, not a label.
    func testCodeIsNotALabel() {
        withLatinFirstMinimum(1) {
            //                      01234567890123456789012345
            let v = visual("{\"a\": 1, \"b\": \"سلام دنیا\"}")
            guard v.count == 26 else { return }
            XCTAssertEqual(Array(v[2...10]), ascending(from: v[2], count: 9), "a\": 1, \"b is one run")
        }
    }
}
