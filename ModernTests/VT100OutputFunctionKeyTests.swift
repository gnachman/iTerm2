//
//  VT100OutputFunctionKeyTests.swift
//  iTerm2XCTests
//
//  Regression tests for issue 10717: modified function keys must carry their
//  modifier under a tmux -CC session, whose term type is tmux's default-terminal
//  (tmux-256color) rather than xterm-256color. The bare terminfo lookup has no
//  modified-key entries, so the encoding must fall through to the xterm CSI
//  modifier form (e.g. Shift+F5 -> ^[[15;2~) for xterm- and tmux-like terminals.
//  TERM=screen deliberately stays on the terminfo path.
//

import XCTest
@testable import iTerm2SharedARC

final class VT100OutputFunctionKeyTests: XCTestCase {
    private func output(term: String) -> VT100Output {
        let o = VT100Output()
        o.termType = term
        return o
    }

    private func string(_ data: Data?) -> String {
        guard let data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    // Shift+F5 carries the modifier for both xterm and tmux term types. This is
    // independent of whether the terminfo database is installed, since the
    // modified form comes from xtermKeyFunction, not a terminfo lookup.
    func testShiftFunctionKeyEncodesModifier() {
        let shift = NSEvent.ModifierFlags.shift
        for term in ["xterm-256color", "tmux-256color", "tmux"] {
            let data = output(term: term).keyFunction(5, modifiers: shift)
            XCTAssertEqual(string(data), "\u{1b}[15;2~", "term=\(term)")
        }
    }

    // Control+F1 likewise carries the modifier under a tmux term type.
    func testControlFunctionKeyEncodesModifierForTmux() {
        let control = NSEvent.ModifierFlags.control
        let data = output(term: "tmux-256color").keyFunction(1, modifiers: control)
        XCTAssertEqual(string(data), "\u{1b}[1;5P")
    }

    // TERM=screen keeps the terminfo path, which has no xterm modifier encoding.
    func testShiftFunctionKeyDoesNotUseXtermEncodingForScreen() {
        let shift = NSEvent.ModifierFlags.shift
        let data = output(term: "screen").keyFunction(5, modifiers: shift)
        XCTAssertNotEqual(string(data), "\u{1b}[15;2~")
    }
}
