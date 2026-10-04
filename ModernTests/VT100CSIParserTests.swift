//
//  VT100CSIParserTests.swift
//  ModernTests
//
//  Ported from the legacy iTerm2XCTests/VT100CSIParserTest.m. Drives
//  VT100CSIParser directly through an iTermParserContext and checks the token
//  type, the parsed parameters and subparameters, and the dual-mode SGR color
//  decoding that sits on top of the subparameter list.
//

import XCTest
@testable import iTerm2SharedARC

final class VT100CSIParserTests: XCTestCase {
    private var incidentals = CVector()
    private let esc = "\u{1b}"

    override func setUp() {
        super.setUp()
        CVectorCreate(&incidentals, 1)
    }

    override func tearDown() {
        CVectorDestroy(&incidentals)
        super.tearDown()
    }

    // MARK: - Helpers

    // Runs the CSI parser over the UTF-8 bytes of `string` and returns the resulting token.
    private func decode(_ string: String) -> VT100Token {
        var bytes = Array(string.utf8)
        let token = VT100Token()
        bytes.withUnsafeMutableBufferPointer { buf in
            var context = iTermParserContextMake(buf.baseAddress, Int32(buf.count))
            VT100CSIParser.decode(from: &context,
                                  support8BitControlCharacters: false,
                                  incidentals: &incidentals,
                                  token: token)
        }
        return token
    }

    // Decodes ESC [ followed by `body`.
    private func csi(_ body: String) -> VT100Token {
        return decode(esc + "[" + body)
    }

    // All VT100CSIPARAM_MAX parameter slots of the token, whether or not they are set.
    private func parameters(_ token: VT100Token) -> [Int32] {
        return withUnsafeBytes(of: token.csi.pointee.p) { raw in
            Array(raw.bindMemory(to: Int32.self))
        }
    }

    private func parameterCount(_ token: VT100Token) -> Int {
        return Int(token.csi.pointee.count)
    }

    private func subparameters(_ token: VT100Token, parameter: Int32) -> [Int32] {
        var subs = [Int32](repeating: 0, count: Int(VT100CSISUBPARAM_MAX))
        let n = iTermParserGetAllCSISubparametersForParameter(token.csi, parameter, &subs)
        return Array(subs.prefix(Int(n)))
    }

    private func colorValue(_ token: VT100Token, startingAt index: Int32) -> (VT100TerminalColorValue, Int32) {
        var i = index
        let value = VT100TerminalColorValueFromCSI(token.csi, &i)
        return (value, i)
    }

    // Checks that ESC [ `body` yields `type` with exactly `expected` parameters and that the
    // slot after the last one is unset.
    private func assertDefaults(_ body: String,
                                _ type: VT100TerminalTokenType,
                                _ expected: [Int32],
                                file: StaticString = #filePath,
                                line: UInt = #line) {
        let token = csi(body)
        XCTAssertEqual(token.type, type, "token type for CSI \(body.debugDescription)", file: file, line: line)
        XCTAssertEqual(parameterCount(token), expected.count, "parameter count for CSI \(body.debugDescription)", file: file, line: line)
        let p = parameters(token)
        XCTAssertEqual(Array(p.prefix(expected.count)), expected, "parameters for CSI \(body.debugDescription)", file: file, line: line)
        XCTAssertEqual(p[expected.count], -1, "slot past the last parameter must be unset", file: file, line: line)
    }

    private func assertUnsupported(_ body: String, file: StaticString = #filePath, line: UInt = #line) {
        let token = csi(body)
        XCTAssertEqual(token.type, VT100_NOTSUPPORT, "Unexpectedly supported CSI \(body.debugDescription)", file: file, line: line)
    }

    private func assertWindowManipulation(_ p0: Int32,
                                          _ type: VT100TerminalTokenType,
                                          file: StaticString = #filePath,
                                          line: UInt = #line) {
        let token = csi("\(p0)t")
        XCTAssertEqual(token.type, type, "token type for CSI \(p0) t", file: file, line: line)
        XCTAssertEqual(parameters(token)[0], p0, file: file, line: line)
    }

