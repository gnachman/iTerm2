//
//  TermkeyKeyMapperTests.swift
//  iTerm2 ModernTests
//
//  Ported from iTermTermkeyKeyMapperTest.m. Runs synthesized key-down events through
//  iTermTermkeyKeyMapper (the libtermkey / CSI u protocol) and checks the exact bytes sent.
//  The modifier flag values are the raw flags AppKit attached to real key events when the
//  cases were recorded, including the device-dependent left/right bits.
//

import Carbon.HIToolbox
import XCTest
@testable import iTerm2SharedARC

final class TermkeyKeyMapperTests: XCTestCase, iTermTermkeyKeyMapperDelegate {
    private var mapper: iTermTermkeyKeyMapper!
    private var optionKeyBehavior = iTermOptionKeyBehavior.OPT_NORMAL

    private let esc = "\u{1b}"
    private let del = "\u{7f}"
    private let cr = "\r"
    private let tab = "\t"
    private let backtab = "\u{19}"

    override func setUp() {
        super.setUp()
        mapper = iTermTermkeyKeyMapper()
        mapper.delegate = self
        optionKeyBehavior = .OPT_NORMAL
    }

    override func tearDown() {
        mapper = nil
        super.tearDown()
    }

    // MARK: - iTermTermkeyKeyMapperDelegate

    func termkeyKeyMapperWillMapKey(_ termkeyKeyMapper: iTermTermkeyKeyMapper) {
        termkeyKeyMapper.configuration = iTermTermkeyKeyMapperConfiguration(
            encoding: String.Encoding.utf8.rawValue,
            leftOptionKey: optionKeyBehavior,
            rightOptionKey: optionKeyBehavior,
            applicationCursorMode: false,
            applicationKeypadMode: false)
    }

    // MARK: - Helpers

    private func flags(_ raw: UInt) -> NSEvent.ModifierFlags {
        return NSEvent.ModifierFlags(rawValue: raw)
    }

    /// The bytes the mapper would send for the event: the pre-Cocoa string encoded as UTF-8
    /// if it handles the key there, otherwise the post-Cocoa data.
    private func mappedBytes(_ characters: String,
                             ignoringModifiers: String,
                             modifiers: UInt,
                             keyCode: Int) -> [UInt8]? {
        guard let event = NSEvent.keyEvent(with: .keyDown,
                                           location: .zero,
                                           modifierFlags: flags(modifiers),
                                           timestamp: 0,
                                           windowNumber: 0,
                                           context: nil,
                                           characters: characters,
                                           charactersIgnoringModifiers: ignoringModifiers,
                                           isARepeat: false,
                                           keyCode: UInt16(keyCode)) else {
            return nil
        }
        if let string = mapper.keyMapperString(forPreCocoaEvent: event) {
            return Array(string.utf8)
        }
        if let data = mapper.keyMapperData(forPostCocoaEvent: event) {
            return [UInt8](data)
        }
        return nil
    }

    private func verify(_ characters: String,
                        ignoringModifiers: String? = nil,
                        modifiers: UInt,
                        keyCode: Int,
                        expected: String,
                        file: StaticString = #filePath,
                        line: UInt = #line) {
        verifyBytes(characters,
                    ignoringModifiers: ignoringModifiers,
                    modifiers: modifiers,
                    keyCode: keyCode,
                    expected: Array(expected.utf8),
                    file: file,
                    line: line)
    }

    private func verifyBytes(_ characters: String,
                             ignoringModifiers: String? = nil,
                             modifiers: UInt,
                             keyCode: Int,
                             expected: [UInt8],
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        guard let actual = mappedBytes(characters,
                                       ignoringModifiers: ignoringModifiers ?? characters,
                                       modifiers: modifiers,
                                       keyCode: keyCode) else {
            XCTFail("Mapper produced nothing; expected \(describe(expected))", file: file, line: line)
            return
        }
        XCTAssertEqual(actual, expected,
                       "got \(describe(actual)), expected \(describe(expected))",
                       file: file, line: line)
    }

    private func describe(_ bytes: [UInt8]) -> String {
        return bytes.map { byte in
            if byte >= 0x20 && byte < 0x7f {
                return String(UnicodeScalar(byte))
            }
            return String(format: "\\x%02x", byte)
        }.joined()
    }

    private func escPlus(_ string: String) -> String {
        return esc + string
    }

    /// CSI codepoint ; modifier u
    private func csiU(_ codepoint: Int, modifier: Int) -> String {
        return "\(esc)[\(codepoint);\(modifier)u"
    }

    /// CSI args Z
    private func csiZ(_ args: [String]) -> String {
        return "\(esc)[\(args.joined(separator: ";"))Z"
    }

    /// CSI number ~ or CSI number ; modifier ~
    private func csiTilde(_ number: Int, modifier: Int) -> String {
        if modifier == 1 {
            return "\(esc)[\(number)~"
        }
        return "\(esc)[\(number);\(modifier)~"
    }

