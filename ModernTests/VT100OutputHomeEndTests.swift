//
//  VT100OutputHomeEndTests.swift
//  iTerm2XCTests
//
//  Home and End in a tmux -CC pane (screenlike) send tmux's own spelling,
//  CSI 1 ~ and CSI 4 ~, when unmodified (issue 3748). Modified Home and End
//  must keep their modifier, CSI 1 ; mod H and CSI 1 ; mod F, which is what
//  tmux itself sends for them (issue 13220).
//

import XCTest
@testable import iTerm2SharedARC

final class VT100OutputHomeEndTests: XCTestCase {
    private let control = UInt32(NSEvent.ModifierFlags.control.rawValue)
    private let shift = UInt32(NSEvent.ModifierFlags.shift.rawValue)

    private func string(_ data: Data?) -> String {
        guard let data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - VT100Output

    func testScreenlikeUnmodifiedHomeEndUseTmuxSpelling() {
        let output = VT100Output()
        XCTAssertEqual(string(output.keyHome(0, screenlikeTerminal: true)), "\u{1b}[1~")
        XCTAssertEqual(string(output.keyEnd(0, screenlikeTerminal: true)), "\u{1b}[4~")
    }

    func testScreenlikeControlHomeEndKeepModifier() {
        let output = VT100Output()
        XCTAssertEqual(string(output.keyHome(control, screenlikeTerminal: true)), "\u{1b}[1;5H")
        XCTAssertEqual(string(output.keyEnd(control, screenlikeTerminal: true)), "\u{1b}[1;5F")
    }

    func testScreenlikeShiftHomeEndKeepModifier() {
        let output = VT100Output()
        XCTAssertEqual(string(output.keyHome(shift, screenlikeTerminal: true)), "\u{1b}[1;2H")
        XCTAssertEqual(string(output.keyEnd(shift, screenlikeTerminal: true)), "\u{1b}[1;2F")
    }

    func testNonScreenlikeControlHomeEndMatchScreenlike() {
        let output = VT100Output()
        XCTAssertEqual(string(output.keyHome(control, screenlikeTerminal: false)), "\u{1b}[1;5H")
        XCTAssertEqual(string(output.keyEnd(control, screenlikeTerminal: false)), "\u{1b}[1;5F")
    }

    // MARK: - Standard key mapper in a tmux pane

    private func screenlikeMapper() -> iTermStandardKeyMapper {
        let config = iTermStandardKeyMapperConfiguration()
        config.outputFactory = VT100Output()
        config.encoding = String.Encoding.utf8.rawValue
        config.leftOptionKey = .OPT_NORMAL
        config.rightOptionKey = .OPT_NORMAL
        config.screenlike = true
        let mapper = iTermStandardKeyMapper()
        mapper.configuration = config
        return mapper
    }

    private func mappedString(_ key: CompanionSpecialKey,
                              modifiers: CompanionKeyModifiers = CompanionKeyModifiers()) -> String {
        let mapper = screenlikeMapper()
        guard let event = CompanionKeyEvent(key: .special(key), modifiers: modifiers).makeKeyDownEvents().first else {
            XCTFail("No event for \(key)")
            return ""
        }
        if let pre = mapper.keyMapperString(forPreCocoaEvent: event), !pre.isEmpty {
            return pre
        }
        return string(mapper.keyMapperData(forPostCocoaEvent: event))
    }

    func testStandardMapperScreenlikeControlHomeEnd() {
        let control = CompanionKeyModifiers(control: true)
        XCTAssertEqual(mappedString(.home, modifiers: control), "\u{1b}[1;5H")
        XCTAssertEqual(mappedString(.end, modifiers: control), "\u{1b}[1;5F")
    }

    func testStandardMapperScreenlikeUnmodifiedHomeEnd() {
        XCTAssertEqual(mappedString(.home), "\u{1b}[1~")
        XCTAssertEqual(mappedString(.end), "\u{1b}[4~")
    }
}
