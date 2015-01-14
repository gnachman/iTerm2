//
//  VT100CSIParser.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "VT100CSIParser.h"

// Functions to modify the packed command in CSIParam.cmd.
static int32_t SetFinalByteInPackedCommand(int32_t command, unsigned char c) {
    return (command & 0xffffff00) | (c << 0);
}

static int32_t SetIntermediateByteInPackedCommand(int32_t command, unsigned char c) {
    return (command & 0xffff00ff) | (c << 8);
}

static int32_t SetPrefixByteInPackedCommand(int32_t command, unsigned char c) {
    return (command & 0xff00ffff) | (c << 16);
}

// A macro is used here so it can be a value in a case statement.
// Note that only a single intermediate byte is supported. I don't know of any CSI codes that use
// more than one. The integer packing format is very efficient, so it's worth the limitation.
#define PACKED_CSI_COMMAND(prefix, intermediate, final) \
    (((prefix) << 16) | ((intermediate) << 8) | (final))

// Packed command value for an unparseable code.
#define INVALID_CSI_CMD PACKED_CSI_COMMAND(0xff, 0xff, 0xff)

// Packed command value for more-data-need.
#define INCOMPLETE_CSI_CMD PACKED_CSI_COMMAND(0, 0, 0)

@implementation VT100CSIParser

// Advances past one character and then any following control characters.
// If a control character is found that cancels a CSI sequence,
// then NO is returned. If all is well, YES is returned and parsing can
// continue. Non-canceling control characters are appended to |incidentals|
static BOOL AdvanceAndEatControlChars(iTermParserContext *context,
                                      CVector *incidentals) {
    // First, advance if possible.
    iTermParserTryAdvance(context);

    // Now eat control characters.
    unsigned char c;
    while (iTermParserTryPeek(context, &c)) {
        switch (c) {
            case VT100CC_ENQ:
                // TODO: This should respond with a user-definable "answerback" string, which
                // defaults to the empty string.
                break;
            case VT100CC_BEL:
            case VT100CC_BS:
            case VT100CC_HT:
            case VT100CC_LF:
            case VT100CC_VT:
            case VT100CC_FF:
            case VT100CC_CR:
            case VT100CC_SO:
            case VT100CC_SI:
            case VT100CC_DC1:
            case VT100CC_DC3:
            case VT100CC_DEL:
                CVectorAppend(incidentals, [VT100Token tokenForControlCharacter:c]);
                break;

            case VT100CC_CAN:
            case VT100CC_SUB:
            case VT100CC_ESC:
                return NO;

            default:
                if (c >= 0x20) {
                    return YES;
                }
                break;
        }
        iTermParserAdvance(context);
    }
    return YES;
}

static void CSIParamInitialize(CSIParam *param) {
    param->cmd = INCOMPLETE_CSI_CMD;
    param->count = 0;

    for (int i = 0; i < VT100CSIPARAM_MAX; ++i ) {
        param->p[i] = -1;
    }
}

static BOOL ParseCSIPrologue(iTermParserContext *context, CVector *incidentals) {
    iTermParserConsumeOrDie(context, VT100CC_ESC);
    assert(iTermParserCanAdvance(context));
    assert(iTermParserPeek(context) == '[');
    return AdvanceAndEatControlChars(context, incidentals);
}

static BOOL ParseCSIPrefix(iTermParserContext *context, CVector *incidentals, CSIParam *param) {
    // Now we parse Parameter Bytes (ECMA-48, 5.4 - (b))
    //
    // CSI P...P I...I F
    //     ^
    //
    // Parameter Bytes, which, if present, consist of bit combinations from \x30 to \x3f;
    //
    //     1. In DEC VT-series and some derived emulators,
    //        the first 1 byte of P-bytes is sometimes treated as prefix.
    //
    //        ECMA-48, 5.4.2 - (d) says that;
    //
    //          > Bit combinations 03/12 to 03/15 are reserved for future
    //          > standardization except when used as the first bit combination
    //          > of the parameter string.
    //
    //          note: ECMA-48 is to write ascii codes as (decimal top nibble)/(decimal lower nibble),
    //                and that a value like 03/15 = 0x3f (see ECMA-48, 4.1).
    //
    //        This description suggests that if the first byte of parameter bytes is one of
    //        '<', '=', '>', '?' (\x3c-\x3f), it's well-formed and could be considered
    //        as private CSI extention.
    //
    //        Example:
    //
    //          In the DEC VT-series, the '?' prefix is used, such as by DEC-specific private modes.
    //          "CSI > Ps c" is interpreted as a Secondary Device attributes (DA2) request.
    //          Higher versions of the DEC VT treat "CSI = Ps c" as a Tertiary Device attributes
    //          (DA3) request. Tera Term and RLogin use '<'-prefixed extensions for IME support.
    //          For example, "CSI < Ps t" means "change the IME open/close state".
    //          http://ttssh2.sourceforge.jp/manual/en/about/ctrlseq.html
    //
    if (iTermParserCanAdvance(context)) {
        unsigned char c = iTermParserPeek(context);
        switch (c) {
            case '<':
            case '=':
            case '>':
            case '?':
                param->cmd = SetPrefixByteInPackedCommand(param->cmd, c);
                if (!AdvanceAndEatControlChars(context, incidentals)) {
                    return NO;
                }
                break;

            default:
                break;
        }
    }
    return YES;
}

