//
//  VT100CSIParser.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "VT100CSIParser.h"

#define PACK_CSI_COMMAND(first, second) ((first << 8) | second)


@implementation VT100CSIParser

static int advanceAndEatControlChars(unsigned char **ppdata,
                                     int *pdatalen,
                                     CVector *incidentals)
{
    // return value represent "continuous" state.
    // If it is YES, current control sequence parsing process was not canceled.
    // If it is NO, current control sequence parsing process was canceled by CAN, SUB, or ESC.
    while (*pdatalen > 0) {
        ++*ppdata;
        --*pdatalen;
        switch (**ppdata) {
            case VT100CC_ENQ:
                // TODO: send answerback if it is needed
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
            case VT100CC_CAN:
            case VT100CC_SUB:
            case VT100CC_ESC:
            case VT100CC_DEL:
                CVectorAppend(incidentals, [VT100Token tokenForControlCharacter:**ppdata]);
                break;
            default:
                if (**ppdata >= 0x20)
                    return YES;
                break;
        }
    }
    return YES;
}

static int getCSIParam(unsigned char *datap,
                       int datalen,
                       CSIParam *param,
                       CVector *incidentals)
{
    int i;
    BOOL unrecognized = NO;
    unsigned char *orgp = datap;
    BOOL readNumericParameter = NO;
    size_t commandBytesCount = 0;
    
    NSCParameterAssert(datap != NULL);
    NSCParameterAssert(datalen >= 2);
    NSCParameterAssert(param != NULL);
    
    param->count = 0;
    
    // 2013/1/10 H.Saito
    //
    // The dispatching method for control functions becomes more simply and efficiently.
    // Now they are aggregated with VT100Token.csi.cmd parameter.
    //
    // cmd parameter consists of following bytes:
    // - Parameter Prefix Byte (if present, range: \x3a-\x3f)
    // - Intermediate Bytes (if present, range: \x20-\x2f)
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
    // With this case, packed cmd value is calculated as follows:
    //
    // (((0x3c << 8) | 0x24) << 8) | 0x70 = 3941488
    //
    // This value is always unique for each command functions.
    //
    const size_t COMMAND_BYTES_MAX = sizeof(param->cmd) / sizeof(*datap) + 1;
    param->cmd = 0;
    
    for (i = 0; i < VT100CSIPARAM_MAX; ++i ) {
        param->p[i] = -1;
    }
    
    NSCParameterAssert(*datap == ESC);
    datap++;
    datalen--;
    
    NSCParameterAssert(*datap == '[');
    
    if (!advanceAndEatControlChars(&datap, &datalen, incidentals)) {
        goto cancel;
    }
    
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
    //          In DEC VT-series, '?' prefix is commonly used by such as DEC specific private modes.
    //          "CSI > Ps c" is interpreted as the request of Secondary Device attributes(DA2).
    //          In some highter version of VT treats "CSI = Ps c" as the request of Tirnary Device attributes(DA3).
    //          The terminal emulator Tera Term and RLogin use '<'-prefixed extensions for IME support.
    //          "CSI < Ps t" means "change the IME open/close state".
    //          ref: supported control functions by Tera Term
    //          http://ttssh2.sourceforge.jp/manual/en/about/ctrlseq.html
    //
    if (datalen > 0) {
        switch (*datap) {
            case '<':
            case '=':
            case '>':
            case '?':
                param->cmd = *datap;
                if (!advanceAndEatControlChars(&datap, &datalen, incidentals))
                    goto cancel;
                break;
            default:
                break;
        }
    }
    
    //     2. parse parameters
    //        Typically, it consists of '0'-'9' or ';'. If there are sub parameters, they'll
    //        be colon-delimited. <parameter>:<sub 1>:<sub 2>:<sub 3>...:<sub N>
    //        '<', '=', '>', '?' should be ignored, but if current sequence contains them,
    //        this sequence should be mark as unrecognized.
    BOOL isSub = NO;
    while (datalen > 0 && *datap >= 0x30 && *datap <= 0x3f) {
        switch (*datap) {
            case '0':
            case '1':
            case '2':
            case '3':
            case '4':
            case '5':
            case '6':
            case '7':
            case '8':
            case '9':
            {
                int n = 0;
                while (datalen > 0 && *datap >= '0' && *datap <= '9') {
                    if (n > (INT_MAX - 10) / 10) {
                        unrecognized = YES;
                    }
                    n = n * 10 + *datap - '0';
                    if (!advanceAndEatControlChars(&datap, &datalen, incidentals)) {
                        goto cancel;
                    }
                }
                
                if (isSub) {
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
                
                if (!advanceAndEatControlChars(&datap, &datalen, incidentals)) {
                    goto cancel;
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
                if (!advanceAndEatControlChars(&datap, &datalen, incidentals)) {
                    goto cancel;
                }
                break;
                
            default:
                // '<', '=', '>', or '?'
                unrecognized = YES;
                if (!advanceAndEatControlChars(&datap, &datalen, incidentals)) {
                    goto cancel;
                }
                break;
        }
    }
    
    // Now we parse intermediate bytes (ECMA-48, 5.4 - (c))
    //
    // CSI P...P I...I F
    //           ^
    // Intermediate Bytes, if present, consist of bit combinations from 02/00 to 02/15.
    //
    while (datalen > 0 && *datap >= 0x20 && *datap <= 0x2f) {
        if (commandBytesCount < COMMAND_BYTES_MAX) {
            param->cmd = PACK_CSI_COMMAND(param->cmd, *datap);
        } else {
            unrecognized = YES;
        }
        commandBytesCount++;
        if (!advanceAndEatControlChars(&datap, &datalen, incidentals)) {
            goto cancel;
        }
    }
    
    // compatibility HACK:
    //
    // CSI P...P I...I (G...G) F
    //                  ^
    // xterm allows "garbage bytes" before final byte.
    // rxvt, urxvt, PuTTY, MinTTY, mlterm, TeraTerm also does so.
    // We skip them, too.
    //
    while (datalen > 0) {
        if (*datap >= 0x40 && *datap <= 0x7e) { // final byte
            break;
        } else {
            if (*datap > 0x1f && *datap != 0x7f) {
                // if "garbage bytes" contains non-control character,
                // mark current sequence as "unrecognized".
                unrecognized = YES;
            }
            if (!advanceAndEatControlChars(&datap, &datalen, incidentals)) {
                goto cancel;
            }
        }
    }
    
    // Now we parse final byte (ECMA-48, 5.4 - (d))
    //
    // CSI P...P I...I F
    //                 ^
    // Final Byte consists of a bit combination from 04/00 to 07/14.
    //
    if (datalen > 0) {
        if (commandBytesCount < COMMAND_BYTES_MAX) {
            param->cmd = PACK_CSI_COMMAND(param->cmd, *datap);
        }
        datap++;
        datalen--;
        
        if (unrecognized) {
            param->cmd = 0xff;
        }
    } else {
        param->cmd = 0x00;
    }
    return datap - orgp;
    
cancel:
    param->cmd = 0xff;
    return datap - orgp;
}

+ (void)decodeBytes:(unsigned char *)datap
             length:(int)datalen
          bytesUsed:(int *)rmlen
        incidentals:(CVector *)incidentals
              token:(VT100Token *)result
{
    CSIParam *param = result.csi;
    int paramlen;
    int i;
    
    paramlen = getCSIParam(datap, datalen, param, incidentals);
    result->type = VT100_WAIT;
    
    // Check for unkown
    if (param->cmd == 0xff) {
        result->type = VT100_UNKNOWNCHAR;
        *rmlen = paramlen;
    } else if (paramlen > 0 && param->cmd > 0) {
        // process
        switch (param->cmd) {
            case 'D':       // Cursor Backward
                result->type = VT100CSI_CUB;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
                
            case 'B':       // Cursor Down
                result->type = VT100CSI_CUD;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
                
            case 'C':       // Cursor Forward
                result->type = VT100CSI_CUF;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
                
            case 'A':       // Cursor Up
                result->type = VT100CSI_CUU;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
                
            case 'H':
                result->type = VT100CSI_CUP;
                SET_PARAM_DEFAULT(param, 0, 1);
                SET_PARAM_DEFAULT(param, 1, 1);
                break;
                
            case 'c':
                result->type = VT100CSI_DA;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;
                
            case PACK_CSI_COMMAND('>', 'c'):
                result->type = VT100CSI_DA2;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;
                
            case 'q':
                result->type = VT100CSI_DECLL;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;
                
            case 'x':
                if (param->count == 1)
                    result->type = VT100CSI_DECREQTPARM;
                else
                    result->type = VT100CSI_DECREPTPARM;
                break;
                
            case 'r':
                result->type = VT100CSI_DECSTBM;
                SET_PARAM_DEFAULT(param, 0, 1);
                SET_PARAM_DEFAULT(param, 1, 0);
                break;
                
            case 'y':
                if (param->count == 2)
                    result->type = VT100CSI_DECTST;
                else
                {
                    result->type = VT100_NOTSUPPORT;
                }
                break;
                
            case 'n':
                result->type = VT100CSI_DSR;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;
                
            case PACK_CSI_COMMAND('?', 'n'):
                result->type = VT100CSI_DECDSR;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;
                
            case 'J':
                result->type = VT100CSI_ED;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;
                
            case 'K':
                result->type = VT100CSI_EL;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;
                
            case 'f':
                result->type = VT100CSI_HVP;
                SET_PARAM_DEFAULT(param, 0, 1);
                SET_PARAM_DEFAULT(param, 1, 1);
                break;
                
            case 'l':
                result->type = VT100CSI_RM;
                break;
                
            case PACK_CSI_COMMAND('>', 'm'):
                result->type = VT100CSI_SET_MODIFIERS;
                break;
                
            case PACK_CSI_COMMAND('>', 'n'):
                result->type = VT100CSI_RESET_MODIFIERS;
                break;
                
            case 'm':
                result->type = VT100CSI_SGR;
                for (i = 0; i < param->count; ++i) {
                    SET_PARAM_DEFAULT(param, i, 0);
                }
                break;
                
            case 'h':
                result->type = VT100CSI_SM;
                break;
                
            case 'g':
                result->type = VT100CSI_TBC;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;
                
            case PACK_CSI_COMMAND(' ', 'q'):
                result->type = VT100CSI_DECSCUSR;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;
                
            case PACK_CSI_COMMAND('!', 'p'):
                result->type = VT100CSI_DECSTR;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;
                
                // these are xterm controls
            case '@':
                result->type = XTERMCC_INSBLNK;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
            case 'L':
                result->type = XTERMCC_INSLN;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
            case 'P':
                result->type = XTERMCC_DELCH;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
            case 'M':
                result->type = XTERMCC_DELLN;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
            case 't':
                switch (param->p[0]) {
                    case 8:
                        result->type = XTERMCC_WINDOWSIZE;
                        SET_PARAM_DEFAULT(param, 1, 0);     // columns or Y
                        SET_PARAM_DEFAULT(param, 2, 0);     // rows or X
                        break;
                    case 3:
                        result->type = XTERMCC_WINDOWPOS;
                        SET_PARAM_DEFAULT(param, 1, 0);     // columns or Y
                        SET_PARAM_DEFAULT(param, 2, 0);     // rows or X
                        break;
                    case 4:
                        result->type = XTERMCC_WINDOWSIZE_PIXEL;
                        break;
                    case 2:
                        result->type = XTERMCC_ICONIFY;
                        break;
                    case 1:
                        result->type = XTERMCC_DEICONIFY;
                        break;
                    case 5:
                        result->type = XTERMCC_RAISE;
                        break;
                    case 6:
                        result->type = XTERMCC_LOWER;
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
                    default:
                        result->type = VT100_NOTSUPPORT;
                        break;
                }
                break;
            case 'S':
                result->type = XTERMCC_SU;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
            case 'T':
                if (param->count < 2) {
                    result->type = XTERMCC_SD;
                    SET_PARAM_DEFAULT(param, 0, 1);
                }
                else
                    result->type = VT100_NOTSUPPORT;
                break;
                
                // ANSI
            case 'Z':
                result->type = ANSICSI_CBT;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
            case 'G':
                result->type = ANSICSI_CHA;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
            case 'd':
                result->type = ANSICSI_VPA;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
            case 'e':
                result->type = ANSICSI_VPR;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
            case 'X':
                result->type = ANSICSI_ECH;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
            case 'i':
                result->type = ANSICSI_PRINT;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;
            case 's':
                // TODO: Test disambiguation
                result->type = VT100CSI_DECSLRM_OR_ANSICSI_SCP;
                break;
            case 'u':
                result->type = ANSICSI_RCP;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;
            case PACK_CSI_COMMAND('?', 'h'):       // Dec private mode set
                result->type = VT100CSI_DECSET;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;
            case PACK_CSI_COMMAND('?', 'l'):       // Dec private mode reset
                result->type = VT100CSI_DECRST;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;
            default:
                result->type = VT100_NOTSUPPORT;
                break;
                
        }
        
        *rmlen = paramlen;
    }
}

@end