    // MARK: - Incomplete sequences

    func testCSIOnly() {
        XCTAssertEqual(csi("").type, VT100_WAIT)
    }

    func testPrefixOnly() {
        XCTAssertEqual(csi("?").type, VT100_WAIT)
    }

    func testPrefixParameterOnly() {
        XCTAssertEqual(csi("?36").type, VT100_WAIT)
    }

    func testPrefixParameterIntermediateOnly() {
        XCTAssertEqual(csi("?36$").type, VT100_WAIT)
    }

    func testFullyFormedPrefixParameterIntermediateFinal() {
        XCTAssertEqual(csi("?36$p").type, VT100CSI_DECRQM_DEC)
    }

    // MARK: - Parameters

    func testSimpleCSI() {
        let token = csi("D")
        XCTAssertEqual(token.type, VT100CSI_CUB)
        XCTAssertEqual(parameterCount(token), 1)
        XCTAssertEqual(parameters(token)[0], 1)  // Default
    }

    func testSimpleCSIWithParameter() {
        let token = csi("2D")
        XCTAssertEqual(token.type, VT100CSI_CUB)
        XCTAssertEqual(parameterCount(token), 1)
        XCTAssertEqual(parameters(token)[0], 2)
    }

    func testSimpleCSIWithTwoDigitParameter() {
        let token = csi("23D")
        XCTAssertEqual(token.type, VT100CSI_CUB)
        XCTAssertEqual(parameterCount(token), 1)
        XCTAssertEqual(parameters(token)[0], 23)
    }

    func testParameterPrefix() {
        let token = csi(">23c")
        XCTAssertEqual(token.type, VT100CSI_DA2)
        XCTAssertEqual(parameterCount(token), 1)
        XCTAssertEqual(parameters(token)[0], 23)
    }

    func testTwoParameters() {
        let token = csi("5;6H")
        XCTAssertEqual(token.type, VT100CSI_CUP)
        XCTAssertEqual(parameterCount(token), 2)
        XCTAssertEqual(parameters(token)[0], 5)
        XCTAssertEqual(parameters(token)[1], 6)
    }

    func testCursorForwardTabulation() {
        let token = csi("2I")
        XCTAssertEqual(token.type, VT100CSI_CHT)
        XCTAssertEqual(parameterCount(token), 1)
        XCTAssertEqual(parameters(token)[0], 2)
    }

    func testCursorForwardTabulationDefault() {
        let token = csi("I")
        XCTAssertEqual(token.type, VT100CSI_CHT)
        XCTAssertEqual(parameterCount(token), 1)
        XCTAssertEqual(parameters(token)[0], 1)
    }

    func testSubParameter() {
        let token = csi("38:2:255:128:64:0:5:1m")
        XCTAssertEqual(token.type, VT100CSI_SGR)
        XCTAssertEqual(parameterCount(token), 1)
        XCTAssertEqual(parameters(token)[0], 38)
        XCTAssertEqual(subparameters(token, parameter: 0), [2, 255, 128, 64, 0, 5, 1])
    }

    func testBogusCharacterInParameters() {
        XCTAssertEqual(csi("38=m").type, VT100_UNKNOWNCHAR)
    }

    // MARK: - Dual-mode SGR (38:12 / 48:12 / 38:13 / 48:13)

    func testDualModeRGBForeground() {
        let token = csi("38:12:10:20:30:40:50:60m")
        XCTAssertEqual(token.type, VT100CSI_SGR)
        XCTAssertEqual(parameterCount(token), 1)
        XCTAssertEqual(parameters(token)[0], 38)

        let (value, _) = colorValue(token, startingAt: 0)
        XCTAssertEqual(value.mode, ColorMode24bit)
        XCTAssertEqual(value.red, 10)
        XCTAssertEqual(value.green, 20)
        XCTAssertEqual(value.blue, 30)
        XCTAssertTrue(value.hasDarkVariant.boolValue)
        XCTAssertEqual(value.redDark, 40)
        XCTAssertEqual(value.greenDark, 50)
        XCTAssertEqual(value.blueDark, 60)
    }