    /// CSI code or CSI 1 ; modifier code, for the cursor and F1-F4 keys.
    private func special(_ code: String, modifier: Int) -> String {
        if modifier == 1 {
            return "\(esc)[\(code)"
        }
        return "\(esc)[1;\(modifier)\(code)"
    }

    // MARK: - Modified Unicode

    func testUnmodifiedAscii() {
        verify("x", modifiers: 0x100, keyCode: kVK_ANSI_X, expected: "x")
    }

    func testUnmodifiedNonAscii() {
        verify("\u{c4}", modifiers: 0x20002, keyCode: kVK_ANSI_Quote, expected: "\u{c4}")
    }

    func testEscPlusAscii() {
        optionKeyBehavior = .OPT_ESC
        verify("\u{e5}", ignoringModifiers: "a", modifiers: 0x80140, keyCode: kVK_ANSI_A, expected: escPlus("a"))
    }

    func testEscPlusNonAscii() {
        optionKeyBehavior = .OPT_ESC
        verify("\u{e6}", ignoringModifiers: "\u{e4}", modifiers: 0x80040, keyCode: kVK_ANSI_Quote, expected: escPlus("\u{e4}"))
    }

    // Suspected bug in iTermTermkeyKeyMapper (sources/Keyboard/iTermTermkeyKeyMapper.m),
    // present since the mapper was added in 0ac126e7c. With Option configured as Meta,
    // termkeySequenceForCodePoint:modifiers:keyCode: calls dataForOptionModifiedKeypress,
    // which correctly produces the single byte 0xe2 ("b" | 0x80), but then re-decodes it
    // with -[NSString initWithData:encoding:] using the profile encoding (UTF-8). A lone
    // byte >= 0x80 is not valid UTF-8, so that returns nil, postCocoaData returns nil, and
    // PTYSession sends nothing: the keypress is dropped. iTermStandardKeyMapper returns the
    // NSData directly and sends the meta byte (see CompanionKeyInjectionTests). The legacy
    // ObjC test masked this because its expected value went through the same lossy decode
    // and compared nil to nil.
    func testMetaAscii() {
        optionKeyBehavior = .OPT_META
        XCTExpectFailure("iTermTermkeyKeyMapper drops Option+ASCII when Option is Meta: termkeySequenceForCodePoint re-decodes the 8-bit meta byte as UTF-8 and gets nil") {
            verifyBytes("\u{222b}", ignoringModifiers: "b", modifiers: 0x80140, keyCode: kVK_ANSI_B, expected: [UInt8(ascii: "b") | 0x80])
        }
    }

    func testBang() {
        verify("!", modifiers: 0x20102, keyCode: kVK_ANSI_1, expected: "!")
    }

    func testCtrlI() {
        verify(tab, ignoringModifiers: "i", modifiers: 0x42100, keyCode: kVK_ANSI_I, expected: csiU(105, modifier: 5))
    }

    func testCtrlM() {
        verify(cr, ignoringModifiers: "m", modifiers: 0x42100, keyCode: kVK_ANSI_M, expected: csiU(109, modifier: 5))
    }

    func testCtrlOpenBracket() {
        verify(esc, ignoringModifiers: "[", modifiers: 0x42100, keyCode: kVK_ANSI_LeftBracket, expected: csiU(91, modifier: 5))
    }

    func testCtrlShiftI() {
        verify(tab, ignoringModifiers: "I", modifiers: 0x62102, keyCode: kVK_ANSI_I, expected: csiU(73, modifier: 5))
    }

    func testCtrlShiftM() {
        verify(cr, ignoringModifiers: "M", modifiers: 0x62102, keyCode: kVK_ANSI_M, expected: csiU(77, modifier: 5))
    }

    func testCtrlOpenBrace() {
        verify(esc, ignoringModifiers: "{", modifiers: 0x42100, keyCode: kVK_ANSI_LeftBracket, expected: csiU(123, modifier: 5))
    }

    func testTab() {
        verify(tab, modifiers: 0x100, keyCode: kVK_Tab, expected: tab)
    }

    func testEnter() {
        verify(cr, modifiers: 0x100, keyCode: kVK_Return, expected: cr)
    }

    func testEscape() {
        verify(esc, modifiers: 0x100, keyCode: kVK_Escape, expected: esc)
    }

    func testSpace() {
        verify(" ", modifiers: 0x100, keyCode: kVK_Space, expected: " ")
    }

    func testCtrlA() {
        verify("\u{01}", ignoringModifiers: "a", modifiers: 0x42100, keyCode: kVK_ANSI_A, expected: "\u{01}")
    }

    func testCtrlB() {
        verify("\u{02}", ignoringModifiers: "b", modifiers: 0x42100, keyCode: kVK_ANSI_B, expected: "\u{02}")
    }

    func testCtrlShiftA() {
        verify("\u{01}", ignoringModifiers: "A", modifiers: 0x62102, keyCode: kVK_ANSI_A, expected: csiU(65, modifier: 5))
    }