static BOOL ParseCSIParameters(iTermParserContext *context,
                               CVector *incidentals,
                               CSIParam *param,
                               BOOL *unrecognized) {
    //     2. parse parameters
    //        Typically, it consists of '0'-'9' or ';'. If there are sub parameters, they'll
    //        be colon-delimited. <parameter>:<sub 1>:<sub 2>:<sub 3>...:<sub N>
    //        '<', '=', '>', '?' should be ignored, but if current sequence contains them,
    //        this sequence should be mark as unrecognized.
    BOOL isSub = NO;
    BOOL readNumericParameter = NO;
    unsigned char c;
    while (iTermParserTryPeek(context, &c) && c >= 0x30 && c <= 0x3f) {
        switch (c) {
            case '0':
            case '1':
            case '2':
            case '3':
            case '4':
            case '5':
            case '6':
            case '7':
            case '8':
            case '9': {
                int n = 0;
                while (iTermParserTryPeek(context, &c) && isdigit(c)) {
                    if (n > (INT_MAX - 10) / 10) {
                        *unrecognized = YES;
                    }
                    n = n * 10 + (c - '0');
                    if (!AdvanceAndEatControlChars(context, incidentals)) {
                        return NO;
                    }
                }
                
                if (isSub && param->count > 0) {
                    // This implementation is not really well aligned with the spec. In ECMA-48
                    // section 5.4, the format of a CSI code is described. The parameter string,
                    // which follows CSI, is a semicolon-delimited list of parameter substrings
                    // A parameter substring is a sequence of digits with colon separators.
                    // The data structure we use treats each parameter string up to the first
                    // colon (if any) as the parameter, and parts after the first colon as
                    // sub-parameters. That doesn't really make sense if a paramater string
                    // starts with a colon, which is allowed but not defined in the spec.
                    // Since that never should happen in practice, we'll just ignore a parameter
                    // string that starts with a colon.
                    const int paramNum = param->count - 1;
                    assert(paramNum >= 0 && paramNum < VT100CSIPARAM_MAX);
                    int subParamNum = param->subCount[paramNum];
                    if (subParamNum < VT100CSISUBPARAM_MAX) {
                        param->sub[paramNum][subParamNum] = n;
                        param->subCount[paramNum]++;
                    }
                } else if (param->count < VT100CSIPARAM_MAX) {
                    param->p[param->count] = n;
                    // increment the parameter count
                    param->count++;
                }
                
                // set the numeric parameter flag
                readNumericParameter = YES;
                
                break;
            }
                
            case ';':
                // If we got an implied (blank) parameter, increment the parameter count again
                if (param->count < VT100CSIPARAM_MAX && readNumericParameter == NO) {
                    param->count++;
                }
                // reset the parameter flag
                readNumericParameter = NO;
                
                if (!AdvanceAndEatControlChars(context, incidentals)) {
                    return NO;
                }
                break;
                
            case ':':
                // 2013/1/10 H. Saito
                // TODO: Now colon separator(":") used in SGR sequence by few terminals
                // (xterm #282, TeraTerm, RLogin, mlterm, tanasinn).
                // ECMA-48 suggests it may be used as a separator in a parameter sub-string (5.4.2 - (b)),
                // but it seems the usage of ":" around SGR is confused a little.
                //
                // 1. Konsole's 3-byte color mode style:
                //    CSI 38 ; 2 ; R ; G ; B m (Konsole, xterm, TeraTerm)
                //
                // 2. ITU-T T-416 like style:
                //    CSI 38 ; 2 : R : G : B m (xterm, TeraTerm, RLogin)
                //    CSI 38 ; 2 ; R : G : B m (xterm, TeraTerm, RLogin)
                //    CSI 38 ; 2 ; R ; G : B m (xterm, RLogin)
                //    CSI 38 ; 2 ; R : G ; B m (xterm, TeraTerm)
                //    CSI 38 : 2 : R : G : B m (xterm, TeraTerm, RLogin)
                //
                // (* It seems mlterm/tanasinn don't distinguish ":" from ";")
                //
                // In other case, yaft proposes GWREPT(glyph width report, OSC 8900)
                //
                //   > OSC 8900 ; Ps ; Pt ; width : from : to ; width : from : to ; ... ST
                //   http://uobikiemukot.github.io/yaft/glyph_width_report.html
                //
                // In this usage, ":" are certainly treated as sub-parameter separators.
                isSub = YES;
                if (!AdvanceAndEatControlChars(context, incidentals)) {
                    return NO;
                }
                break;
                
            default:
                // '<', '=', '>', or '?'
                *unrecognized = YES;
                if (!AdvanceAndEatControlChars(context, incidentals)) {
                    return NO;
                }
                break;
        }
    }

    return YES;
}