    func testDualModeRGBBackground() {
        let token = csi("48:12:1:2:3:4:5:6m")
        XCTAssertEqual(token.type, VT100CSI_SGR)
        XCTAssertEqual(parameters(token)[0], 48)

        let (value, _) = colorValue(token, startingAt: 0)
        XCTAssertEqual(value.mode, ColorMode24bit)
        XCTAssertEqual(value.red, 1)
        XCTAssertEqual(value.blue, 3)
        XCTAssertTrue(value.hasDarkVariant.boolValue)
        XCTAssertEqual(value.redDark, 4)
        XCTAssertEqual(value.blueDark, 6)
    }

    func testDualModeIndexedForeground() {
        let token = csi("38:13:208:11m")
        XCTAssertEqual(token.type, VT100CSI_SGR)
        XCTAssertEqual(parameters(token)[0], 38)

        let (value, _) = colorValue(token, startingAt: 0)
        XCTAssertEqual(value.mode, ColorModeNormal)
        XCTAssertEqual(value.red, 208)
        XCTAssertTrue(value.hasDarkVariant.boolValue)
        XCTAssertEqual(value.redDark, 11)
    }

    func testDualModeRejectsSemicolonForm() {
        // 38;12;... is the unsafe semicolon form; the parser must NOT treat it as
        // dual-mode (it would spill trailing values into the SGR stream on
        // non-supporting terminals). Should fall through and not return a valid
        // dual-mode color.
        let token = csi("38;12;1;2;3;4;5;6m")
        XCTAssertEqual(token.type, VT100CSI_SGR)
        XCTAssertEqual(parameters(token)[0], 38)

        let (value, _) = colorValue(token, startingAt: 0)
        XCTAssertFalse(value.hasDarkVariant.boolValue)
    }

    func testDualModeShortSubparametersInvalid() {
        // 38:12 with fewer than 7 subparameters should not produce a dual-mode value.
        let token = csi("38:12:1:2:3m")
        XCTAssertEqual(token.type, VT100CSI_SGR)

        let (value, _) = colorValue(token, startingAt: 0)
        XCTAssertFalse(value.hasDarkVariant.boolValue)
    }

    func testDualModeChainedAfterFallback() {
        // The recommended emission pattern: 38;2;Rf;Gf;Bf followed by 38:12:...
        // Last-wins semantics mean the dual-mode value is what an SGR executor
        // would land on after processing both color specs in order.
        let token = csi("38;2;7;7;7;38:12:11:22:33:44:55:66m")
        XCTAssertEqual(token.type, VT100CSI_SGR)
        // Six top-level params: 38, 2, 7, 7, 7, 38 (the colon-form payload hangs
        // off the second 38 as its sub-parameters).
        XCTAssertEqual(parameterCount(token), 6)

        // First parse: semicolon-form fallback at index 0. Should yield single-color
        // RGB(7,7,7) with no dark variant, advancing index past the consumed params.
        let (fallback, _) = colorValue(token, startingAt: 0)
        XCTAssertEqual(fallback.mode, ColorMode24bit)
        XCTAssertEqual(fallback.red, 7)
        XCTAssertEqual(fallback.green, 7)
        XCTAssertEqual(fallback.blue, 7)
        XCTAssertFalse(fallback.hasDarkVariant.boolValue)

        // Second parse: colon-form override at index 5. Should yield dual-mode
        // RGB with light=(11,22,33) and dark=(44,55,66); this is the value an
        // SGR executor lands on (last-wins).
        let (override, _) = colorValue(token, startingAt: 5)
        XCTAssertEqual(override.mode, ColorMode24bit)
        XCTAssertTrue(override.hasDarkVariant.boolValue)
        XCTAssertEqual(override.red, 11)
        XCTAssertEqual(override.green, 22)
        XCTAssertEqual(override.blue, 33)
        XCTAssertEqual(override.redDark, 44)
        XCTAssertEqual(override.greenDark, 55)
        XCTAssertEqual(override.blueDark, 66)
    }

    // MARK: - Dual-mode SGR 58 (underline color)

