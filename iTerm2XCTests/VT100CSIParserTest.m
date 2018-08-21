//
//  VT100CSIParserTest.m
//  iTerm2
//
//  Created by George Nachman on 1/8/15.
//
//

#import <XCTest/XCTest.h>
#import "VT100CSIParser.h"

@interface VT100CSIParserTest : XCTestCase
@end

@implementation VT100CSIParserTest {
    CVector _incidentals;
    iTermParserContext _context;
}

- (void)setUp {
    CVectorCreate(&_incidentals, 1);
}

- (void)tearDown {
    CVectorDestroy(&_incidentals);
}

- (VT100Token *)tokenForDataWithFormat:(NSString *)formatString, ... {
    va_list args;
    va_start(args, formatString);
    NSString *string = [[[NSString alloc] initWithFormat:formatString arguments:args] autorelease];
    va_end(args);

    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    VT100Token *token = [[[VT100Token alloc] init] autorelease];
    _context = iTermParserContextMake((unsigned char *)data.bytes, data.length);
    [VT100CSIParser decodeFromContext:&_context incidentals:&_incidentals token:token];
    return token;
}

- (void)testCSIOnly {
    VT100Token *token = [self tokenForDataWithFormat:@"%c[", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
}

- (void)testPrefixOnly {
    VT100Token *token = [self tokenForDataWithFormat:@"%c[?", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
}

- (void)testPrefixParameterOnly {
    VT100Token *token = [self tokenForDataWithFormat:@"%c[?36", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
}

- (void)testPrefixParameterIntermediateOnly {
    VT100Token *token = [self tokenForDataWithFormat:@"%c[?36$", VT100CC_ESC];
    XCTAssert(token->type == VT100_WAIT);
}

- (void)testFullyFormedPrefixParameterIntermediateFinal {
    VT100Token *token = [self tokenForDataWithFormat:@"%c[?36$p", VT100CC_ESC];
    XCTAssert(token->type == VT100_NOTSUPPORT);  // Sadly, DECRQM isn't supported yet, so this test is incomplete.
}

- (void)testSimpleCSI {
    VT100Token *token = [self tokenForDataWithFormat:@"%c[D", VT100CC_ESC];
    XCTAssert(token->type == VT100CSI_CUB);
    XCTAssert(token.csi->count == 1);
    XCTAssert(token.csi->p[0] == 1);  // Default
}

- (void)testSimpleCSIWithParameter {
    VT100Token *token = [self tokenForDataWithFormat:@"%c[2D", VT100CC_ESC];
    XCTAssert(token->type == VT100CSI_CUB);
    XCTAssert(token.csi->count == 1);
    XCTAssert(token.csi->p[0] == 2);  // Parameter
}

- (void)testSimpleCSIWithTwoDigitParameter {
    VT100Token *token = [self tokenForDataWithFormat:@"%c[23D", VT100CC_ESC];
    XCTAssert(token->type == VT100CSI_CUB);
    XCTAssert(token.csi->count == 1);
    XCTAssert(token.csi->p[0] == 23);  // Parameter
}

- (void)testParameterPrefix {
    VT100Token *token = [self tokenForDataWithFormat:@"%c[>23c", VT100CC_ESC];
    XCTAssert(token->type == VT100CSI_DA2);
    XCTAssert(token.csi->count == 1);
    XCTAssert(token.csi->p[0] == 23);  // Parameter
}

- (void)testTwoParameters {
    VT100Token *token = [self tokenForDataWithFormat:@"%c[5;6H", VT100CC_ESC];
    XCTAssert(token->type == VT100CSI_CUP);
    XCTAssert(token.csi->count == 2);
    XCTAssert(token.csi->p[0] == 5);
    XCTAssert(token.csi->p[1] == 6);
}

- (void)testCursorForwardTabulation {
    VT100Token *token = [self tokenForDataWithFormat:@"%c[2I", VT100CC_ESC];
    XCTAssert(token->type == VT100CSI_CHT);
    XCTAssert(token.csi->count == 1);
    XCTAssert(token.csi->p[0] == 2);
}

- (void)testCursorForwardTabulationDefault {
    VT100Token *token = [self tokenForDataWithFormat:@"%c[I", VT100CC_ESC];
    XCTAssert(token->type == VT100CSI_CHT);
    XCTAssert(token.csi->count == 1);
    XCTAssert(token.csi->p[0] == 1);
}

- (void)testSubParameter {
    VT100Token *token = [self tokenForDataWithFormat:@"%c[38:2:255:128:64:0:5:1m", VT100CC_ESC];
    XCTAssert(token->type == VT100CSI_SGR);
    XCTAssert(token.csi->count == 1);
    XCTAssert(token.csi->p[0] == 38);

    int subs[VT100CSISUBPARAM_MAX];
    int numberOfSubparameters = iTermParserGetAllCSISubparametersForParameter(token.csi, 0, subs);

    XCTAssert(numberOfSubparameters == 7);
    XCTAssert(subs[0] == 2);
    XCTAssert(subs[1] == 255);
    XCTAssert(subs[2] == 128);
    XCTAssert(subs[3] == 64);
    XCTAssert(subs[4] == 0);
    XCTAssert(subs[5] == 5);
    XCTAssert(subs[6] == 1);
}

- (void)testBogusCharacterInParameters {
    VT100Token *token = [self tokenForDataWithFormat:@"%c[38=m", VT100CC_ESC];
    XCTAssert(token->type == VT100_UNKNOWNCHAR);
}

- (void)testIntermediateByte {
    // DECSCUSR with paraemter 3 (set cursor to "blink underline"), which has an intermediate byte
    // of the space character.
    VT100Token *token = [self tokenForDataWithFormat:@"%c[3 q", VT100CC_ESC];
    XCTAssert(token->type == VT100CSI_DECSCUSR);
    XCTAssert(token.csi->count == 1);
    XCTAssert(token.csi->p[0] == 3);
}

- (void)testBogusCharInParameterSection {
    VT100Token *token = [self tokenForDataWithFormat:@"%c[1<m", VT100CC_ESC];
    XCTAssert(token->type == VT100_UNKNOWNCHAR);
}

- (void)testGarbageIgnored {
    VT100Token *token = [self tokenForDataWithFormat:@"%c[1%cm", VT100CC_ESC, 0x7f];
    XCTAssert(token->type == VT100CSI_SGR);
}

- (void)testBadGarbageCausesFailure {
    VT100Token *token = [self tokenForDataWithFormat:@"%c[1%c 2m", VT100CC_ESC, 0x7f];
    XCTAssert(token->type == VT100_UNKNOWNCHAR);
}

- (void)testDefaultParameterValues {
    struct {
        char prefix;
        char intermediate;
        char final;
        VT100TerminalTokenType tokenType;
        int p0;
        int p1;
        int p2;
        int p3;
    } simpleCodes[] = {
        { 0, 0, '@', VT100CSI_ICH, 1, -1, -1, -1 },
        { 0, 0, 'A', VT100CSI_CUU, 1, -1, -1, -1 },
        { 0, 0, 'B', VT100CSI_CUD, 1, -1, -1, -1 },
        { 0, 0, 'C', VT100CSI_CUF, 1, -1, -1, -1 },
        { 0, 0, 'D', VT100CSI_CUB, 1, -1, -1, -1 },
        { 0, 0, 'E', VT100CSI_CNL, 1, -1, -1, -1 },
        { 0, 0, 'F', VT100CSI_CPL, 1, -1, -1, -1 },
        { 0, 0, 'G', ANSICSI_CHA, 1, -1, -1, -1 },
        { 0, 0, 'H', VT100CSI_CUP, 1, 1, -1, -1 },
        // I not supported (Cursor Forward Tabulation P s tab stops (default = 1) (CHT))
        { 0, 0, 'J', VT100CSI_ED, 0, -1, -1, -1 },
        // ?J not supported (Erase in Display (DECSED))
        { 0, 0, 'K', VT100CSI_EL, 0, -1, -1, -1 },
        // ?K not supported ((Erase in Line (DECSEL))
        { 0, 0, 'L', XTERMCC_INSLN, 1, -1, -1, -1 },
        { 0, 0, 'M', XTERMCC_DELLN, 1, -1, -1, -1 },
        { 0, 0, 'P', XTERMCC_DELCH, 1, -1, -1, -1 },
        { 0, 0, 'S', XTERMCC_SU, 1, -1, -1, -1 },
        // ?Pi;Pa;PvS not supported (Sixel/ReGIS)
        { 0, 0, 'T', XTERMCC_SD, 1, -1, -1, -1 },
        // Ps;Ps;Ps;Ps;PsT not supported (Initiate highlight mouse tracking)
        { 0, 0, 'X', ANSICSI_ECH, 1, -1, -1, -1 },
        { 0, 0, 'Z', ANSICSI_CBT, 1, -1, -1, -1 },
        // ` not supported (Character Position Absolute [column] (default = [row,1]) (HPA))
        // a not supported (Character Position Relative [columns] (default = [row,col+1]) (HPR))
        // b not supported (Repeat the preceding graphic character P s times (REP))
        { 0, 0, 'b', VT100CSI_REP, 1, -1, -1, -1 },
        { 0, 0, 'c', VT100CSI_DA, 0, -1, -1, -1 },
        { '>', 0, 'c', VT100CSI_DA2, 0, -1, -1, -1 },
        { 0, 0, 'd', ANSICSI_VPA, 1, -1, -1, -1 },
        { 0, 0, 'e', ANSICSI_VPR, 1, -1, -1, -1 },
        { 0, 0, 'f', VT100CSI_HVP, 1, 1, -1, -1 },
        { 0, 0, 'g', VT100CSI_TBC, 0, -1, -1, -1 },
        { 0, 0, 'h', VT100CSI_SM, -1, -1, -1, -1 },
        { '?', 0, 'h', VT100CSI_DECSET, -1, -1, -1, -1 },
        { 0, 0, 'i', ANSICSI_PRINT, 0, -1, -1, -1 },
        // ?i not supported (Media Copy (MC, DEC-specific))
        { 0, 0, 'l', VT100CSI_RM, -1, -1, -1, -1 },
        { '?', 0, 'l', VT100CSI_DECRST, -1, -1, -1, -1 },
        { 0, 0, 'm', VT100CSI_SGR, 0, -1, -1, -1 },
        { '>', 0, 'm', VT100CSI_SET_MODIFIERS, -1, -1, -1, -1 },
        { 0, 0, 'n', VT100CSI_DSR, 0, -1, -1, -1 },
        { '>', 0, 'n', VT100CSI_RESET_MODIFIERS, -1, -1, -1, -1 },
        { '?', 0, 'n', VT100CSI_DECDSR, 0, -1, -1, -1 },
        // >p not supported (Set resource value pointerMode. This is used by xterm to decide whether
        // to hide the pointer cursor as the user types.)
        { '!', 0, 'p', VT100CSI_DECSTR, -1, -1, -1, -1 },
        // $p not supported (Request ANSI mode (DECRQM))
        // ?$p not supported (Request DEC private mode (DECRQM))
        // "p not supported (Set conformance level (DECSCL))
        // q not supported (Load LEDs (DECLL))
        { 0, ' ', 'q', VT100CSI_DECSCUSR, 0, -1, -1, -1 },
        // "q not supported (Select character protection attribute (DECSCA))
        { 0, 0, 'r', VT100CSI_DECSTBM, -1, -1, -1, -1 },
        // $r not supported (Change Attributes in Rectangular Area (DECCARA))
        { 0, 0, 's', VT100CSI_DECSLRM_OR_ANSICSI_SCP, -1, -1, -1, -1 },
        // ?s not supported (Save DEC Private Mode Values)
        // t tested in -testWindowManipulationCodes
        // $t not supported (Reverse Attributes in Rectangular Area (DECRARA))
        // >t not supported (Set one or more features of the title modes)
        // SP t not supported (Set warning-bell volume (DECSWBV, VT520))
        { 0, 0, 'u', ANSICSI_RCP, -1, -1, -1, -1 },
        // SP u not supported (Set margin-bell volume (DECSMBV, VT520))
        // $v not supported (Copy Rectangular Area (DECCRA, VT400 and up))
        // 'w not supported (Enable Filter Rectangle (DECEFR), VT420 and up)
        // x not supported (Request Terminal Parameters (DECREQTPARM))
        // *x not supported (Select Attribute Change Extent (DECSACE))
        { 0, '*', 'y', VT100CSI_DECRQCRA, -1, -1, 1, -1 },
        // $x not supported (Fill Rectangular Area (DECFRA), VT420 and up)
        // 'z not supported (Enable Locator Reporting (DECELR))
        // $z not supported (Erase Rectangular Area (DECERA), VT400 and up)
        // '{ not supported (Select Locator Events (DECSLE))
        // ${ not supported (Selective Erase Rectangular Area (DECSERA), VT400 and up)
        // '| not supported (Request Locator Position (DECRQLP))
        // '} not supported (Insert P s Column(s) (default = 1) (DECIC), VT420 and up)
        // '~ not supported (Delete P s Column(s) (default = 1) (DECDC), VT420 and up)
        { 0, '#', '|', VT100CSI_XTREPORTSGR, 1, 1, 1, 1 }
    };

    const int n = sizeof(simpleCodes) / sizeof(*simpleCodes);
    for (int i = 0; i < n; i++) {
        int maxParams = 0;
        if (simpleCodes[i].p3 >= 0) {
            maxParams = 4;
        } else if (simpleCodes[i].p2 >= 0) {
            maxParams = 3;
        } else if (simpleCodes[i].p1 >= 0) {
            maxParams = 2;
        } else if (simpleCodes[i].p0 >= 0) {
            maxParams = 1;
        }

        NSMutableString *s = [NSMutableString stringWithFormat:@"%c[", VT100CC_ESC];
        if (simpleCodes[i].prefix) {
            [s appendFormat:@"%c", simpleCodes[i].prefix];
        }
        if (simpleCodes[i].intermediate) {
            [s appendFormat:@"%c", simpleCodes[i].intermediate];
        }
        if (simpleCodes[i].final) {
            [s appendFormat:@"%c", simpleCodes[i].final];
        }
        VT100Token *token = [self tokenForDataWithFormat:@"%@", s];
        XCTAssert(token->type == simpleCodes[i].tokenType);
        XCTAssert(token.csi->count == maxParams);
        if (maxParams >= 1) {
            XCTAssert(token.csi->count >= 1);
            XCTAssert(token.csi->p[0] == simpleCodes[i].p0);
        }
        if (maxParams >= 2) {
            XCTAssert(token.csi->count >= 2);
            XCTAssert(token.csi->p[1] == simpleCodes[i].p1);
        }
        if (maxParams >= 3) {
            XCTAssert(token.csi->count >= 3);
            XCTAssert(token.csi->p[2] == simpleCodes[i].p2);
        }
        if (maxParams >= 4) {
            XCTAssert(token.csi->count >= 4);
            XCTAssert(token.csi->p[3] == simpleCodes[i].p3);
        }
        XCTAssert(token.csi->p[maxParams] == -1);
    }
}

// This test is here to remind you to write a test when implementing support for a new CSI code.
- (void)testUnsupportedCodes {
    char *unsupported[] = {
        "I",
        "?J",
        "?K",
        "?1;1;1S",
        "1;1;1;1;1T",
        "`",
        "a",
        "?1i",
        ">0p",
        "1$p",
        "?1$p",
        "61;0\"p",
        "q",
        "\"q",
        "1;2;3;4;0$r",
        "?1s",
        "1;2;3;4;0$t",
        ">1;60t",
        "0 t",
        "1 u",
        "1;2;3;4;5;6;7;8$v",
        "1;2;3;4'w",
        "x",
        "0*x",
        "0;1;2;3;4$x",
        "0;0'z",
        "1;2;3;4$z",
        "'{",
        "1;2;3;4${",
        "'|",
        "'}",
        "'~",
    };
    const int n = sizeof(unsupported) / sizeof(*unsupported);
    for (int i = 0; i < n; i++) {
        VT100Token *token = [self tokenForDataWithFormat:@"%c[%s", VT100CC_ESC, unsupported[i]];
        XCTAssert(token->type == VT100_NOTSUPPORT);
    }
}

- (void)testWindowManipulationCodes {
    struct {
        int p0;
        VT100TerminalTokenType type;
    } codes[] = {
        { 1, XTERMCC_DEICONIFY },
        { 2, XTERMCC_ICONIFY },
        { 3, XTERMCC_WINDOWPOS },
        { 4, XTERMCC_WINDOWSIZE_PIXEL },
        { 5, XTERMCC_RAISE },
        { 6, XTERMCC_LOWER },
        // 7 is not supported (Refresh the window)
        { 8, XTERMCC_WINDOWSIZE },
        // 9 is not supported (Various maximize window actions)
        // 10 is not supported (Various full-screen actions)
        { 11, XTERMCC_REPORT_WIN_STATE },
        // 12 is not defined
        { 13, XTERMCC_REPORT_WIN_POS },
        { 14, XTERMCC_REPORT_WIN_PIX_SIZE },
        // 15, 16, and 17 are not defined
        { 18, XTERMCC_REPORT_WIN_SIZE },
        { 19, XTERMCC_REPORT_SCREEN_SIZE },
        { 20, XTERMCC_REPORT_ICON_TITLE },
        { 21, XTERMCC_REPORT_WIN_TITLE },
        { 22, XTERMCC_PUSH_TITLE },
        { 23, XTERMCC_POP_TITLE },
        // 24+ is not supported (resize to Ps lines - DECSLPP)
    };
    int n = sizeof(codes) / sizeof(*codes);
    for (int i = 0; i < n; i++) {
        VT100Token *token = [self tokenForDataWithFormat:@"%c[%dt", VT100CC_ESC, codes[i].p0];
        XCTAssert(token->type == codes[i].type);
        XCTAssert(token.csi->p[0] == codes[i].p0);
    }
}

@end