static BOOL ParseCSIIntermediate(iTermParserContext *context,
                                 CVector *incidentals,
                                 CSIParam *param) {
    // Now we parse intermediate bytes (ECMA-48, 5.4 - (c))
    //
    // CSI P...P I...I F
    //           ^
    // Intermediate Bytes, if present, consist of bit combinations from 02/00 to 02/15.
    //
    unsigned char c;
    while (iTermParserTryPeek(context, &c) && c >= 0x20 && c <= 0x2f) {
        param->cmd = SetIntermediateByteInPackedCommand(param->cmd, c);
        if (!AdvanceAndEatControlChars(context, incidentals)) {
            return NO;
        }
    }
    return YES;
}

static BOOL ParseCSIGarbage(iTermParserContext *context, CVector *incidentals, BOOL *unrecognized) {
    // compatibility HACK:
    //
    // CSI P...P I...I (G...G) F
    //                  ^
    // xterm allows "garbage bytes" before final byte.
    // rxvt, urxvt, PuTTY, MinTTY, mlterm, TeraTerm also do.
    // We skip them, too.
    unsigned char c;
    while (iTermParserTryPeek(context, &c)) {
        if (c >= 0x40 && c <= 0x7e) { // final byte
            break;
        } else {
            if (c > 0x1f && c != 0x7f) {
                // if "garbage bytes" contains non-control character,
                // mark current sequence as "unrecognized". The only way to get here is to have
                // a character in the range [0x20,0x3f] occur after an 0x7f.
                *unrecognized = YES;
            }
            if (!AdvanceAndEatControlChars(context, incidentals)) {
                return NO;
            }
        }
    }
    return YES;
}

static void ParseCSIFinal(iTermParserContext *context, CSIParam *param, BOOL *unrecognized) {
    // Now we parse final byte (ECMA-48, 5.4 - (d))
    //
    // CSI P...P I...I F
    //                 ^
    // Final Byte consists of a bit combination from 04/00 to 07/14.
    unsigned char c;
    if (iTermParserTryConsume(context, &c)) {
        if (c >= 0x40 && c < 0x7f && !*unrecognized) {
            param->cmd = SetFinalByteInPackedCommand(param->cmd, c);
        } else {
            param->cmd = INVALID_CSI_CMD;
        }
    } else {
        param->cmd = INCOMPLETE_CSI_CMD;
    }
}

static void ParseCSISequence(iTermParserContext *context, CSIParam *param, CVector *incidentals) {
    // A CSI sequence consists of a prefix byte, zero or more parameters (optionally with sub-
    // parameters), zero or more intermediate bytes, and a final byte.
    //
    // The prefix, intermediate, and final bytes are packed into an integer and stored in
    // param->cmd. The parameters and sub-parameters are stored in param->p and param->sub.
    //
    // - Parameter Prefix Byte (if present, range: \x3a-\x3f)
    // - Intermediate Bytes (actually, just the last one) (if present, range: \x20-\x2f)
    // - Final byte (range: \x40-\x3e)
    //
    // Example: DECRQM sequence
    // http://www.vt100.net/docs/vt510-rm/DECRQM
    //
    // ESC [ ? 3 6 $ p
    //
    // it can be parsed as...
    //
    // Parameter Prefix Byte --> '?' (\x3c)
    // Parameters            --> [ 36 ]
    // Intermediate Bytes    --> '$' (\x24)
    // Final Byte            --> 'p' (\x70)
    //
    // The packed cmd value would be:
    //
    // ((prefix << 16) | (intermediate << 8) | final) = 0x3c2470
    //
    // Each (prefix, intermediate, final) 3-tuple has a unique packed representation.

    BOOL unrecognized = NO;

    CSIParamInitialize(param);

    if (ParseCSIPrologue(context, incidentals) &&
        ParseCSIPrefix(context, incidentals, param) &&
        ParseCSIParameters(context, incidentals, param, &unrecognized) &&
        ParseCSIIntermediate(context, incidentals, param) &&
        ParseCSIGarbage(context, incidentals, &unrecognized)) {
        ParseCSIFinal(context, param, &unrecognized);
    } else {
        param->cmd = INVALID_CSI_CMD;
    }
}