    // SGR 58 shares VT100TerminalColorValueFromCSI with 38/48, so the parser already
    // understands sub-modes 12 and 13 for underline. These tests pin the contract.

    func testDualModeRGBUnderline() {
        let token = csi("58:12:10:20:30:40:50:60m")
        XCTAssertEqual(token.type, VT100CSI_SGR)
        XCTAssertEqual(parameterCount(token), 1)
        XCTAssertEqual(parameters(token)[0], 58)

        let (value, _) = colorValue(token, startingAt: 0)
        XCTAssertEqual(value.mode, ColorMode24bit)
        XCTAssertEqual(value.red, 10)
        XCTAssertEqual(value.green, 20)
        XCTAssertEqual(value.blue, 30)
        XCTAssertTrue(value.hasDarkVariant.boolValue)
        XCTAssertEqual(value.redDark, 40)
        XCTAssertEqual(value.greenDark, 50)
        XCTAssertEqual(value.blueDark, 60)
    }

    func testDualModeIndexedUnderline() {
        let token = csi("58:13:208:120m")
        XCTAssertEqual(token.type, VT100CSI_SGR)
        XCTAssertEqual(parameters(token)[0], 58)

        let (value, _) = colorValue(token, startingAt: 0)
        XCTAssertEqual(value.mode, ColorModeNormal)
        XCTAssertEqual(value.red, 208)
        XCTAssertTrue(value.hasDarkVariant.boolValue)
        XCTAssertEqual(value.redDark, 120)
    }

    // MARK: - Intermediate bytes and garbage

    func testIntermediateByte() {
        // DECSCUSR with parameter 3 (set cursor to "blink underline"), which has an intermediate byte
        // of the space character.
        let token = csi("3 q")
        XCTAssertEqual(token.type, VT100CSI_DECSCUSR)
        XCTAssertEqual(parameterCount(token), 1)
        XCTAssertEqual(parameters(token)[0], 3)
    }

    func testBogusCharInParameterSection() {
        XCTAssertEqual(csi("1<m").type, VT100_UNKNOWNCHAR)
    }

    func testGarbageIgnored() {
        XCTAssertEqual(csi("1\u{7f}m").type, VT100CSI_SGR)
    }

    func testBadGarbageCausesFailure() {
        XCTAssertEqual(csi("1\u{7f} 2m").type, VT100_UNKNOWNCHAR)
    }

    // MARK: - Default parameter values, one test per supported final byte

