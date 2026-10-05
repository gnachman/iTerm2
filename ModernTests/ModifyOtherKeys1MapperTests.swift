//
//  ModifyOtherKeys1MapperTests.swift
//  iTerm2 ModernTests
//
//  Ported from iTermModifyOtherKeys1Test.m. Runs synthesized key-down events through
//  iTermModifyOtherKeysMapper1 (xterm modifyOtherKeys=1) with Option configured as Esc+ and
//  checks the exact bytes the terminal would receive for every modifier combination.
//

import Carbon.HIToolbox
import XCTest
@testable import iTerm2SharedARC

final class ModifyOtherKeys1MapperTests: XCTestCase, iTermStandardKeyMapperDelegate, iTermModifyOtherKeysMapperDelegate {
    private var mapper: iTermModifyOtherKeysMapper1!
    private var output: VT100Output!

    private let ctrl: NSEvent.ModifierFlags = .control
    private let opt: NSEvent.ModifierFlags = .option
    private let shift: NSEvent.ModifierFlags = .shift
    private let fn: NSEvent.ModifierFlags = .function

    // Unicode private-use characters AppKit puts in `characters` for special keys.
    private let upArrow = "\u{f700}"
    private let f1 = "\u{f704}"
    private let f2 = "\u{f705}"
    private let forwardDelete = "\u{f728}"
    private let esc = "\u{1b}"
    private let del = "\u{7f}"
    private let tab = "\t"
    private let backtab = "\u{19}"

    override func setUp() {
        super.setUp()
        mapper = iTermModifyOtherKeysMapper1()
        mapper.delegate = self
        output = VT100Output()
        output.termType = "xterm"
    }