static void SetCSITypeAndDefaultParameters(CSIParam *param, VT100Token *result) {
    switch (param->cmd) {
        case INVALID_CSI_CMD:
            result->type = VT100_UNKNOWNCHAR;
            break;

        case INCOMPLETE_CSI_CMD:
            result->type = VT100_WAIT;
            break;

        case 'D':       // Cursor Backward
            result->type = VT100CSI_CUB;
            iTermParserSetCSIParameterIfDefault(param, 0, 1);
            break;

        case 'B':       // Cursor Down
            result->type = VT100CSI_CUD;
            iTermParserSetCSIParameterIfDefault(param, 0, 1);
            break;

        case 'C':       // Cursor Forward
            result->type = VT100CSI_CUF;
            iTermParserSetCSIParameterIfDefault(param, 0, 1);
            break;

        case 'A':       // Cursor Up
            result->type = VT100CSI_CUU;
            iTermParserSetCSIParameterIfDefault(param, 0, 1);
            break;

        case 'E':       // Cursor Next Line
            result->type = VT100CSI_CNL;
            iTermParserSetCSIParameterIfDefault(param, 0, 1);
            break;

        case 'F':       // Cursor Preceding Line
            result->type = VT100CSI_CPL;
            iTermParserSetCSIParameterIfDefault(param, 0, 1);
            break;

        case 'H':
            result->type = VT100CSI_CUP;
            iTermParserSetCSIParameterIfDefault(param, 0, 1);
            iTermParserSetCSIParameterIfDefault(param, 1, 1);
            break;

        case 'c':
            result->type = VT100CSI_DA;
            iTermParserSetCSIParameterIfDefault(param, 0, 0);
            break;

        case PACKED_CSI_COMMAND('>', 0, 'c'):
            result->type = VT100CSI_DA2;
            iTermParserSetCSIParameterIfDefault(param, 0, 0);
            break;

        case 'r':
            result->type = VT100CSI_DECSTBM;
            break;

        case 'n':
            result->type = VT100CSI_DSR;
            iTermParserSetCSIParameterIfDefault(param, 0, 0);
            break;

        case PACKED_CSI_COMMAND('?', 0, 'n'):
            result->type = VT100CSI_DECDSR;
            iTermParserSetCSIParameterIfDefault(param, 0, 0);
            break;

        case 'J':
            result->type = VT100CSI_ED;
            iTermParserSetCSIParameterIfDefault(param, 0, 0);
            break;

        case 'K':
            result->type = VT100CSI_EL;
            iTermParserSetCSIParameterIfDefault(param, 0, 0);
            break;

        case 'f':
            result->type = VT100CSI_HVP;
            iTermParserSetCSIParameterIfDefault(param, 0, 1);
            iTermParserSetCSIParameterIfDefault(param, 1, 1);
            break;

        case 'l':
            result->type = VT100CSI_RM;
            break;

        case PACKED_CSI_COMMAND('>', 0, 'm'):
            result->type = VT100CSI_SET_MODIFIERS;
            break;

        case PACKED_CSI_COMMAND('>', 0, 'n'):
            result->type = VT100CSI_RESET_MODIFIERS;
            break;

        case 'm':
            result->type = VT100CSI_SGR;
            // TODO: Test codes like CSI 1 ; ; m
            for (int i = 0; i < MAX(1, param->count); ++i) {
                iTermParserSetCSIParameterIfDefault(param, i, 0);
            }
            break;

        case 'h':
            result->type = VT100CSI_SM;
            break;

        case 'g':
            result->type = VT100CSI_TBC;
            iTermParserSetCSIParameterIfDefault(param, 0, 0);
            break;

        case PACKED_CSI_COMMAND(0, ' ', 'q'):
            result->type = VT100CSI_DECSCUSR;
            iTermParserSetCSIParameterIfDefault(param, 0, 0);
            break;

        case PACKED_CSI_COMMAND(0, '!', 'p'):
            result->type = VT100CSI_DECSTR;
            break;

        case PACKED_CSI_COMMAND(0, '*', 'y'):
            result->type = VT100CSI_DECRQCRA;
            iTermParserSetCSIParameterIfDefault(param, 2, 1);
            break;

        case '@':
            result->type = VT100CSI_ICH;
            iTermParserSetCSIParameterIfDefault(param, 0, 1);
            break;
        case 'L':
            result->type = XTERMCC_INSLN;
            iTermParserSetCSIParameterIfDefault(param, 0, 1);
            break;
        case 'P':
            result->type = XTERMCC_DELCH;
            iTermParserSetCSIParameterIfDefault(param, 0, 1);
            break;
        case 'M':
            result->type = XTERMCC_DELLN;
            iTermParserSetCSIParameterIfDefault(param, 0, 1);
            break;
        case 't':
            switch (param->p[0]) {
                case 1:
                    result->type = XTERMCC_DEICONIFY;
                    break;
                case 2:
                    result->type = XTERMCC_ICONIFY;
                    break;
                case 3:
                    result->type = XTERMCC_WINDOWPOS;
                    iTermParserSetCSIParameterIfDefault(param, 1, 0);  // columns or Y
                    iTermParserSetCSIParameterIfDefault(param, 2, 0);  // rows or X
                    break;
                case 4:
                    result->type = XTERMCC_WINDOWSIZE_PIXEL;
                    break;
                case 5:
                    result->type = XTERMCC_RAISE;
                    break;
                case 6:
                    result->type = XTERMCC_LOWER;
                    break;
                case 8:
                    result->type = XTERMCC_WINDOWSIZE;
                    break;
                case 11:
                    result->type = XTERMCC_REPORT_WIN_STATE;
                    break;
                case 13:
                    result->type = XTERMCC_REPORT_WIN_POS;
                    break;
                case 14:
                    result->type = XTERMCC_REPORT_WIN_PIX_SIZE;
                    break;
                case 18:
                    result->type = XTERMCC_REPORT_WIN_SIZE;
                    break;
                case 19:
                    result->type = XTERMCC_REPORT_SCREEN_SIZE;
                    break;
                case 20:
                    result->type = XTERMCC_REPORT_ICON_TITLE;
                    break;
                case 21:
                    result->type = XTERMCC_REPORT_WIN_TITLE;
                    break;
                case 22:
                    result->type = XTERMCC_PUSH_TITLE;
                    break;
                case 23:
                    result->type = XTERMCC_POP_TITLE;
                    break;
                default:
                    result->type = VT100_NOTSUPPORT;
                    break;
            }
            break;
        case 'S':
            result->type = XTERMCC_SU;
            iTermParserSetCSIParameterIfDefault(param, 0, 1);
            break;
        case 'T':
            if (param->count < 2) {
                result->type = XTERMCC_SD;
                iTermParserSetCSIParameterIfDefault(param, 0, 1);
            } else {
                result->type = VT100_NOTSUPPORT;
            }
            break;

            // ANSI:
        case 'Z':
            result->type = ANSICSI_CBT;
            iTermParserSetCSIParameterIfDefault(param, 0, 1);
            break;
        case 'G':
            result->type = ANSICSI_CHA;
            iTermParserSetCSIParameterIfDefault(param, 0, 1);
            break;
        case 'd':
            result->type = ANSICSI_VPA;
            iTermParserSetCSIParameterIfDefault(param, 0, 1);
            break;
        case 'e':
            result->type = ANSICSI_VPR;
            iTermParserSetCSIParameterIfDefault(param, 0, 1);
            break;
        case 'X':
            result->type = ANSICSI_ECH;
            iTermParserSetCSIParameterIfDefault(param, 0, 1);
            break;
        case 'i':
            result->type = ANSICSI_PRINT;
            iTermParserSetCSIParameterIfDefault(param, 0, 0);
            break;
        case 's':
            result->type = VT100CSI_DECSLRM_OR_ANSICSI_SCP;
            break;
        case 'u':
            result->type = ANSICSI_RCP;
            break;
        case PACKED_CSI_COMMAND('?', 0, 'h'):       // DEC private mode set
            result->type = VT100CSI_DECSET;
            break;
        case PACKED_CSI_COMMAND('?', 0, 'l'):       // DEC private mode reset
            result->type = VT100CSI_DECRST;
            break;
        default:
            result->type = VT100_NOTSUPPORT;
            break;
            
    }
}

+ (void)decodeFromContext:(iTermParserContext *)context
              incidentals:(CVector *)incidentals
                    token:(VT100Token *)result {
    CSIParam *param = result.csi;
    iTermParserContext savedContext = *context;

    ParseCSISequence(context, param, incidentals);
    SetCSITypeAndDefaultParameters(param, result);
    if (result->type == VT100_WAIT) {
        *context = savedContext;
    }
}

@end