    func testDefaultParameters_ICH() { assertDefaults("@", VT100CSI_ICH, [1]) }
    func testDefaultParameters_CUU() { assertDefaults("A", VT100CSI_CUU, [1]) }
    func testDefaultParameters_CUD() { assertDefaults("B", VT100CSI_CUD, [1]) }
    func testDefaultParameters_CUF() { assertDefaults("C", VT100CSI_CUF, [1]) }
    func testDefaultParameters_CUB() { assertDefaults("D", VT100CSI_CUB, [1]) }
    func testDefaultParameters_CNL() { assertDefaults("E", VT100CSI_CNL, [1]) }
    func testDefaultParameters_CPL() { assertDefaults("F", VT100CSI_CPL, [1]) }
    func testDefaultParameters_CHA() { assertDefaults("G", ANSICSI_CHA, [1]) }
    func testDefaultParameters_CUP() { assertDefaults("H", VT100CSI_CUP, [1, 1]) }
    func testDefaultParameters_ED() { assertDefaults("J", VT100CSI_ED, [0]) }
    func testDefaultParameters_EL() { assertDefaults("K", VT100CSI_EL, [0]) }
    func testDefaultParameters_INSLN() { assertDefaults("L", XTERMCC_INSLN, [1]) }
    func testDefaultParameters_DELLN() { assertDefaults("M", XTERMCC_DELLN, [1]) }
    func testDefaultParameters_DELCH() { assertDefaults("P", XTERMCC_DELCH, [1]) }
    func testDefaultParameters_SU() { assertDefaults("S", XTERMCC_SU, [1]) }
    func testDefaultParameters_SD() { assertDefaults("T", XTERMCC_SD, [1]) }
    func testDefaultParameters_ECH() { assertDefaults("X", ANSICSI_ECH, [1]) }
    func testDefaultParameters_CBT() { assertDefaults("Z", ANSICSI_CBT, [1]) }
    func testDefaultParameters_REP() { assertDefaults("b", VT100CSI_REP, [1]) }
    func testDefaultParameters_DA() { assertDefaults("c", VT100CSI_DA, [0]) }
    func testDefaultParameters_DA2() { assertDefaults(">c", VT100CSI_DA2, [0]) }
    func testDefaultParameters_VPA() { assertDefaults("d", ANSICSI_VPA, [1]) }
    func testDefaultParameters_VPR() { assertDefaults("e", ANSICSI_VPR, [1]) }
    func testDefaultParameters_HVP() { assertDefaults("f", VT100CSI_HVP, [1, 1]) }
    func testDefaultParameters_TBC() { assertDefaults("g", VT100CSI_TBC, [0]) }
    func testDefaultParameters_SM() { assertDefaults("h", VT100CSI_SM, []) }
    func testDefaultParameters_DECSET() { assertDefaults("?h", VT100CSI_DECSET, []) }
    func testDefaultParameters_PRINT() { assertDefaults("i", ANSICSI_PRINT, [0]) }
    func testDefaultParameters_RM() { assertDefaults("l", VT100CSI_RM, []) }
    func testDefaultParameters_DECRST() { assertDefaults("?l", VT100CSI_DECRST, []) }
    func testDefaultParameters_SGR() { assertDefaults("m", VT100CSI_SGR, [0]) }
    func testDefaultParameters_SetModifiers() { assertDefaults(">m", VT100CSI_SET_MODIFIERS, []) }
    func testDefaultParameters_DSR() { assertDefaults("n", VT100CSI_DSR, [0]) }
    func testDefaultParameters_ResetModifiers() { assertDefaults(">n", VT100CSI_RESET_MODIFIERS, []) }
    func testDefaultParameters_DECDSR() { assertDefaults("?n", VT100CSI_DECDSR, [0]) }
    func testDefaultParameters_DECSTR() { assertDefaults("!p", VT100CSI_DECSTR, []) }
    func testDefaultParameters_DECRQM_ANSI() { assertDefaults("$p", VT100CSI_DECRQM_ANSI, [0]) }
    func testDefaultParameters_DECRQM_DEC() { assertDefaults("?$p", VT100CSI_DECRQM_DEC, [0]) }
    func testDefaultParameters_DECSCUSR() { assertDefaults(" q", VT100CSI_DECSCUSR, [0]) }
    // The legacy test listed DECSCL as unsupported; support was added for issue 11690.
    func testDefaultParameters_DECSCL() { assertDefaults("\"p", VT100CSI_DECSCL, [0, 1]) }
    func testDefaultParameters_DECSTBM() { assertDefaults("r", VT100CSI_DECSTBM, []) }
    func testDefaultParameters_DECSLRMOrSCP() { assertDefaults("s", VT100CSI_DECSLRM_OR_ANSICSI_SCP, []) }
    func testDefaultParameters_RCP() { assertDefaults("u", ANSICSI_RCP, []) }
    func testDefaultParameters_DECRQCRA() { assertDefaults("*y", VT100CSI_DECRQCRA, [-1, -1, 1]) }
    func testDefaultParameters_XTREPORTSGR() { assertDefaults("#|", VT100CSI_XTREPORTSGR, [1, 1, 1, 1]) }
    func testDefaultParameters_XDA() { assertDefaults(">q", VT100CSI_XDA, [0]) }
    func testDefaultParameters_PushKeyReportingMode() { assertDefaults(">u", VT100CSI_PUSH_KEY_REPORTING_MODE, [0]) }
    func testDefaultParameters_PopKeyReportingMode() { assertDefaults("<u", VT100CSI_POP_KEY_REPORTING_MODE, [0]) }
    func testDefaultParameters_QueryKeyReportingMode() { assertDefaults("?u", VT100CSI_QUERY_KEY_REPORTING_MODE, []) }