    func testCtrlShiftB() {
        verify("\u{02}", ignoringModifiers: "B", modifiers: 0x62102, keyCode: kVK_ANSI_B, expected: csiU(66, modifier: 5))
    }

    func testCtrlAltC() {
        verify("\u{e7}", ignoringModifiers: "c", modifiers: 0xc2140, keyCode: kVK_ANSI_C, expected: csiU(Int(UInt8(ascii: "c")), modifier: 7))
    }

    func testAltBackspace() {
        optionKeyBehavior = .OPT_ESC
        verify(del, modifiers: 0x80140, keyCode: kVK_Delete, expected: escPlus(del))
    }

    // MARK: - Modified C0 Controls

    func testAltShiftBackspace() {
        optionKeyBehavior = .OPT_ESC
        verify(del, modifiers: 0xa0142, keyCode: kVK_Delete, expected: csiU(0x7f, modifier: 4))
    }

    func testShiftEnter() {
        verify(cr, modifiers: 0x20102, keyCode: kVK_Return, expected: csiU(13, modifier: 2))
    }

    func testShiftEscape() {
        verify(esc, modifiers: 0x20104, keyCode: kVK_Escape, expected: csiU(27, modifier: 2))
    }

    func testShiftBackspace() {
        verify(del, modifiers: 0x20102, keyCode: kVK_Delete, expected: csiU(127, modifier: 2))
    }

    func testCtrlEnter() {
        verify(cr, modifiers: 0x42100, keyCode: kVK_Return, expected: csiU(13, modifier: 5))
    }

    func testCtrlEscape() {
        verify(esc, modifiers: 0x42100, keyCode: kVK_Escape, expected: csiU(27, modifier: 5))
    }

    func testCtrlBackspace() {
        verify(del, modifiers: 0x42100, keyCode: kVK_Delete, expected: csiU(127, modifier: 5))
    }

    func testShiftSpace() {
        verify(" ", modifiers: 0x20102, keyCode: kVK_Space, expected: csiU(32, modifier: 2))
    }

    func testCtrlSpace() {
        verify("\u{0}", ignoringModifiers: " ", modifiers: 0x42100, keyCode: kVK_Space, expected: "\u{0}")
    }

    func testShiftCtrlSpace() {
        verify("\u{0}", ignoringModifiers: " ", modifiers: 0x62102, keyCode: kVK_Space, expected: csiU(32, modifier: 6))
    }

    func testShiftTab() {
        verify(backtab, modifiers: 0x20102, keyCode: kVK_Tab, expected: csiZ([]))
    }

    func testCtrlTab() {
        verify(tab, modifiers: 0x42100, keyCode: kVK_Tab, expected: csiU(9, modifier: 5))
    }

    func testShiftCtrlTab() {
        verify(backtab, modifiers: 0x62102, keyCode: kVK_Tab, expected: csiZ(["1", "5"]))
    }

    // MARK: - Special Keys

    func testInsert() {
        verify("\u{f746}", modifiers: 0x800100, keyCode: kVK_Help, expected: csiTilde(2, modifier: 1))
    }

    func testDelete() {
        verify("\u{f728}", modifiers: 0x800000, keyCode: kVK_ForwardDelete, expected: csiTilde(3, modifier: 1))
    }

    func testPageUp() {
        verify("\u{f72c}", modifiers: 0x800100, keyCode: kVK_PageUp, expected: csiTilde(5, modifier: 1))
    }

    func testPageDown() {
        verify("\u{f72d}", modifiers: 0x800100, keyCode: kVK_PageDown, expected: csiTilde(6, modifier: 1))
    }

    func testF5() {
        verify("\u{f708}", modifiers: 0x800000, keyCode: kVK_F5, expected: csiTilde(15, modifier: 1))
    }

    func testF12() {
        verify("\u{f70f}", modifiers: 0x800000, keyCode: kVK_F12, expected: csiTilde(24, modifier: 1))
    }

    // MARK: - Really Special Keypresses

    func testUp() {
        verify("\u{f700}", modifiers: 0xa00100, keyCode: kVK_UpArrow, expected: special("A", modifier: 1))
    }

    func testDown() {
        verify("\u{f701}", modifiers: 0xa00100, keyCode: kVK_DownArrow, expected: special("B", modifier: 1))
    }

    func testRight() {
        verify("\u{f703}", modifiers: 0xa00100, keyCode: kVK_RightArrow, expected: special("C", modifier: 1))
    }

    func testLeft() {
        verify("\u{f702}", modifiers: 0xa00100, keyCode: kVK_LeftArrow, expected: special("D", modifier: 1))
    }

    func testEnd() {
        verify("\u{f72b}", modifiers: 0x800100, keyCode: kVK_End, expected: special("F", modifier: 1))
    }

    func testHome() {
        verify("\u{f729}", modifiers: 0x800100, keyCode: kVK_Home, expected: special("H", modifier: 1))
    }

    func testF1() {
        verify("\u{f704}", modifiers: 0x800000, keyCode: kVK_F1, expected: special("P", modifier: 1))
    }
}