    override func tearDown() {
        mapper = nil
        output = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func keyEvent(_ characters: String,
                          ignoringModifiers: String,
                          modifiers: NSEvent.ModifierFlags,
                          keyCode: Int) -> NSEvent? {
        return NSEvent.keyEvent(with: .keyDown,
                                location: .zero,
                                modifierFlags: modifiers,
                                timestamp: 0,
                                windowNumber: 0,
                                context: nil,
                                characters: characters,
                                charactersIgnoringModifiers: ignoringModifiers,
                                isARepeat: false,
                                keyCode: UInt16(keyCode))
    }

    /// What the mapper would send for the event: the pre-Cocoa string if it handles the key
    /// there, otherwise the post-Cocoa data decoded as UTF-8.
    private func mapped(_ event: NSEvent) -> String? {
        if let string = mapper.keyMapperString(forPreCocoaEvent: event) {
            return string
        }
        if let data = mapper.keyMapperData(forPostCocoaEvent: event) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private func verify(_ characters: String,
                        ignoringModifiers: String? = nil,
                        modifiers: NSEvent.ModifierFlags,
                        keyCode: Int,
                        expected: String,
                        file: StaticString = #filePath,
                        line: UInt = #line) {
        guard let event = keyEvent(characters,
                                   ignoringModifiers: ignoringModifiers ?? characters,
                                   modifiers: modifiers,
                                   keyCode: keyCode) else {
            XCTFail("Could not synthesize key event", file: file, line: line)
            return
        }
        guard let actual = mapped(event) else {
            XCTFail("Mapper produced nothing; expected \(debugDescription(of: expected))",
                    file: file, line: line)
            return
        }
        XCTAssertEqual(actual, expected,
                       "got \(debugDescription(of: actual)), expected \(debugDescription(of: expected))",
                       file: file, line: line)
    }

    private func debugDescription(of string: String) -> String {
        return string.unicodeScalars.map { scalar in
            if scalar.value < 0x20 || scalar.value == 0x7f {
                return String(format: "\\x%02x", scalar.value)
            }
            return String(scalar)
        }.joined()
    }

    private func csi(_ suffix: String) -> String {
        return "\u{1b}[" + suffix
    }

    private func escPlus(_ suffix: String) -> String {
        return "\u{1b}" + suffix
    }

    /// The control character for a key, e.g. ctrlChar("[") is ESC and ctrlChar("?") is DEL.
    private func ctrlChar(_ c: Unicode.Scalar) -> String {
        if c == "?" {
            return "\u{7f}"
        }
        guard c.value >= 0x40, let scalar = Unicode.Scalar(c.value - 0x40) else {
            XCTFail("No control character for \(c)")
            return ""
        }
        return String(scalar)
    }

    // MARK: - iTermStandardKeyMapperDelegate

    func standardKeyMapperWillMapKey(_ standardKeyMapper: iTermStandardKeyMapper) {
        let configuration = iTermStandardKeyMapperConfiguration()
        configuration.outputFactory = output
        configuration.encoding = String.Encoding.utf8.rawValue
        configuration.leftOptionKey = .OPT_ESC
        configuration.rightOptionKey = .OPT_ESC
        configuration.screenlike = false
        standardKeyMapper.configuration = configuration
    }

    // MARK: - iTermModifyOtherKeysMapperDelegate

    func modifiyOtherKeysDelegateEncoding(_ sender: iTermModifyOtherKeysMapper) -> UInt {
        return String.Encoding.utf8.rawValue
    }

    func modifyOtherKeys(_ sender: iTermModifyOtherKeysMapper,
                         getOptionKeyBehaviorLeft left: UnsafeMutablePointer<iTermOptionKeyBehavior>,
                         right: UnsafeMutablePointer<iTermOptionKeyBehavior>) {
        left.pointee = .OPT_ESC
        right.pointee = .OPT_ESC
    }

    func modifyOtherKeysOutputFactory(_ sender: iTermModifyOtherKeysMapper) -> VT100Output {
        return output
    }

    func modifyOtherKeysTerminalIsScreenlike(_ sender: iTermModifyOtherKeysMapper) -> Bool {
        return false
    }

    // MARK: - Unmodified

    func testUnmodifiedLetter() {
        verify("a", modifiers: [], keyCode: kVK_ANSI_A, expected: "a")
    }

    func testUnmodifiedNumber() {
        verify("1", modifiers: [], keyCode: kVK_ANSI_1, expected: "1")
    }

    func testUnmodifiedSymbol() {
        verify("[", modifiers: [], keyCode: kVK_ANSI_LeftBracket, expected: "[")
    }

    func testUnmodifiedArrow() {
        verify(upArrow, modifiers: fn, keyCode: kVK_UpArrow, expected: csi("A"))
    }

    func testUnmodifiedFunctionKey() {
        verify(f1, modifiers: fn, keyCode: kVK_F1, expected: escPlus("OP"))
    }

    func testUnmodifiedDelete() {
        verify(forwardDelete, modifiers: fn, keyCode: kVK_ForwardDelete, expected: csi("3~"))
    }

    func testUnmodifiedTab() {
        verify(tab, modifiers: [], keyCode: kVK_Tab, expected: tab)
    }

    func testUnmodifiedEsc() {
        verify(esc, modifiers: [], keyCode: kVK_Escape, expected: esc)
    }

    func testUnmodifiedBackspace() {
        verify(del, modifiers: [], keyCode: kVK_Delete, expected: del)
    }

    // MARK: - Control

    func testControlLetter() {
        verify("\u{01}", ignoringModifiers: "a", modifiers: ctrl, keyCode: kVK_ANSI_A, expected: "\u{01}")
    }

    // Digits with no control-character equivalent are reported as CSI 27 ; 5 ; code ~.
    func testControlDigitWithoutControlEquivalentUsesCSI27() {
        verify("1", modifiers: ctrl, keyCode: kVK_ANSI_1, expected: csi("27;5;49~"))
        verify("9", modifiers: ctrl, keyCode: kVK_ANSI_9, expected: csi("27;5;57~"))
        verify("0", modifiers: ctrl, keyCode: kVK_ANSI_0, expected: csi("27;5;48~"))
    }

    // Digits 2 through 8 map to the classic control characters ^@ ^[ ^\ ^] ^^ ^_ and DEL.
    func testControlDigitWithControlEquivalentSendsControlCharacter() {
        verify("2", modifiers: ctrl, keyCode: kVK_ANSI_2, expected: ctrlChar("@"))
        verify("3", modifiers: ctrl, keyCode: kVK_ANSI_3, expected: ctrlChar("["))
        verify("4", modifiers: ctrl, keyCode: kVK_ANSI_4, expected: ctrlChar("\\"))
        verify("5", modifiers: ctrl, keyCode: kVK_ANSI_5, expected: ctrlChar("]"))
        verify("6", modifiers: ctrl, keyCode: kVK_ANSI_6, expected: ctrlChar("^"))
        verify("7", modifiers: ctrl, keyCode: kVK_ANSI_7, expected: ctrlChar("_"))
        verify("8", modifiers: ctrl, keyCode: kVK_ANSI_8, expected: ctrlChar("?"))
    }

    func testControlSymbol() {
        verify("\u{1b}", ignoringModifiers: "[", modifiers: ctrl, keyCode: kVK_ANSI_LeftBracket, expected: ctrlChar("["))
        verify("\u{1d}", ignoringModifiers: "]", modifiers: ctrl, keyCode: kVK_ANSI_RightBracket, expected: ctrlChar("]"))
    }

    func testControlArrow() {
        verify(upArrow, modifiers: [fn, ctrl], keyCode: kVK_UpArrow, expected: csi("1;5A"))
    }

    func testControlFunctionKey() {
        verify(f2, modifiers: [fn, ctrl], keyCode: kVK_F2, expected: csi("1;5Q"))
    }

    func testControlDelete() {
        verify(forwardDelete, modifiers: [fn, ctrl], keyCode: kVK_ForwardDelete, expected: csi("3;5~"))
    }

    func testControlTab() {
        verify(tab, modifiers: ctrl, keyCode: kVK_Tab, expected: csi("27;5;9~"))
    }

    func testControlEsc() {
        verify(esc, modifiers: ctrl, keyCode: kVK_Escape, expected: esc)
    }

    func testControlBackspace() {
        verify(del, modifiers: ctrl, keyCode: kVK_Delete, expected: ctrlChar("H"))
    }

    // MARK: - Meta (Option as Esc+)

    func testMetaLetter() {
        verify("a", modifiers: opt, keyCode: kVK_ANSI_A, expected: escPlus("a"))
    }

    func testMetaNumber() {
        verify("1", modifiers: opt, keyCode: kVK_ANSI_1, expected: escPlus("1"))
    }

    func testMetaSymbol() {
        verify("[", modifiers: opt, keyCode: kVK_ANSI_LeftBracket, expected: escPlus("["))
    }

    // Would be 1;3A if Option were Alt rather than Meta.
    func testMetaArrow() {
        verify(upArrow, modifiers: [opt, fn], keyCode: kVK_UpArrow, expected: csi("1;9A"))
    }

    // Would be 1;3P if Option were Alt rather than Meta.
    func testMetaFunctionKey() {
        verify(f1, modifiers: [opt, fn], keyCode: kVK_F1, expected: csi("1;9P"))
    }

    func testMetaDelete() {
        verify(forwardDelete, modifiers: [opt, fn], keyCode: kVK_ForwardDelete, expected: csi("3;9~"))
    }

    func testMetaTab() {
        verify(tab, modifiers: opt, keyCode: kVK_Tab, expected: escPlus(tab))
    }

    func testMetaEsc() {
        verify(esc, modifiers: opt, keyCode: kVK_Escape, expected: escPlus(esc))
    }

    func testMetaBackspace() {
        verify(del, modifiers: opt, keyCode: kVK_Delete, expected: escPlus(del))
    }

    // MARK: - Shift

    func testShiftLetter() {
        verify("A", modifiers: shift, keyCode: kVK_ANSI_A, expected: "A")
    }

    func testShiftNumberSendsShiftedSymbol() {
        let shifted: [(String, Int)] = [("!", kVK_ANSI_1), ("@", kVK_ANSI_2), ("#", kVK_ANSI_3),
                                        ("$", kVK_ANSI_4), ("%", kVK_ANSI_5), ("^", kVK_ANSI_6),
                                        ("&", kVK_ANSI_7), ("*", kVK_ANSI_8), ("(", kVK_ANSI_9),
                                        (")", kVK_ANSI_0)]
        for (symbol, keyCode) in shifted {
            verify(symbol, modifiers: shift, keyCode: keyCode, expected: symbol)
        }
    }

    func testShiftSymbol() {
        verify("{", modifiers: shift, keyCode: kVK_ANSI_LeftBracket, expected: "{")
        verify("}", modifiers: shift, keyCode: kVK_ANSI_RightBracket, expected: "}")
    }

    func testShiftArrow() {
        verify(upArrow, modifiers: [fn, shift], keyCode: kVK_UpArrow, expected: csi("1;2A"))
    }

    func testShiftFunctionKey() {
        verify(f1, modifiers: [fn, shift], keyCode: kVK_F1, expected: csi("1;2P"))
    }

    func testShiftDelete() {
        verify(forwardDelete, modifiers: [fn, shift], keyCode: kVK_ForwardDelete, expected: csi("3;2~"))
    }

    func testShiftTab() {
        verify(backtab, modifiers: shift, keyCode: kVK_Tab, expected: csi("Z"))
    }

    func testShiftEsc() {
        verify(esc, modifiers: shift, keyCode: kVK_Escape, expected: esc)
    }

    func testShiftBackspace() {
        verify(del, modifiers: shift, keyCode: kVK_Delete, expected: del)
    }

    // MARK: - Control-Shift

    func testControlShiftLetter() {
        verify("\u{01}", ignoringModifiers: "A", modifiers: [ctrl, shift], keyCode: kVK_ANSI_A, expected: "\u{01}")
    }

    func testControlShiftDigitWithoutControlEquivalentUsesCSI27() {
        verify("1", ignoringModifiers: "!", modifiers: [ctrl, shift], keyCode: kVK_ANSI_1, expected: csi("27;6;33~"))
        verify("3", ignoringModifiers: "#", modifiers: [ctrl, shift], keyCode: kVK_ANSI_3, expected: csi("27;6;35~"))
        verify("4", ignoringModifiers: "$", modifiers: [ctrl, shift], keyCode: kVK_ANSI_4, expected: csi("27;6;36~"))
        verify("5", ignoringModifiers: "%", modifiers: [ctrl, shift], keyCode: kVK_ANSI_5, expected: csi("27;6;37~"))
        verify("7", ignoringModifiers: "&", modifiers: [ctrl, shift], keyCode: kVK_ANSI_7, expected: csi("27;6;38~"))
        verify("8", ignoringModifiers: "*", modifiers: [ctrl, shift], keyCode: kVK_ANSI_8, expected: csi("27;6;42~"))
        verify("9", ignoringModifiers: "(", modifiers: [ctrl, shift], keyCode: kVK_ANSI_9, expected: csi("27;6;40~"))
        verify("0", ignoringModifiers: ")", modifiers: [ctrl, shift], keyCode: kVK_ANSI_0, expected: csi("27;6;41~"))
    }

    // Control-@ and Control-^ have control-character equivalents even with shift held.
    func testControlShiftDigitWithControlEquivalentSendsControlCharacter() {
        verify("2", ignoringModifiers: "@", modifiers: [ctrl, shift], keyCode: kVK_ANSI_2, expected: ctrlChar("@"))
        verify("6", ignoringModifiers: "^", modifiers: [ctrl, shift], keyCode: kVK_ANSI_6, expected: ctrlChar("^"))
    }

    func testControlShiftSymbol() {
        verify("\u{1b}", ignoringModifiers: "{", modifiers: [ctrl, shift], keyCode: kVK_ANSI_LeftBracket, expected: ctrlChar("["))
        verify("\u{1d}", ignoringModifiers: "}", modifiers: [ctrl, shift], keyCode: kVK_ANSI_RightBracket, expected: ctrlChar("]"))
    }

    func testControlShiftArrow() {
        verify(upArrow, modifiers: [fn, ctrl, shift], keyCode: kVK_UpArrow, expected: csi("1;6A"))
    }

    func testControlShiftFunctionKey() {
        verify(f1, modifiers: [fn, ctrl, shift], keyCode: kVK_F1, expected: csi("1;6P"))
    }

    func testControlShiftDelete() {
        verify(forwardDelete, modifiers: [fn, ctrl, shift], keyCode: kVK_ForwardDelete, expected: csi("3;6~"))
    }

    func testControlShiftTab() {
        verify(backtab, modifiers: [ctrl, shift], keyCode: kVK_Tab, expected: csi("Z"))
    }

    func testControlShiftEsc() {
        verify(esc, modifiers: [ctrl, shift], keyCode: kVK_Escape, expected: esc)
    }

    func testControlShiftBackspace() {
        verify(del, modifiers: [ctrl, shift], keyCode: kVK_Delete, expected: ctrlChar("H"))
    }

    // MARK: - Control-Meta

    func testControlMetaLetter() {
        verify("\u{01}", ignoringModifiers: "a", modifiers: [ctrl, opt], keyCode: kVK_ANSI_A, expected: escPlus("\u{01}"))
    }

    // In xterm, control+number and control+meta+number do the same thing. This is a deliberate
    // departure. The modifier parameter is 7 because that is how iTermModifyOtherKeysMapper has
    // always worked; see csiModifiersForEventModifiers.
    func testControlMetaDigitWithoutControlEquivalentUsesCSI27() {
        verify("1", modifiers: [ctrl, opt], keyCode: kVK_ANSI_1, expected: csi("27;7;49~"))
        verify("9", modifiers: [ctrl, opt], keyCode: kVK_ANSI_9, expected: csi("27;7;57~"))
        verify("0", modifiers: [ctrl, opt], keyCode: kVK_ANSI_0, expected: csi("27;7;48~"))
    }

    func testControlMetaDigitWithControlEquivalentSendsEscPlusControlCharacter() {
        verify("2", modifiers: [ctrl, opt], keyCode: kVK_ANSI_2, expected: escPlus(ctrlChar("@")))
        verify("3", modifiers: [ctrl, opt], keyCode: kVK_ANSI_3, expected: escPlus(ctrlChar("[")))
        verify("4", modifiers: [ctrl, opt], keyCode: kVK_ANSI_4, expected: escPlus(ctrlChar("\\")))
        verify("5", modifiers: [ctrl, opt], keyCode: kVK_ANSI_5, expected: escPlus(ctrlChar("]")))
        verify("6", modifiers: [ctrl, opt], keyCode: kVK_ANSI_6, expected: escPlus(ctrlChar("^")))
        verify("7", modifiers: [ctrl, opt], keyCode: kVK_ANSI_7, expected: escPlus(ctrlChar("_")))
        verify("8", modifiers: [ctrl, opt], keyCode: kVK_ANSI_8, expected: escPlus(ctrlChar("?")))
    }

    func testControlMetaSymbol() {
        verify("\u{1b}", ignoringModifiers: "[", modifiers: [ctrl, opt], keyCode: kVK_ANSI_LeftBracket, expected: escPlus(ctrlChar("[")))
        verify("\u{1d}", ignoringModifiers: "]", modifiers: [ctrl, opt], keyCode: kVK_ANSI_RightBracket, expected: escPlus(ctrlChar("]")))
    }

    func testControlMetaArrow() {
        verify(upArrow, modifiers: [fn, ctrl, opt], keyCode: kVK_UpArrow, expected: csi("1;13A"))
    }

    func testControlMetaFunctionKey() {
        verify(f2, modifiers: [fn, ctrl, opt], keyCode: kVK_F2, expected: csi("1;13Q"))
    }

    func testControlMetaDelete() {
        verify(forwardDelete, modifiers: [fn, ctrl, opt], keyCode: kVK_ForwardDelete, expected: csi("3;13~"))
    }

    func testControlMetaTab() {
        verify(tab, modifiers: [ctrl, opt], keyCode: kVK_Tab, expected: escPlus(tab))
    }

    func testControlMetaEsc() {
        verify(esc, modifiers: [ctrl, opt], keyCode: kVK_Escape, expected: csi("27;7;27~"))
    }

    func testControlMetaBackspace() {
        verify(del, modifiers: [ctrl, opt], keyCode: kVK_Delete, expected: csi("3;7~"))
    }

    // MARK: - Control-Meta-Shift

    func testControlMetaShiftLetter() {
        verify("\u{01}", ignoringModifiers: "a", modifiers: [ctrl, opt, shift], keyCode: kVK_ANSI_A, expected: escPlus("\u{01}"))
    }

    func testControlMetaShiftDigitWithoutControlEquivalentUsesCSI27() {
        verify("1", ignoringModifiers: "!", modifiers: [ctrl, opt, shift], keyCode: kVK_ANSI_1, expected: csi("27;8;33~"))
        verify("3", ignoringModifiers: "#", modifiers: [ctrl, opt, shift], keyCode: kVK_ANSI_3, expected: csi("27;8;35~"))
        verify("4", ignoringModifiers: "$", modifiers: [ctrl, opt, shift], keyCode: kVK_ANSI_4, expected: csi("27;8;36~"))
        verify("5", ignoringModifiers: "%", modifiers: [ctrl, opt, shift], keyCode: kVK_ANSI_5, expected: csi("27;8;37~"))
        verify("7", ignoringModifiers: "&", modifiers: [ctrl, opt, shift], keyCode: kVK_ANSI_7, expected: csi("27;8;38~"))
        verify("8", ignoringModifiers: "*", modifiers: [ctrl, opt, shift], keyCode: kVK_ANSI_8, expected: csi("27;8;42~"))
        verify("9", ignoringModifiers: "(", modifiers: [ctrl, opt, shift], keyCode: kVK_ANSI_9, expected: csi("27;8;40~"))
        verify("0", ignoringModifiers: ")", modifiers: [ctrl, opt, shift], keyCode: kVK_ANSI_0, expected: csi("27;8;41~"))
    }

    func testControlMetaShiftDigitWithControlEquivalentSendsEscPlusControlCharacter() {
        verify("2", ignoringModifiers: "@", modifiers: [ctrl, opt, shift], keyCode: kVK_ANSI_2, expected: escPlus(ctrlChar("@")))
        verify("6", ignoringModifiers: "^", modifiers: [ctrl, opt, shift], keyCode: kVK_ANSI_6, expected: escPlus(ctrlChar("^")))
    }

    func testControlMetaShiftSymbol() {
        verify("\u{1b}", ignoringModifiers: "[", modifiers: [ctrl, opt, shift], keyCode: kVK_ANSI_LeftBracket, expected: escPlus(ctrlChar("[")))
        verify("\u{1d}", ignoringModifiers: "]", modifiers: [ctrl, opt, shift], keyCode: kVK_ANSI_RightBracket, expected: escPlus(ctrlChar("]")))
    }

    func testControlMetaShiftArrow() {
        verify(upArrow, modifiers: [fn, ctrl, opt, shift], keyCode: kVK_UpArrow, expected: csi("1;14A"))
    }

    func testControlMetaShiftFunctionKey() {
        verify(f2, modifiers: [fn, ctrl, opt, shift], keyCode: kVK_F2, expected: csi("1;14Q"))
    }

    func testControlMetaShiftDelete() {
        verify(forwardDelete, modifiers: [fn, ctrl, opt, shift], keyCode: kVK_ForwardDelete, expected: csi("3;14~"))
    }

    func testControlMetaShiftTab() {
        verify(backtab, modifiers: [ctrl, opt, shift], keyCode: kVK_Tab, expected: csi("Z"))
    }

    func testControlMetaShiftEsc() {
        verify(esc, modifiers: [ctrl, opt, shift], keyCode: kVK_Escape, expected: csi("27;8;27~"))
    }

    func testControlMetaShiftBackspace() {
        verify(del, modifiers: [ctrl, opt, shift], keyCode: kVK_Delete, expected: escPlus(ctrlChar("H")))
    }

    // MARK: - Meta-Shift

    func testMetaShiftLetter() {
        verify("\u{c5}", ignoringModifiers: "A", modifiers: [opt, shift], keyCode: kVK_ANSI_A, expected: escPlus("A"))
    }

    func testMetaShiftNumber() {
        verify("\u{2044}", ignoringModifiers: "!", modifiers: [opt, shift], keyCode: kVK_ANSI_1, expected: escPlus("!"))
    }

    func testMetaShiftSymbol() {
        verify("\u{201d}", ignoringModifiers: "{", modifiers: [opt, shift], keyCode: kVK_ANSI_LeftBracket, expected: escPlus("{"))
    }

    // Would be 1;4A if Option were Alt rather than Meta.
    func testMetaShiftArrow() {
        verify(upArrow, modifiers: [fn, opt, shift], keyCode: kVK_UpArrow, expected: csi("1;10A"))
    }

    // Would be 1;4P if Option were Alt rather than Meta.
    func testMetaShiftFunctionKey() {
        verify(f1, modifiers: [fn, opt, shift], keyCode: kVK_F1, expected: csi("1;10P"))
    }

    func testMetaShiftDelete() {
        verify(forwardDelete, modifiers: [fn, opt, shift], keyCode: kVK_ForwardDelete, expected: csi("3;10~"))
    }

    func testMetaShiftTab() {
        verify(backtab, modifiers: [opt, shift], keyCode: kVK_Tab, expected: csi("Z"))
    }

    func testMetaShiftEsc() {
        verify(esc, modifiers: [opt, shift], keyCode: kVK_Escape, expected: csi("27;4;27~"))
    }

    func testMetaShiftBackspace() {
        verify(del, modifiers: [opt, shift], keyCode: kVK_Delete, expected: escPlus(del))
    }
}