    // MARK: - Unsupported codes
    // These are here to remind you to write a test when implementing support for a new CSI code.

    func testUnsupported_HighlightMouseTracking() { assertUnsupported("1;1;1;1;1T") }
    func testUnsupported_DECMediaCopy() { assertUnsupported("?1i") }
    func testUnsupported_PointerMode() { assertUnsupported(">0p") }
    func testUnsupported_DECLL() { assertUnsupported("q") }
    func testUnsupported_SaveDECPrivateModes() { assertUnsupported("?1s") }
    func testUnsupported_TitleModes() { assertUnsupported(">1;60t") }
    func testUnsupported_DECSWBV() { assertUnsupported("0 t") }
    func testUnsupported_DECSMBV() { assertUnsupported("1 u") }
    func testUnsupported_DECEFR() { assertUnsupported("1;2;3;4'w") }
    func testUnsupported_DECREQTPARM() { assertUnsupported("x") }
    func testUnsupported_DECELR() { assertUnsupported("0;0'z") }
    func testUnsupported_DECSLE() { assertUnsupported("'{") }
    func testUnsupported_DECRQLP() { assertUnsupported("'|") }

    // MARK: - Window manipulation (CSI Ps t)

    func testWindowManipulation_Deiconify() { assertWindowManipulation(1, XTERMCC_DEICONIFY) }
    func testWindowManipulation_Iconify() { assertWindowManipulation(2, XTERMCC_ICONIFY) }
    func testWindowManipulation_WindowPosition() { assertWindowManipulation(3, XTERMCC_WINDOWPOS) }
    func testWindowManipulation_WindowSizeInPixels() { assertWindowManipulation(4, XTERMCC_WINDOWSIZE_PIXEL) }
    func testWindowManipulation_Raise() { assertWindowManipulation(5, XTERMCC_RAISE) }
    func testWindowManipulation_Lower() { assertWindowManipulation(6, XTERMCC_LOWER) }
    // 7 is not supported (Refresh the window)
    func testWindowManipulation_WindowSize() { assertWindowManipulation(8, XTERMCC_WINDOWSIZE) }
    // 9 is not supported (Various maximize window actions)
    // 10 is not supported (Various full-screen actions)
    func testWindowManipulation_ReportWindowState() { assertWindowManipulation(11, XTERMCC_REPORT_WIN_STATE) }
    // 12 is not defined
    func testWindowManipulation_ReportWindowPosition() { assertWindowManipulation(13, XTERMCC_REPORT_WIN_POS) }
    func testWindowManipulation_ReportWindowPixelSize() { assertWindowManipulation(14, XTERMCC_REPORT_WIN_PIX_SIZE) }
    // 15, 16, and 17 are not defined
    func testWindowManipulation_ReportWindowSize() { assertWindowManipulation(18, XTERMCC_REPORT_WIN_SIZE) }
    func testWindowManipulation_ReportScreenSize() { assertWindowManipulation(19, XTERMCC_REPORT_SCREEN_SIZE) }
    func testWindowManipulation_ReportIconTitle() { assertWindowManipulation(20, XTERMCC_REPORT_ICON_TITLE) }
    func testWindowManipulation_ReportWindowTitle() { assertWindowManipulation(21, XTERMCC_REPORT_WIN_TITLE) }
    func testWindowManipulation_PushTitle() { assertWindowManipulation(22, XTERMCC_PUSH_TITLE) }
    func testWindowManipulation_PopTitle() { assertWindowManipulation(23, XTERMCC_POP_TITLE) }
    // 24+ is not supported (resize to Ps lines - DECSLPP)

    // MARK: - Parameter limits

    func testDECSCLWithParameters() {
        let token = csi("61;0\"p")
        XCTAssertEqual(token.type, VT100CSI_DECSCL)
        XCTAssertEqual(parameterCount(token), 2)
        XCTAssertEqual(Array(parameters(token).prefix(2)), [61, 0])
    }

    func testParameterOverflow() {
        XCTAssertEqual(csi("9999999999m").type, VT100_UNKNOWNCHAR)
    }

    func testMaximumNumberOfParameters() {
        // VT100CSIPARAM_MAX is 16, and all 16 slots should be usable.
        let token = csi("1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16m")
        XCTAssertEqual(token.type, VT100CSI_SGR)
        XCTAssertEqual(parameterCount(token), 16)
        XCTAssertEqual(parameters(token)[15], 16)
    }

    func testParametersPastTheMaximumAreDiscarded() {
        let token = csi("1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;17m")
        XCTAssertEqual(token.type, VT100CSI_SGR)
        XCTAssertEqual(parameterCount(token), 16)
        XCTAssertEqual(parameters(token)[15], 16)
    }

    func testSubparametersOfADiscardedParameterDoNotAttachToTheLastOneKept() {
        // The 17th parameter doesn't fit. Its subparameter must be discarded with it: attaching it to
        // the 16th parameter would turn plain underline (4) into dashed underline (4:5).
        let token = csi("1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;4;3:5m")
        XCTAssertEqual(token.type, VT100CSI_SGR)
        XCTAssertEqual(parameterCount(token), 16)
        XCTAssertEqual(parameters(token)[15], 4)
        XCTAssertEqual(iTermParserGetNumberOfCSISubparameters(token.csi, 15), 0)
    }

    func testSubparametersOfTheSixteenthParameter() {
        let token = csi("1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;38:2:255:0:0m")
        XCTAssertEqual(token.type, VT100CSI_SGR)
        XCTAssertEqual(parameterCount(token), 16)
        XCTAssertEqual(parameters(token)[15], 38)
        XCTAssertEqual(subparameters(token, parameter: 15), [2, 255, 0, 0])
    }

    func testSubparametersOfABlankSixteenthParameterAreKept() {
        // The 16th parameter here is an implied blank created by a doubled semicolon. It still fills a
        // valid slot (index 15), so a subparameter attached to it must be kept, not discarded as if it
        // belonged to an overflow parameter beyond the 16th.
        let token = csi("1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;;:5m")
        XCTAssertEqual(token.type, VT100CSI_SGR)
        XCTAssertEqual(parameterCount(token), 16)
        XCTAssertEqual(iTermParserGetNumberOfCSISubparameters(token.csi, 15), 1)
        XCTAssertEqual(iTermParserGetCSISubparameter(token.csi, 15, 0), 5)
    }

    func testGetCSISubparameterByIndex() {
        let token = csi("4:1:2:3m")
        XCTAssertEqual(token.type, VT100CSI_SGR)
        XCTAssertEqual(iTermParserGetCSISubparameter(token.csi, 0, 0), 1)
        XCTAssertEqual(iTermParserGetCSISubparameter(token.csi, 0, 1), 2)
        XCTAssertEqual(iTermParserGetCSISubparameter(token.csi, 0, 2), 3)
        XCTAssertEqual(iTermParserGetCSISubparameter(token.csi, 0, 3), -1)
    }

    func testSubparameterAfterAFullParameterListBelongsToTheLastParameter() {
        // A parameter substring that starts with a colon doesn't open a parameter of its own, so this
        // subparameter belongs to the 16th parameter, which was stored. Nothing overflowed, so it must
        // be kept: the list being full is not by itself a reason to discard it.
        let token = csi("1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;:5m")
        XCTAssertEqual(token.type, VT100CSI_SGR)
        XCTAssertEqual(parameterCount(token), 16)
        XCTAssertEqual(iTermParserGetNumberOfCSISubparameters(token.csi, 15), 1)
        XCTAssertEqual(iTermParserGetCSISubparameter(token.csi, 15, 0), 5)
    }

    func testSubparameterAfterADiscardedParameterIsDiscarded() {
        // Here the 17th parameter was discarded, so the subparameter that follows it belongs to a
        // parameter that doesn't exist and must go with it rather than landing on the 16th.
        let token = csi("1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;17;:5m")
        XCTAssertEqual(token.type, VT100CSI_SGR)
        XCTAssertEqual(parameterCount(token), 16)
        XCTAssertEqual(iTermParserGetNumberOfCSISubparameters(token.csi, 15), 0)
    }
}
