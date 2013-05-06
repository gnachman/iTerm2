// -*- mode:objc -*-
// $Id: VT100Terminal.m,v 1.136 2008-10-21 05:43:52 yfabian Exp $
//
/*
 **  VT100Terminal.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **      Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: Implements the model class VT100 terminal.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import "VT100Terminal.h"
#import "PTYSession.h"
#import "VT100Screen.h"
#import "NSStringITerm.h"
#import "iTermApplicationDelegate.h"
#import "ITAddressBookMgr.h"
#import "PTYTab.h"
#import "PseudoTerminal.h"
#import "WindowControllerInterface.h"
#include <term.h>
#include <wchar.h>

#define DEBUG_ALLOC 0
#define LOG_UNKNOWN 0
#define STANDARD_STREAM_SIZE 100000
#define MAX_BUFFER_LENGTH 1024

@implementation VT100Terminal

#define iscontrol(c)  ((c) <= 0x1f)

/*
 Traditional Chinese (Big5)
 1st   0xa1-0xfe
 2nd   0x40-0x7e || 0xa1-0xfe

 Simplifed Chinese (EUC_CN)
 1st   0x81-0xfe
 2nd   0x40-0x7e || 0x80-0xfe
 */
#define iseuccn(c)   ((c) >= 0x81 && (c) <= 0xfe)
#define isbig5(c)    ((c) >= 0xa1 && (c) <= 0xfe)
#define issjiskanji(c)  (((c) >= 0x81 && (c) <= 0x9f) ||  \
                         ((c) >= 0xe0 && (c) <= 0xef))
#define iseuckr(c)   ((c) >= 0xa1 && (c) <= 0xfe)

#define isGBEncoding(e)     ((e)==0x80000019||(e)==0x80000421|| \
                             (e)==0x80000631||(e)==0x80000632|| \
                             (e)==0x80000930)
#define isBig5Encoding(e)   ((e)==0x80000002||(e)==0x80000423|| \
                             (e)==0x80000931||(e)==0x80000a03|| \
                             (e)==0x80000a06)
#define isJPEncoding(e)     ((e)==0x80000001||(e)==0x8||(e)==0x15)
#define isSJISEncoding(e)   ((e)==0x80000628||(e)==0x80000a01)
#define isKREncoding(e)     ((e)==0x80000422||(e)==0x80000003|| \
                             (e)==0x80000840||(e)==0x80000940)
#define ESC  0x1b
#define DEL  0x7f

#define CURSOR_SET_DOWN      "\033OB"
#define CURSOR_SET_UP        "\033OA"
#define CURSOR_SET_RIGHT     "\033OC"
#define CURSOR_SET_LEFT      "\033OD"
#define CURSOR_SET_HOME      "\033OH"
#define CURSOR_SET_END       "\033OF"
#define CURSOR_RESET_DOWN    "\033[B"
#define CURSOR_RESET_UP      "\033[A"
#define CURSOR_RESET_RIGHT   "\033[C"
#define CURSOR_RESET_LEFT    "\033[D"
#define CURSOR_RESET_HOME    "\033[H"
#define CURSOR_RESET_END     "\033[F"
#define CURSOR_MOD_DOWN      "\033[1;%dB"
#define CURSOR_MOD_UP        "\033[1;%dA"
#define CURSOR_MOD_RIGHT     "\033[1;%dC"
#define CURSOR_MOD_LEFT      "\033[1;%dD"
#define CURSOR_MOD_HOME      "\033[1;%dH"
#define CURSOR_MOD_END       "\033[1;%dF"

#define KEY_INSERT           "\033[2~"
#define KEY_PAGE_UP          "\033[5~"
#define KEY_PAGE_DOWN        "\033[6~"
#define KEY_DEL              "\033[3~"
#define KEY_BACKSPACE        "\010"

#define ALT_KP_0        "\033Op"
#define ALT_KP_1        "\033Oq"
#define ALT_KP_2        "\033Or"
#define ALT_KP_3        "\033Os"
#define ALT_KP_4        "\033Ot"
#define ALT_KP_5        "\033Ou"
#define ALT_KP_6        "\033Ov"
#define ALT_KP_7        "\033Ow"
#define ALT_KP_8        "\033Ox"
#define ALT_KP_9        "\033Oy"
#define ALT_KP_MINUS    "\033Om"
#define ALT_KP_PLUS     "\033Ok"
#define ALT_KP_PERIOD   "\033On"
#define ALT_KP_SLASH    "\033Oo"
#define ALT_KP_STAR     "\033Oj"
#define ALT_KP_EQUALS   "\033OX"
#define ALT_KP_ENTER    "\033OM"



#define KEY_FUNCTION_FORMAT  "\033[%d~"

#define REPORT_POSITION      "\033[%d;%dR"
#define REPORT_POSITION_Q    "\033[?%d;%dR"
#define REPORT_STATUS        "\033[0n"
// Device Attribute : VT100 with Advanced Video Option
#define REPORT_WHATAREYOU    "\033[?1;2c"
// Secondary Device Attribute: VT100
#define REPORT_SDA           "\033[>0;95;c"
#define REPORT_VT52          "\033/Z"

#define conststr_sizeof(n)   ((sizeof(n)) - 1)
#define MAKE_CSI_COMMAND(first, second) ((first << 8) | second) // used by old parser
#define PACK_CSI_COMMAND(first, second) ((first << 8) | second) // used by new parser
#define ADVANCE(datap, datalen, rmlen) do { datap++; datalen--; (*rmlen)++; } while (0)

typedef struct {
    int p[VT100CSIPARAM_MAX];
    int count;
    int cmd;
    BOOL question; // used by old parser
    int modifier;  // used by old parser
} CSIParam;

// functions
static BOOL isCSI(unsigned char *, int);
static BOOL isXTERM(unsigned char *, int);
static BOOL isString(unsigned char *, NSStringEncoding);
static int getCSIParam(unsigned char *, int, CSIParam *, VT100Screen *);
static int getCSIParamCanonically(unsigned char *, int, CSIParam *, VT100Screen *);
static VT100TCC decode_csi(unsigned char *, int, int *,VT100Screen *);
static VT100TCC decode_csi_canonically(unsigned char *, int, int *,VT100Screen *);
static VT100TCC decode_xterm(unsigned char *, int, int *,NSStringEncoding);
static VT100TCC decode_ansi(unsigned char *,int, int *,VT100Screen *);
static VT100TCC decode_other(unsigned char *, int, int *, NSStringEncoding);
static VT100TCC decode_control(unsigned char *, int, int *, NSStringEncoding, VT100Screen *, BOOL);
static VT100TCC decode_utf8(unsigned char *, int, int *);
static VT100TCC decode_euccn(unsigned char *, int, int *);
static VT100TCC decode_big5(unsigned char *,int, int *);
static VT100TCC decode_string(unsigned char *, int, int *,
                              NSStringEncoding);

static BOOL isCSI(unsigned char *code, int len)
{
    if (len >= 2 && code[0] == ESC && (code[1] == '[')) {
        return YES;
    }
    return NO;
}

static BOOL isXTERM(unsigned char *code, int len)
{
    if (len >= 2 && code[0] == ESC && (code[1] == ']'))
        return YES;
    return NO;
}

static BOOL isANSI(unsigned char *code, int len)
{
    // Currently, we only support esc-c as an ANSI code (other ansi codes are CSI).
    if (len >= 2 && code[0] == ESC && code[1] == 'c') {
        return YES;
    }
    return NO;
}

static BOOL isDCS(unsigned char *code, int len)
{
    if (len >= 2 && code[0] == ESC && code[1] == 'P') {
        return YES;
    }
    return NO;
}

static BOOL isString(unsigned char *code,
                     NSStringEncoding encoding)
{
    BOOL result = NO;

    //    NSLog(@"%@",[NSString localizedNameOfStringEncoding:encoding]);
    if (encoding== NSUTF8StringEncoding) {
        if (*code >= 0x80) {
            result = YES;
        }
    }
    else if (isGBEncoding(encoding)) {
        if (iseuccn(*code))
            result = YES;
    }
    else if (isBig5Encoding(encoding)) {
        if (isbig5(*code))
            result = YES;
    }
    else if (isJPEncoding(encoding)) {
        if (*code ==0x8e || *code==0x8f|| (*code>=0xa1&&*code<=0xfe))
            result = YES;
    }
    else if (isSJISEncoding(encoding)) {
        if (*code >= 0x80)
            result = YES;
    }
    else if (isKREncoding(encoding)) {
        if (iseuckr(*code))
            result = YES;
    }
    else if (*code>=0x20) {
        result = YES;
    }

    return result;
}

static int advanceAndEatControlChars(unsigned char **ppdata,
                                     int *pdatalen,
                                     VT100Screen *SCREEN)
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
                [SCREEN activateBell];
                break;
            case VT100CC_BS:
                [SCREEN backSpace];
                break;
            case VT100CC_HT:
                [SCREEN setTab];
                break;
            case VT100CC_LF:
            case VT100CC_VT:
            case VT100CC_FF:
                [SCREEN setNewLine];
                break;
            case VT100CC_CR:
                [SCREEN cursorToX:1 Y:[SCREEN cursorY]];
                break;
            case VT100CC_SO:
                // TODO: ISO-2022 mode terminal should implement SO
                break;
            case VT100CC_SI:
                // TODO: ISO-2022 mode terminal should implement SI
                break;
            case VT100CC_DC1:
                break;
            case VT100CC_DC3:
                break;
            case VT100CC_CAN:
            case VT100CC_SUB:
            case VT100CC_ESC:
                return NO;
            case VT100CC_DEL:
                [SCREEN deleteCharacters:1];
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
                       CSIParam *param, VT100Screen *SCREEN)
{
    int i;
    BOOL unrecognized=NO;
    unsigned char *orgp = datap;
    BOOL readNumericParameter = NO;

    NSCParameterAssert(datap != NULL);
    NSCParameterAssert(datalen >= 2);
    NSCParameterAssert(param != NULL);

    param->count = 0;
    param->cmd = 0;
    for (i = 0; i < VT100CSIPARAM_MAX; ++i )
        param->p[i] = -1;

    NSCParameterAssert(datap[0] == ESC);
    NSCParameterAssert(datap[1] == '[');
    datap += 2;
    datalen -= 2;

    if (datalen > 0 && *datap == '?') {
        param->question = YES;
        datap ++;
        datalen --;
    }
    // check for secondsry device attribute modifier
    else if (datalen > 0 && *datap == '>')
    {
        param->modifier = '>';
        param->question = NO;
        datap++;
        datalen--;
    }
    else
        param->question = NO;


    while (datalen > 0) {

        if (isdigit(*datap)) {
            int n = *datap - '0';
            datap++;
            datalen--;

            while (datalen > 0 && isdigit(*datap)) {
                if (n > (INT_MAX - 10) / 10) {
                    param->cmd = 0xff;
                    unrecognized = YES;
                }
                n = n * 10 + *datap - '0';

                datap++;
                datalen--;
            }
            if (param->count < VT100CSIPARAM_MAX)
                param->p[param->count] = n;
            // increment the parameter count
            param->count++;

            // set the numeric parameter flag
            readNumericParameter = YES;

        }
        else if (*datap == ';') {
            datap++;
            datalen--;

            // If we got an implied (blank) parameter, increment the parameter count again
            if(readNumericParameter == NO)
                param->count++;
            // reset the parameter flag
            readNumericParameter = NO;

            if (param->count >= VT100CSIPARAM_MAX) {
                // broken
                param->cmd = 0xff;
                unrecognized = YES;
            }
        }
        else if (isalpha(*datap)||*datap=='@') {
            datalen--;
            param->cmd = unrecognized?0xff:*datap;
            datap++;
            break;
        }
        else if (*datap == ' ') {
            datap++;
            datalen--;
            switch (*datap) {
                case 'q':
                    param->cmd = MAKE_CSI_COMMAND(' ', 'q');
                    datap++;
                    datalen--;
                    return datap - orgp;
                default:
                    //NSLog(@"Unrecognized sequence: CSI SP %c (0x%x)", *datap, *datap);
                    datap++;
                    datalen--;
                    param->cmd = 0xff;
                    break;
            }
        }
        else if (*datap=='\'') {
            datap++;
            datalen--;
            switch (*datap) {
                case 'z':
                case '|':
                case 'w':
                    //NSLog(@"Unsupported locator sequence");
                    param->cmd=0xff;
                    datap++;
                    datalen--;
                    break;
                default:
                    //NSLog(@"Unrecognized locator sequence");
                    datap++;
                    datalen--;
                    param->cmd=0xff;
                    break;
            }
            break;
        }
        else if (*datap=='&') {
            datap++;
            datalen--;
            switch (*datap) {
                case 'w':
                    //NSLog(@"Unsupported locator sequence");
                    param->cmd=0xff;
                    datap++;
                    datalen--;
                    break;
                default:
                    //NSLog(@"Unrecognized locator sequence");
                    datap++;
                    datalen--;
                    param->cmd=0xff;
                    break;
            }
            break;
        }
        else if (*datap == '!') {
            datap++;
            datalen--;
            if (datalen == 0) {
                return -1;
            }
            switch (*datap) {
                case 'p':
                    param->cmd = MAKE_CSI_COMMAND('!', 'p');
                    datap++;
                    datalen--;
                    return datap - orgp;
                default:
                    datap++;
                    datalen--;
                    param->cmd=0xff;
                    break;
            }
        }
        else {
            switch (*datap) {
                case VT100CC_ENQ: break;
                case VT100CC_BEL: [SCREEN activateBell]; break;
                case VT100CC_BS:  [SCREEN backSpace]; break;
                case VT100CC_HT:  [SCREEN setTab]; break;
                case VT100CC_LF:
                case VT100CC_VT:
                case VT100CC_FF:  [SCREEN setNewLine]; break;
                case VT100CC_CR:  [SCREEN cursorToX:1 Y:[SCREEN cursorY]]; break;
                case VT100CC_SO:  break;
                case VT100CC_SI:  break;
                case VT100CC_DC1: break;
                case VT100CC_DC3: break;
                case VT100CC_CAN:
                case VT100CC_SUB: break;
                case VT100CC_DEL: [SCREEN deleteCharacters:1];break;
                default:
                    //NSLog(@"Unrecognized escape sequence: %c (0x%x)", *datap, *datap);
                    param->cmd=0xff;
                    unrecognized=YES;
                    break;
            }
            if (unrecognized == NO) {
                datalen--;
                datap++;
            }
        }
        if (unrecognized) break;
    }
    return datap - orgp;
}

static int getCSIParamCanonically(unsigned char *datap,
                                  int datalen,
                                  CSIParam *param, VT100Screen *SCREEN)
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
    // VT100TCC.u.csi.modifier and VT100TCC.u.csi.question flags are dropped.
    // Now they are aggregated with VT100TCC.u.csi.cmd parameter.
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

    if (!advanceAndEatControlChars(&datap, &datalen, SCREEN)) {
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
                if (!advanceAndEatControlChars(&datap, &datalen, SCREEN))
                    goto cancel;
                break;
            default:
                break;
        }
    }

    //     2. parse parameters
    //        Typically, it consists of '0'-'9' or ';',
    //        ':', '<', '=', '>', '?' should be ignored, but if current sequence contains them,
    //        this sequence should be mark as unrecognized.
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
                    if (!advanceAndEatControlChars(&datap, &datalen, SCREEN)) {
                        goto cancel;
                    }
                }
                if (param->count < VT100CSIPARAM_MAX) {
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
                if (param->count >= VT100CSIPARAM_MAX) {
                    unrecognized = YES;
                } else if(readNumericParameter == NO) {
                    param->count++;
                }
                // reset the parameter flag
                readNumericParameter = NO;

                if (!advanceAndEatControlChars(&datap, &datalen, SCREEN)) {
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
                //   http://www.nak.ics.keio.ac.jp/~haru/yaft/glyph_width_report.html
                //
                // In this usage, ":" are certainly treated as sub-parameter separators.
                //
                // I think, at the time when we need sub-parameter, CSIParam should be extended.
                // Now we ignore them by the reason of performance.
                unrecognized = YES;
                if (!advanceAndEatControlChars(&datap, &datalen, SCREEN)) {
                    goto cancel;
                }
                break;

            default:
                // '<', '=', '>', or '?'
                unrecognized = YES;
                if (!advanceAndEatControlChars(&datap, &datalen, SCREEN)) {
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
        if (!advanceAndEatControlChars(&datap, &datalen, SCREEN)) {
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
            if (!advanceAndEatControlChars(&datap, &datalen, SCREEN)) {
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

#define SET_PARAM_DEFAULT(pm,n,d) \
(((pm).p[(n)] = (pm).p[(n)] < 0 ? (d):(pm).p[(n)]), \
 ((pm).count  = (pm).count > (n) + 1 ? (pm).count : (n) + 1 ))

static VT100TCC decode_ansi(unsigned char *datap,
                            int datalen,
                            int *rmlen,
                            VT100Screen *SCREEN)
{
    VT100TCC result;
    result.type = VT100_UNKNOWNCHAR;
    if (datalen >= 2 && datap[0] == ESC) {
        switch (datap[1]) {
            case 'c':
                result.type = ANSI_RIS;
                *rmlen = 2;
                break;
        }
    }
    return result;
}


static VT100TCC decode_csi(unsigned char *datap,
                           int datalen,
                           int *rmlen,
                           VT100Screen *SCREEN)
{
    VT100TCC result;
    CSIParam param={{0},0};
    int paramlen;
    int i;

    paramlen = getCSIParam(datap, datalen, &param, SCREEN);
    result.type = VT100_WAIT;

    // Check for unkown
    if (param.cmd == 0xff) {
        result.type = VT100_UNKNOWNCHAR;
        *rmlen = paramlen;
    }
    // process
    else if (paramlen > 0 && param.cmd > 0) {
        if (!param.question) {
            switch (param.cmd) {
                case 'D':       // Cursor Backward
                    result.type = VT100CSI_CUB;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    break;

                case 'B':       // Cursor Down
                    result.type = VT100CSI_CUD;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    break;

                case 'C':       // Cursor Forward
                    result.type = VT100CSI_CUF;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    break;

                case 'A':       // Cursor Up
                    result.type = VT100CSI_CUU;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    break;

                case 'H':
                    result.type = VT100CSI_CUP;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    SET_PARAM_DEFAULT(param, 1, 1);
                    break;

                case 'c':
                    if (param.modifier == '>') {
                        result.type = VT100CSI_DA2;
                    } else {
                        result.type = VT100CSI_DA;
                    }
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;

                case 'q':
                    result.type = VT100CSI_DECLL;
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;

                case 'x':
                    if (param.count == 1)
                        result.type = VT100CSI_DECREQTPARM;
                    else
                        result.type = VT100CSI_DECREPTPARM;
                    break;

                case 'r':
                    result.type = VT100CSI_DECSTBM;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    SET_PARAM_DEFAULT(param, 1, [SCREEN height]);
                    break;

                case 'y':
                    if (param.count == 2)
                        result.type = VT100CSI_DECTST;
                    else
                    {
#if LOG_UNKNOWN
                        NSLog(@"1: Unknown token %c", param.cmd);
#endif
                        result.type = VT100_NOTSUPPORT;
                    }
                        break;

                case 'n':
                    result.type = VT100CSI_DSR;
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;

                case 'J':
                    result.type = VT100CSI_ED;
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;

                case 'K':
                    result.type = VT100CSI_EL;
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;

                case 'f':
                    result.type = VT100CSI_HVP;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    SET_PARAM_DEFAULT(param, 1, 1);
                    break;

                case 'l':
                    result.type = VT100CSI_RM;
                    break;

                case 'm':
                    if (param.modifier == '>') {
                        result.type = VT100CSI_SET_MODIFIERS;
                    } else {
                        result.type = VT100CSI_SGR;
                    }
                    for (i = 0; i < param.count; ++i) {
                        SET_PARAM_DEFAULT(param, i, 0);
                        //                        NSLog(@"m[%d]=%d",i,param.p[i]);
                    }
                    break;

                case 'h':
                    if (param.modifier == '>') {
                        result.type = VT100CSI_RESET_MODIFIERS;
                    } else {
                        result.type = VT100CSI_SM;
                    }
                    break;

                case 'g':
                    result.type = VT100CSI_TBC;
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;

                case MAKE_CSI_COMMAND(' ', 'q'):
                    result.type = VT100CSI_DECSCUSR;
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;

                case MAKE_CSI_COMMAND('!', 'p'):
                    result.type = VT100CSI_DECSTR;
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;

                    // these are xterm controls
                case '@':
                    result.type = XTERMCC_INSBLNK;
                    SET_PARAM_DEFAULT(param,0,1);
                    break;
                case 'L':
                    result.type = XTERMCC_INSLN;
                    SET_PARAM_DEFAULT(param,0,1);
                    break;
                case 'P':
                    result.type = XTERMCC_DELCH;
                    SET_PARAM_DEFAULT(param,0,1);
                    break;
                case 'M':
                    result.type = XTERMCC_DELLN;
                    SET_PARAM_DEFAULT(param,0,1);
                    break;
                case 't':
                    switch (param.p[0]) {
                        case 8:
                            result.type = XTERMCC_WINDOWSIZE;
                            SET_PARAM_DEFAULT(param, 1, 0);     // columns or Y
                            SET_PARAM_DEFAULT(param, 2, 0);     // rows or X
                            break;
                        case 3:
                            result.type = XTERMCC_WINDOWPOS;
                            SET_PARAM_DEFAULT(param, 1, 0);     // columns or Y
                            SET_PARAM_DEFAULT(param, 2, 0);     // rows or X
                            break;
                        case 4:
                            result.type = XTERMCC_WINDOWSIZE_PIXEL;
                            SET_PARAM_DEFAULT(param, 1, 0);     // columns or Y
                            SET_PARAM_DEFAULT(param, 2, 0);     // rows or X
                            break;
                        case 2:
                            result.type = XTERMCC_ICONIFY;
                            break;
                        case 1:
                            result.type = XTERMCC_DEICONIFY;
                            break;
                        case 5:
                            result.type = XTERMCC_RAISE;
                            break;
                        case 6:
                            result.type = XTERMCC_LOWER;
                            break;
                        case 11:
                            result.type = XTERMCC_REPORT_WIN_STATE;
                            break;
                        case 13:
                            result.type = XTERMCC_REPORT_WIN_POS;
                            break;
                        case 14:
                            result.type = XTERMCC_REPORT_WIN_PIX_SIZE;
                            break;
                        case 18:
                            result.type = XTERMCC_REPORT_WIN_SIZE;
                            break;
                        case 19:
                            result.type = XTERMCC_REPORT_SCREEN_SIZE;
                            break;
                        case 20:
                            result.type = XTERMCC_REPORT_ICON_TITLE;
                            break;
                        case 21:
                            result.type = XTERMCC_REPORT_WIN_TITLE;
                            break;
                        case 22:
                            result.type = XTERMCC_PUSH_TITLE;
                            SET_PARAM_DEFAULT(param, 0, 0);
                            break;
                        case 23:
                            result.type = XTERMCC_POP_TITLE;
                            SET_PARAM_DEFAULT(param, 0, 0);
                            break;
                        default:
                            result.type = VT100_NOTSUPPORT;
                            break;
                    }
                    break;
                case 'S':
                    result.type = XTERMCC_SU;
                    SET_PARAM_DEFAULT(param,0,1);
                    break;
                case 'T':
                    if (param.count<2) {
                        result.type = XTERMCC_SD;
                        SET_PARAM_DEFAULT(param,0,1);
                    }
                    else
                        result.type = VT100_NOTSUPPORT;

                    break;


                    // ANSI
                case 'Z':
                    result.type = ANSICSI_CBT;
                    SET_PARAM_DEFAULT(param,0,1);
                    break;
                case 'G':
                    result.type = ANSICSI_CHA;
                    SET_PARAM_DEFAULT(param,0,1);
                    break;
                case 'd':
                    result.type = ANSICSI_VPA;
                    SET_PARAM_DEFAULT(param,0,1);
                    break;
                case 'e':
                    result.type = ANSICSI_VPR;
                    SET_PARAM_DEFAULT(param,0,1);
                    break;
                case 'X':
                    result.type = ANSICSI_ECH;
                    SET_PARAM_DEFAULT(param,0,1);
                    break;
                case 'i':
                    result.type = ANSICSI_PRINT;
                    SET_PARAM_DEFAULT(param,0,0);
                    break;
                case 's':
                    result.type = ANSICSI_SCP;
                    SET_PARAM_DEFAULT(param,0,0);
                    break;
                case 'u':
                    result.type = ANSICSI_RCP;
                    SET_PARAM_DEFAULT(param,0,0);
                    break;
                default:
#if LOG_UNKNOWN
                    NSLog(@"2: Unknown token (%c); %s", param.cmd, datap);
#endif
                    result.type = VT100_NOTSUPPORT;
                    break;
            }
        }
        else {
            switch (param.cmd) {
                case 'h':       // Dec private mode set
                    result.type = VT100CSI_DECSET;
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;
                case 'l':       // Dec private mode reset
                    result.type = VT100CSI_DECRST;
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;
                default:
#if LOG_UNKNOWN
                    NSLog(@"3: Unknown token %c", param.cmd);
#endif
                    result.type = VT100_NOTSUPPORT;
                    break;

            }
        }

        // copy CSI parameter
        for (i = 0; i < VT100CSIPARAM_MAX; ++i)
            result.u.csi.p[i] = param.p[i];
        result.u.csi.count = param.count;
        result.u.csi.question = param.question;
        result.u.csi.modifier = param.modifier;

        *rmlen = paramlen;
    }

    return result;
}

static VT100TCC decode_csi_canonically(unsigned char *datap,
                                       int datalen,
                                       int *rmlen,
                                       VT100Screen *SCREEN)
{
    VT100TCC result;
    CSIParam param={{0},0};
    int paramlen;
    int i;

    paramlen = getCSIParamCanonically(datap, datalen, &param, SCREEN);
    result.type = VT100_WAIT;

    // Check for unkown
    if (param.cmd == 0xff) {
        result.type = VT100_UNKNOWNCHAR;
        *rmlen = paramlen;
    }
    // process
    else if (paramlen > 0 && param.cmd > 0) {
        switch (param.cmd) {
            case 'D':       // Cursor Backward
                result.type = VT100CSI_CUB;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;

            case 'B':       // Cursor Down
                result.type = VT100CSI_CUD;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;

            case 'C':       // Cursor Forward
                result.type = VT100CSI_CUF;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;

            case 'A':       // Cursor Up
                result.type = VT100CSI_CUU;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;

            case 'H':
                result.type = VT100CSI_CUP;
                SET_PARAM_DEFAULT(param, 0, 1);
                SET_PARAM_DEFAULT(param, 1, 1);
                break;

            case 'c':
                result.type = VT100CSI_DA;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;

            case PACK_CSI_COMMAND('>', 'c'):
                result.type = VT100CSI_DA2;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;

            case 'q':
                result.type = VT100CSI_DECLL;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;

            case 'x':
                if (param.count == 1)
                    result.type = VT100CSI_DECREQTPARM;
                else
                    result.type = VT100CSI_DECREPTPARM;
                break;

            case 'r':
                result.type = VT100CSI_DECSTBM;
                SET_PARAM_DEFAULT(param, 0, 1);
                SET_PARAM_DEFAULT(param, 1, [SCREEN height]);
                break;

            case 'y':
                if (param.count == 2)
                    result.type = VT100CSI_DECTST;
                else
                {
#if LOG_UNKNOWN
                    NSLog(@"1: Unknown token %x", param.cmd);
#endif
                    result.type = VT100_NOTSUPPORT;
                }
                break;

            case 'n':
                result.type = VT100CSI_DSR;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;

            case PACK_CSI_COMMAND('?', 'n'):
                result.type = VT100CSI_DECDSR;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;

            case 'J':
                result.type = VT100CSI_ED;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;

            case 'K':
                result.type = VT100CSI_EL;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;

            case 'f':
                result.type = VT100CSI_HVP;
                SET_PARAM_DEFAULT(param, 0, 1);
                SET_PARAM_DEFAULT(param, 1, 1);
                break;

            case 'l':
                result.type = VT100CSI_RM;
                break;

            case PACK_CSI_COMMAND('>', 'm'):
                result.type = VT100CSI_SET_MODIFIERS;
                break;

            case PACK_CSI_COMMAND('>', 'n'):
                result.type = VT100CSI_RESET_MODIFIERS;
                break;

            case 'm':
                result.type = VT100CSI_SGR;
                for (i = 0; i < param.count; ++i) {
                    SET_PARAM_DEFAULT(param, i, 0);
                    //                        NSLog(@"m[%d]=%d",i,param.p[i]);
                }
                break;

            case 'h':
                result.type = VT100CSI_SM;
                break;

            case 'g':
                result.type = VT100CSI_TBC;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;

            case PACK_CSI_COMMAND(' ', 'q'):
                result.type = VT100CSI_DECSCUSR;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;

            case PACK_CSI_COMMAND('!', 'p'):
                result.type = VT100CSI_DECSTR;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;

            // these are xterm controls
            case '@':
                result.type = XTERMCC_INSBLNK;
                SET_PARAM_DEFAULT(param,0,1);
                break;
            case 'L':
                result.type = XTERMCC_INSLN;
                SET_PARAM_DEFAULT(param,0,1);
                break;
            case 'P':
                result.type = XTERMCC_DELCH;
                SET_PARAM_DEFAULT(param,0,1);
                break;
            case 'M':
                result.type = XTERMCC_DELLN;
                SET_PARAM_DEFAULT(param,0,1);
                break;
            case 't':
                switch (param.p[0]) {
                    case 8:
                        result.type = XTERMCC_WINDOWSIZE;
                        SET_PARAM_DEFAULT(param, 1, 0);     // columns or Y
                        SET_PARAM_DEFAULT(param, 2, 0);     // rows or X
                        break;
                    case 3:
                        result.type = XTERMCC_WINDOWPOS;
                        SET_PARAM_DEFAULT(param, 1, 0);     // columns or Y
                        SET_PARAM_DEFAULT(param, 2, 0);     // rows or X
                        break;
                    case 4:
                        result.type = XTERMCC_WINDOWSIZE_PIXEL;
                        SET_PARAM_DEFAULT(param, 1, 0);     // columns or Y
                        SET_PARAM_DEFAULT(param, 2, 0);     // rows or X
                        break;
                    case 2:
                        result.type = XTERMCC_ICONIFY;
                        break;
                    case 1:
                        result.type = XTERMCC_DEICONIFY;
                        break;
                    case 5:
                        result.type = XTERMCC_RAISE;
                        break;
                    case 6:
                        result.type = XTERMCC_LOWER;
                        break;
                    case 11:
                        result.type = XTERMCC_REPORT_WIN_STATE;
                        break;
                    case 13:
                        result.type = XTERMCC_REPORT_WIN_POS;
                        break;
                    case 14:
                        result.type = XTERMCC_REPORT_WIN_PIX_SIZE;
                        break;
                    case 18:
                        result.type = XTERMCC_REPORT_WIN_SIZE;
                        break;
                    case 19:
                        result.type = XTERMCC_REPORT_SCREEN_SIZE;
                        break;
                    case 20:
                        result.type = XTERMCC_REPORT_ICON_TITLE;
                        break;
                    case 21:
                        result.type = XTERMCC_REPORT_WIN_TITLE;
                        break;
                    default:
                        result.type = VT100_NOTSUPPORT;
                        break;
                }
                break;
            case 'S':
                result.type = XTERMCC_SU;
                SET_PARAM_DEFAULT(param,0,1);
                break;
            case 'T':
                if (param.count < 2) {
                    result.type = XTERMCC_SD;
                    SET_PARAM_DEFAULT(param,0,1);
                }
                else
                    result.type = VT100_NOTSUPPORT;
                break;

            // ANSI
            case 'Z':
                result.type = ANSICSI_CBT;
                SET_PARAM_DEFAULT(param,0,1);
                break;
            case 'G':
                result.type = ANSICSI_CHA;
                SET_PARAM_DEFAULT(param,0,1);
                break;
            case 'd':
                result.type = ANSICSI_VPA;
                SET_PARAM_DEFAULT(param,0,1);
                break;
            case 'e':
                result.type = ANSICSI_VPR;
                SET_PARAM_DEFAULT(param,0,1);
                break;
            case 'X':
                result.type = ANSICSI_ECH;
                SET_PARAM_DEFAULT(param,0,1);
                break;
            case 'i':
                result.type = ANSICSI_PRINT;
                SET_PARAM_DEFAULT(param,0,0);
                break;
            case 's':
                result.type = ANSICSI_SCP;
                SET_PARAM_DEFAULT(param,0,0);
                break;
            case 'u':
                result.type = ANSICSI_RCP;
                SET_PARAM_DEFAULT(param,0,0);
                break;
            case PACK_CSI_COMMAND('?', 'h'):       // Dec private mode set
                result.type = VT100CSI_DECSET;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;
            case PACK_CSI_COMMAND('?', 'l'):       // Dec private mode reset
                result.type = VT100CSI_DECRST;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;
            default:
#if LOG_UNKNOWN
                NSLog(@"3: Unknown token %x", param.cmd);
#endif
                result.type = VT100_NOTSUPPORT;
                break;

        }

        // copy CSI parameter
        for (i = 0; i < VT100CSIPARAM_MAX; ++i)
            result.u.csi.p[i] = param.p[i];
        result.u.csi.count = param.count;

        *rmlen = paramlen;
    }

    return result;
}

static VT100TCC decode_dcs(unsigned char *datap,
                           int datalen,
                           int *rmlen,
                           NSStringEncoding enc)
{
    // DCS is kind of messy to parse, but we only support one code, so we just check if it's that.
    VT100TCC result;
    result.type = VT100_WAIT;
    // Can assume we have "ESC P" so skip past that.
    datap += 2;
    datalen -= 2;
    *rmlen=2;
    if (datalen >= 5) {
        if (!strncmp((char *)datap, "1000p", 5)) {
            result.type = DCS_TMUX;
            *rmlen += 5;
        } else {
            result.type = VT100_NOTSUPPORT;
        }
    }
    return result;
}

static VT100TCC decode_xterm(unsigned char *datap,
                             int datalen,
                             int *rmlen,
                             NSStringEncoding enc)
{
    int mode = 0;
    VT100TCC result;
    NSData *data;
    char s[MAX_BUFFER_LENGTH] = { 0 }, *c = nil;

    assert(datap != NULL);
    assert(datalen >= 2);
    *rmlen = 0;
    assert(*datap == ESC);
    ADVANCE(datap, datalen, rmlen);
    assert(*datap == ']');
    ADVANCE(datap, datalen, rmlen);

    if (datalen > 0 && isdigit(*datap)) {
        // read an integer from datap and store it in mode.
        int n = *datap - '0';
        ADVANCE(datap, datalen, rmlen);
        while (datalen > 0 && isdigit(*datap)) {
            // TODO(georgen): Handle integer overflow
            n = n * 10 + *datap - '0';
            ADVANCE(datap, datalen, rmlen);
        }
        mode = n;
    }
    BOOL unrecognized = NO;
    if (datalen > 0) {
        if (*datap != ';' && *datap != 'P') {
	    // Bogus first char after "esc ] [number]". Consume up to and
	    // including terminator and then return VT100_NOTSUPPORT.
            unrecognized = YES;
        } else {
            if (*datap == 'P') {
                mode = -1;
            }
            // Consume ';' or 'P'.
            ADVANCE(datap, datalen, rmlen);
        }
        BOOL str_end = NO;
        c = s;
        // Search for the end of a ^G/ST terminated string (but see the note below about other ways to terminate it).
        while (datalen > 0) {
            // broken OSC (ESC ] P NRRGGBB) does not need any terminator
            if (mode == -1 && c - s >= 7) {
                str_end = YES;
                break;
            }
            // A string control should be canceled by CAN or SUB.
            if (*datap == VT100CC_CAN || *datap == VT100CC_SUB) {
                ADVANCE(datap, datalen, rmlen);
                str_end = YES;
                unrecognized = YES;
                break;
            }
            // BEL terminator
            if (*datap == VT100CC_BEL) {
                ADVANCE(datap, datalen, rmlen);
                str_end = YES;
                break;
            }
            if (*datap == VT100CC_ESC) {
                if (datalen >= 2 && *(datap + 1) == ']') {
                    // if Esc + ] is present recursively, simply skip it.
                    //
                    // Example:
                    //
                    //    ESC ] 0 ; a b c ESC ] d e f BEL
                    //
                    // title string "abcdef" should be accepted.
                    //
                    ADVANCE(datap, datalen, rmlen);
                    ADVANCE(datap, datalen, rmlen);
                    continue;
                } else if (datalen >= 2 && *(datap + 1) == '\\') {
                    // if Esc + \ is present, terminate OSC successfully.
                    //
                    // Example:
                    //
                    //    ESC ] 0 ; a b c ESC '\\'
                    //
                    // title string "abc" should be accepted.
                    //
                    ADVANCE(datap, datalen, rmlen);
                    ADVANCE(datap, datalen, rmlen);
                    str_end = YES;
                    break;
                } else {
                    // otherwise, terminate OSC unsuccessfully and backtrack before ESC.
                    //
                    // Example:
                    //
                    //    ESC ] 0 ; a b c ESC c
                    //
                    // "abc" should be discarded.
                    // ESC c is also accepted and causes hard reset(RIS).
                    //
                    str_end = YES;
                    unrecognized = YES;
                    break;
                }
            }
            if (c - s < MAX_BUFFER_LENGTH) {
                // if 0 <= mode <=2 and current *datap is a control character, replace it with '?'. 
                if ((*datap < 0x20 || *datap == 0x7f) && (mode == 0 || mode == 1 || mode == 2)) {
                    *c = '?';
                } else {
                    *c = *datap;
                }
                c++;
            }
            ADVANCE(datap, datalen, rmlen);
        }
        if (!str_end && datalen == 0) {
            // Ran out of data before terminator. Keep trying.
            *rmlen = 0;
        }
    } else {
        // No data yet, keep trying.
        *rmlen = 0;
    }

    if (!(*rmlen)) {
        result.type = VT100_WAIT;
    } else if (unrecognized) {
        // Found terminator but it's malformed.
        result.type = VT100_NOTSUPPORT;
    } else {
        data = [NSData dataWithBytes:s length:c - s];
        result.u.string = [[[NSString alloc] initWithData:data
                                                 encoding:enc] autorelease];
        switch (mode) {
            case -1:
                // Nonstandard Linux OSC P nrrggbb ST to change color palette
                // entry.
                result.type = XTERMCC_SET_PALETTE;
                break;
            case 0:
                result.type = XTERMCC_WINICON_TITLE;
                break;
            case 1:
                result.type = XTERMCC_ICON_TITLE;
                break;
            case 2:
                result.type = XTERMCC_WIN_TITLE;
                break;
            case 4:
                result.type = XTERMCC_SET_RGB;
                break;
            case 6:
                // This is not a real xterm code. It is from eTerm, which extended the xterm
                // protocol for its own purposes. We don't follow the eTerm protocol,
                // but we follow the template it set.
                // http://www.eterm.org/docs/view.php?doc=ref#escape
                result.type = XTERMCC_PROPRIETARY_ETERM_EXT;
                break;
            case 9:
                result.type = ITERM_GROWL;
                break;
            case 50:
                // Nonstandard escape code implemented by Konsole.
                // <Esc>]50;key=value^G
                result.type = XTERMCC_SET_KVP;
                break;
            case 52:
                // base64 copy/paste (OPT_PASTE64)
                result.type = XTERMCC_PASTE64;
                break;
            default:
                result.type = VT100_NOTSUPPORT;
                break;
        }
        //        NSLog(@"result: %d[%@],%d",result.type,result.u.string,*rmlen);
    }

    return result;
}

static VT100TCC decode_other(unsigned char *datap,
                             int datalen,
                             int *rmlen,
                             NSStringEncoding enc)
{
    VT100TCC result;
    int c1, c2;

    NSCParameterAssert(datap[0] == ESC);
    NSCParameterAssert(datalen > 1);

    c1 = (datalen >= 2 ? datap[1]: -1);
    c2 = (datalen >= 3 ? datap[2]: -1);
    // A third parameter could be available but isn't currently used.
    // c3 = (datalen >= 4 ? datap[3]: -1);

    switch (c1) {
        case 27: // esc: two esc's in a row. Ignore the first one.
            result.type = VT100_NOTSUPPORT;
            *rmlen = 1;
            break;

        case '#':
            if (c2 < 0) {
                result.type = VT100_WAIT;
            } else {
                switch (c2) {
                    case '8': result.type=VT100CSI_DECALN; break;
                    default:
#if LOG_UNKNOWN
                        NSLog(@"4: Unknown token ESC # %c", c2);
#endif
                        result.type = VT100_NOTSUPPORT;
                }
                *rmlen = 3;
            }
            break;

        case '=':
            result.type = VT100CSI_DECKPAM;
            *rmlen = 2;
            break;

        case '>':
            result.type = VT100CSI_DECKPNM;
            *rmlen = 2;
            break;

        case '<':
            result.type = STRICT_ANSI_MODE;
            *rmlen = 2;
            break;

        case '(':
            if (c2 < 0) {
                result.type = VT100_WAIT;
            } else {
                result.type = VT100CSI_SCS0;
                result.u.code = c2;
                *rmlen = 3;
            }
            break;
        case ')':
            if (c2 < 0) {
                result.type = VT100_WAIT;
            } else {
                result.type = VT100CSI_SCS1;
                result.u.code=c2;
                *rmlen = 3;
            }
            break;
        case '*':
            if (c2 < 0) {
                result.type = VT100_WAIT;
            } else {
                result.type = VT100CSI_SCS2;
                result.u.code=c2;
                *rmlen = 3;
            }
            break;
        case '+':
            if (c2 < 0) {
                result.type = VT100_WAIT;
            } else {
                result.type = VT100CSI_SCS3;
                result.u.code=c2;
                *rmlen = 3;
            }
            break;

        case '8':
            result.type = VT100CSI_DECRC;
            *rmlen = 2;
            break;

        case '7':
            result.type = VT100CSI_DECSC;
            *rmlen = 2;
            break;

        case 'D':
            result.type = VT100CSI_IND;
            *rmlen = 2;
            break;

        case 'E':
            result.type = VT100CSI_NEL;
            *rmlen = 2;
            break;

        case 'H':
            result.type = VT100CSI_HTS;
            *rmlen = 2;
            break;

        case 'M':
            result.type = VT100CSI_RI;
            *rmlen = 2;
            break;

        case 'Z':
            result.type = VT100CSI_DECID;
            *rmlen = 2;
            break;

        case 'c':
            result.type = VT100CSI_RIS;
            *rmlen = 2;
            break;

        case 'k':
            // The screen term uses <esc>k<title><cr|esc\> to set the title.
            if (datalen > 0) {
                int i;
                BOOL found = NO;
                // Search for esc or newline terminator.
                for (i = 2; i < datalen; i++) {
                    BOOL isTerminator = NO;
                    int length = i - 2;
                    if (datap[i] == ESC && i + 1 == datalen) {
                        break;
                    } else if (datap[i] == ESC && datap[i + 1] == '\\') {
                        i++;  // cause the backslash to be consumed below
                        isTerminator = YES;
                    } else if (datap[i] == '\n' || datap[i] == '\r') {
                        isTerminator = YES;
                    }
                    if (isTerminator) {
                        // Found terminator. Grab text from datap to char before it
                        // save in result.u.string.
                        NSData *data = [NSData dataWithBytes:datap + 2 length:length];
                        result.u.string = [[[NSString alloc] initWithData:data
                                                                 encoding:enc] autorelease];
                        // Consume everything up to the terminator
                        *rmlen = i + 1;
                        found = YES;
                        break;
                    }
                }
                if (found) {
                    if (result.u.string.length == 0) {
                        // Ignore 0-length titles to avoid getting bitten by a screen
                        // feature/hack described here:
                        // http://www.gnu.org/software/screen/manual/screen.html#Dynamic-Titles
                        //
                        // screen has a shell-specific heuristic that is enabled by setting the
                        // window's name to search|name and arranging to have a null title
                        // escape-sequence output as a part of your prompt. The search portion
                        // specifies an end-of-prompt search string, while the name portion
                        // specifies the default shell name for the window. If the name ends in
                        // a Ô:Õ screen will add what it believes to be the current command
                        // running in the window to the end of the specified name (e.g. name:cmd).
                        // Otherwise the current command name supersedes the shell name while it
                        // is running.
                        //
                        // Here's how it works: you must modify your shell prompt to output a null
                        // title-escape-sequence (<ESC> k <ESC> \) as a part of your prompt. The
                        // last part of your prompt must be the same as the string you specified
                        // for the search portion of the title. Once this is set up, screen will
                        // use the title-escape-sequence to clear the previous command name and
                        // get ready for the next command. Then, when a newline is received from
                        // the shell, a search is made for the end of the prompt. If found, it
                        // will grab the first word after the matched string and use it as the
                        // command name. If the command name begins with Ô!Õ, Ô%Õ, or Ô^Õ, screen
                        // will use the first word on the following line (if found) in preference
                        // to the just-found name. This helps csh users get more accurate titles
                        // when using job control or history recall commands.
                        result.type = VT100_NOTSUPPORT;
                    } else {
                        result.type = XTERMCC_WINICON_TITLE;
                    }
                } else {
                    result.type = VT100_WAIT;
                }
            } else {
                result.type = VT100_WAIT;
            }
            break;

        case ' ':
            if (c2<0) {
                result.type = VT100_WAIT;
            } else {
                switch (c2) {
                    case 'L':
                    case 'M':
                    case 'N':
                    case 'F':
                    case 'G':
                        *rmlen = 3;
                        result.type = VT100_NOTSUPPORT;
                        break;
                    default:
                        *rmlen = 1;
                        result.type = VT100_NOTSUPPORT;
                        break;
                }
            }
            break;

        default:
#if LOG_UNKNOWN
            NSLog(@"5: Unknown token %c(%x)", c1, c1);
#endif
            result.type = VT100_NOTSUPPORT;
            *rmlen = 2;
            break;
    }

    return result;
}

static VT100TCC decode_control(unsigned char *datap,
                               int datalen,
                               int *rmlen,
                               NSStringEncoding enc,
                               VT100Screen *SCREEN,
                               BOOL canonical)
{
    VT100TCC result;

    if (isCSI(datap, datalen)) {
        if (canonical) {
            result = decode_csi_canonically(datap, datalen, rmlen, SCREEN);
        } else {
            result = decode_csi(datap, datalen, rmlen, SCREEN);
        }
    } else if (isXTERM(datap,datalen)) {
        result = decode_xterm(datap, datalen, rmlen, enc);
    } else if (isANSI(datap, datalen)) {
        result = decode_ansi(datap, datalen, rmlen, SCREEN);
    } else if (isDCS(datap, datalen)) {
        result = decode_dcs(datap, datalen, rmlen, enc);
    } else {
        NSCParameterAssert(datalen > 0);

        switch ( *datap ) {
            case VT100CC_NULL:
                result.type = VT100_SKIP;
                *rmlen = 0;
                while (datalen > 0 && *datap == '\0') {
                    ++datap;
                    --datalen;
                    ++ *rmlen;
                }
                break;

            case VT100CC_ESC:
                if (datalen == 1) {
                    result.type = VT100_WAIT;
                } else {
                    result = decode_other(datap, datalen, rmlen, enc);
                }
                break;

            default:
                result.type = *datap;
                *rmlen = 1;
                break;
        }
    }
    return result;
}

static VT100TCC decode_utf8(unsigned char *datap,
                            int datalen,
                            int *rmlen)
{
    VT100TCC result;
    unsigned char *p = datap;
    int len = datalen;
    int utf8DecodeResult;
    int theChar = 0;

    while (true) {
        utf8DecodeResult = decode_utf8_char(p, len, &theChar);
        // Stop on error or end of stream.
        if (utf8DecodeResult <= 0) {
            break;
        }
        // Intentionally break out at ASCII characters. They are
        // processed separately, e.g. they might get converted into
        // line drawing characters.
        if (theChar < 0x80) {
            break;
        }
        // Reject UTF-16 surrogates. They are invalid Unicode codepoints,
        // and NSString initWithBytes fails on them.
        // Reject characters above U+10FFFF. NSString uses UTF-16
        // internally, so it cannot handle higher codepoints.
        if ((theChar >= 0xD800 && theChar <= 0xDFFF) || theChar > 0x10FFFF) {
            utf8DecodeResult = -utf8DecodeResult;
            break;
        }
        p += utf8DecodeResult;
        len -= utf8DecodeResult;
    }

    if (p > datap) {
        // If some characters were successfully decoded, just return them
        // and ignore the error or end of stream for now.
        *rmlen = p - datap;
        assert(p >= datap);
        result.type = VT100_STRING;
    } else {
        // Report error or waiting state.
        if (utf8DecodeResult == 0) {
            result.type = VT100_WAIT;
        } else {
            *rmlen = -utf8DecodeResult;
            result.type = VT100_INVALID_SEQUENCE;
        }
    }
    return result;
}


static VT100TCC decode_euccn(unsigned char *datap,
                             int datalen,
                             int *rmlen)
{
    VT100TCC result;
    unsigned char *p = datap;
    int len = datalen;


    while (len > 0) {
        if (iseuccn(*p)&&len>1) {
            if ((*(p+1) >= 0x40 &&
                 *(p+1) <= 0x7e) ||
                (*(p+1) >= 0x80 &&
                 *(p+1) <= 0xfe)) {
                p += 2;
                len -= 2;
            }
            else {
                *p = ONECHAR_UNKNOWN;
                p++;
                len--;
            }
        }
        else break;
    }
    if (len == datalen) {
        *rmlen = 0;
        result.type = VT100_WAIT;
    }
    else {
        *rmlen = datalen - len;
        result.type = VT100_STRING;
    }

    return result;
}

static VT100TCC decode_big5(unsigned char *datap,
                            int datalen,
                            int *rmlen)
{
    VT100TCC result;
    unsigned char *p = datap;
    int len = datalen;

    while (len > 0) {
        if (isbig5(*p)&&len>1) {
            if ((*(p+1) >= 0x40 &&
                 *(p+1) <= 0x7e) ||
                (*(p+1) >= 0xa1 &&
                 *(p+1)<=0xfe)) {
                p += 2;
                len -= 2;
            }
            else {
                *p = ONECHAR_UNKNOWN;
                p++;
                len--;
            }
        }
        else break;
    }
    if (len == datalen) {
        *rmlen = 0;
        result.type = VT100_WAIT;
    }
    else {
        *rmlen = datalen - len;
        result.type = VT100_STRING;
    }

    return result;
}

static VT100TCC decode_euc_jp(unsigned char *datap,
                              int datalen ,
                              int *rmlen)
{
    VT100TCC result;
    unsigned char *p = datap;
    int len = datalen;

    while (len > 0) {
        if  (len > 1 && *p == 0x8e) {
            p += 2;
            len -= 2;
        }
        else if (len > 2  && *p == 0x8f ) {
            p += 3;
            len -= 3;
        }
        else if (len > 1 && *p >= 0xa1 && *p <= 0xfe ) {
            p += 2;
            len -= 2;
        }
        else break;
    }
    if (len == datalen) {
        *rmlen = 0;
        result.type = VT100_WAIT;
    }
    else {
        *rmlen = datalen - len;
        result.type = VT100_STRING;
    }

    return result;
}


static VT100TCC decode_sjis(unsigned char *datap,
                            int datalen ,
                            int *rmlen)
{
    VT100TCC result;
    unsigned char *p = datap;
    int len = datalen;

    while (len > 0) {
        if (issjiskanji(*p)&&len>1) {
            p += 2;
            len -= 2;
        }
        else if (*p>=0x80) {
            p++;
            len--;
        }
        else break;
    }

    if (len == datalen) {
        *rmlen = 0;
        result.type = VT100_WAIT;
    }
    else {
        *rmlen = datalen - len;
        result.type = VT100_STRING;
    }

    return result;
}


static VT100TCC decode_euckr(unsigned char *datap,
                             int datalen,
                             int *rmlen)
{
    VT100TCC result;
    unsigned char *p = datap;
    int len = datalen;

    while (len > 0) {
        if (iseuckr(*p)&&len>1) {
            p += 2;
            len -= 2;
        }
        else break;
    }
    if (len == datalen) {
        *rmlen = 0;
        result.type = VT100_WAIT;
    }
    else {
        *rmlen = datalen - len;
        result.type = VT100_STRING;
    }

    return result;
}

static VT100TCC decode_other_enc(unsigned char *datap,
                                 int datalen,
                                 int *rmlen)
{
    VT100TCC result;
    unsigned char *p = datap;
    int len = datalen;

    while (len > 0) {
        if (*p>=0x80) {
            p++;
            len--;
        }
        else break;
    }
    if (len == datalen) {
        *rmlen = 0;
        result.type = VT100_WAIT;
    }
    else {
        *rmlen = datalen - len;
        result.type = VT100_STRING;
    }

    return result;
}

static VT100TCC decode_ascii_string(unsigned char *datap,
                                 int datalen,
                                 int *rmlen)
{
    VT100TCC result;
    unsigned char *p = datap;
    int len = datalen;

    while (len > 0) {
        if (*p >= 0x20 && *p <= 0x7f) {
            p++;
            len--;
        } else {
          break;
        }
    }
    if (len == datalen) {
        *rmlen = 0;
        result.type = VT100_WAIT;
    } else {
        *rmlen = datalen - len;
        assert(datalen >= len);
        result.type = VT100_ASCIISTRING;
    }

    result.u.string =[[[NSString alloc]
                                   initWithBytes:datap
                                          length:*rmlen
                                        encoding:NSASCIIStringEncoding]
        autorelease];

    if (result.u.string==nil) {
        *rmlen = 0;
        result.type = VT100_UNKNOWNCHAR;
        result.u.code = datap[0];
    }


    return result;
}

// The datap buffer must be two bytes larger than *lenPtr.
// Returns a string or nil if the array is not well formed UTF-8.
static NSString* SetReplacementCharInArray(unsigned char* datap, int* lenPtr, int badIndex)
{
    // Example: "q?x" with badIndex==1.
    // 01234
    // q?x
    memmove(datap + badIndex + 3, datap + badIndex + 1, *lenPtr - badIndex - 1);
    // 01234
    // q?  x
    const char kUtf8Replacement[] = { 0xEF, 0xBF, 0xBD };
    memmove(datap + badIndex, kUtf8Replacement, 3);
    // q###x
    *lenPtr += 2;
    return [[[NSString alloc] initWithBytes:datap
                                     length:*lenPtr
                                   encoding:NSUTF8StringEncoding] autorelease];
}

static VT100TCC decode_string(unsigned char *datap,
                              int datalen,
                              int *rmlen,
                              NSStringEncoding encoding)
{
    VT100TCC result;

    *rmlen = 0;
    result.type = VT100_UNKNOWNCHAR;
    result.u.code = datap[0];

    //    NSLog(@"data: %@",[NSData dataWithBytes:datap length:datalen]);
    if (encoding == NSUTF8StringEncoding) {
        result = decode_utf8(datap, datalen, rmlen);
    }
    else if (isGBEncoding(encoding)) {
        //        NSLog(@"Chinese-GB!");
        result = decode_euccn(datap, datalen, rmlen);
    }
    else if (isBig5Encoding(encoding)) {
        result = decode_big5(datap, datalen, rmlen);
    }
    else if (isJPEncoding(encoding)) {
        //        NSLog(@"decoding euc-jp");
        result = decode_euc_jp(datap, datalen, rmlen);
    }
    else if (isSJISEncoding(encoding)) {
        //        NSLog(@"decoding j-jis");
        result = decode_sjis(datap, datalen, rmlen);
    }
    else if (isKREncoding(encoding)) {
        //        NSLog(@"decoding korean");
        result = decode_euckr(datap, datalen, rmlen);
    }
    else {
        //        NSLog(@"%s(%d):decode_string()-support character encoding(%@d)",
        //              __FILE__, __LINE__, [NSString localizedNameOfStringEncoding:encoding]);
        result = decode_other_enc(datap, datalen, rmlen);
    }

    if (result.type == VT100_INVALID_SEQUENCE) {
        // Output only one replacement symbol, even if rmlen is higher.
        datap[0] = ONECHAR_UNKNOWN;
        result.u.string = ReplacementString();
        result.type = VT100_STRING;
    } else if (result.type != VT100_WAIT) {
        /*data = [NSData dataWithBytes:datap length:*rmlen];
        result.u.string = [[[NSString alloc]
                                   initWithData:data
                                       encoding:encoding]
            autorelease]; */
        result.u.string =[[[NSString alloc]
                                   initWithBytes:datap
                                          length:*rmlen
                                       encoding:encoding]
            autorelease];

        if (result.u.string == nil) {
            int i;
            if (encoding == NSUTF8StringEncoding) {
                unsigned char temp[*rmlen * 3];
                memcpy(temp, datap, *rmlen);
                int length = *rmlen;
                for (i = *rmlen - 1; i >= 0 && !result.u.string; i--) {
                    result.u.string = SetReplacementCharInArray(temp, &length, i);
                }
            } else {
                for (i = *rmlen - 1; i >= 0 && !result.u.string; i--) {
                    datap[i] = ONECHAR_UNKNOWN;
                    result.u.string = [[[NSString alloc] initWithBytes:datap length:*rmlen encoding:encoding] autorelease];
                }
            }
        }
    }
    return result;
}

+ (void)initialize
{
}

- (id)init
{

#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif
    int i;

    self = [super init];
    if (self) {
        ENCODING = NSASCIIStringEncoding;
        total_stream_length = STANDARD_STREAM_SIZE;
        STREAM = malloc(total_stream_length);
        current_stream_length = 0;

        termType = nil;
        for(i = 0; i < TERMINFO_KEYS; i ++) {
            key_strings[i]=NULL;
        }


        LINE_MODE = NO;
        CURSOR_MODE = NO;
        COLUMN_MODE = NO;
        SCROLL_MODE = NO;
        SCREEN_MODE = NO;
        ORIGIN_MODE = NO;
        WRAPAROUND_MODE = YES;
        AUTOREPEAT_MODE = NO;
        INTERLACE_MODE = NO;
        KEYPAD_MODE = NO;
        INSERT_MODE = NO;
        saveCHARSET=CHARSET = NO;
        XON = YES;
        bold = italic = blink = reversed = under = NO;
        saveBold = saveItalic = saveBlink = saveReversed = saveUnder = NO;
        FG_COLORCODE = ALTSEM_FG_DEFAULT;
        alternateForegroundSemantics = YES;
        BG_COLORCODE = ALTSEM_BG_DEFAULT;
        alternateBackgroundSemantics = YES;
        saveForeground = FG_COLORCODE;
        saveAltForeground = alternateForegroundSemantics;
        saveBackground = BG_COLORCODE;
        saveAltBackground = alternateBackgroundSemantics;
        MOUSE_MODE = MOUSE_REPORTING_NONE;
        MOUSE_FORMAT = MOUSE_FORMAT_XTERM;

        TRACE = NO;

        strictAnsiMode = NO;
        allowColumnMode = NO;
        allowKeypadMode = YES;

        streamOffset = 0;

        numLock = YES;
    }
    return self;
}

- (void)dealloc
{
#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif

    free(STREAM);
    [termType release];

    int i;
    for(i = 0; i < TERMINFO_KEYS; i ++) {
        if (key_strings[i]) {
            free(key_strings[i]);
        }
        key_strings[i] = NULL;
    }

    [super dealloc];
#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x, done", __PRETTY_FUNCTION__, self);
#endif
}

- (NSString *)termtype
{
    return termType;
}

- (void)setTermType:(NSString *)termtype
{
    if (termType) {
        [termType autorelease];
    }
    termType = [termtype retain];

    allowKeypadMode = [termType rangeOfString:@"xterm"].location != NSNotFound;

    int i;
    int r;

    setupterm((char *)[termtype UTF8String], fileno(stdout), &r);

    if (r != 1) {
        NSLog(@"Terminal type %s is not defined.\n",[termtype UTF8String]);
        for (i = 0; i < TERMINFO_KEYS; i ++) {
            if (key_strings[i]) {
                free(key_strings[i]);
            }
            key_strings[i] = NULL;
        }
    } else {
        char *key_names[] = {
            key_left, key_right, key_up, key_down,
            key_home, key_end, key_npage, key_ppage,
            key_f0, key_f1, key_f2, key_f3, key_f4,
            key_f5, key_f6, key_f7, key_f8, key_f9,
            key_f10, key_f11, key_f12, key_f13, key_f14,
            key_f15, key_f16, key_f17, key_f18, key_f19,
            key_f20, key_f21, key_f22, key_f23, key_f24,
            key_f25, key_f26, key_f27, key_f28, key_f29,
            key_f30, key_f31, key_f32, key_f33, key_f34,
            key_f35,
            key_backspace, key_btab,
            tab,
            key_dc, key_ic,
            key_help,
        };

        for (i = 0; i < TERMINFO_KEYS; i ++) {
            if (key_strings[i]) {
                free(key_strings[i]);
            }
            key_strings[i] = key_names[i] ? strdup(key_names[i]) : NULL;
        }
    }

    IS_ANSI = [termType rangeOfString:@"ANSI"
                              options:NSCaseInsensitiveSearch | NSAnchoredSearch ].location != NSNotFound;
}

- (void)saveCursorAttributes
{
    saveBold = bold;
    saveItalic = italic;
    saveUnder = under;
    saveBlink = blink;
    saveReversed = reversed;
    saveCHARSET = CHARSET;
    saveForeground = FG_COLORCODE;
    saveAltForeground = alternateForegroundSemantics;
    saveBackground = BG_COLORCODE;
    saveAltBackground = alternateBackgroundSemantics;
}

- (void)restoreCursorAttributes
{
    bold=saveBold;
    italic=saveItalic;
    under=saveUnder;
    blink=saveBlink;
    reversed=saveReversed;
    CHARSET=saveCHARSET;
    FG_COLORCODE = saveForeground;
    alternateForegroundSemantics = saveAltForeground;
    BG_COLORCODE = saveBackground;
    alternateBackgroundSemantics = saveAltBackground;
}

- (void)setForegroundColor:(int)fgColorCode alternateSemantics:(BOOL)altsem
{
    FG_COLORCODE = fgColorCode;
    alternateForegroundSemantics = altsem;
}

- (void)setBackgroundColor:(int)bgColorCode alternateSemantics:(BOOL)altsem
{
    BG_COLORCODE = bgColorCode;
    alternateBackgroundSemantics = altsem;
}

- (void)reset
{
    LINE_MODE = NO;
    CURSOR_MODE = NO;
    COLUMN_MODE = NO;
    SCROLL_MODE = NO;
    SCREEN_MODE = NO;
    ORIGIN_MODE = NO;
    WRAPAROUND_MODE = YES;
    AUTOREPEAT_MODE = NO;
    INTERLACE_MODE = NO;
    KEYPAD_MODE = NO;
    INSERT_MODE = NO;
    saveCHARSET=CHARSET = NO;
    XON = YES;
    bold = italic = blink = reversed = under = NO;
    saveBold = saveItalic = saveBlink = saveReversed = saveUnder = NO;
    FG_COLORCODE = ALTSEM_FG_DEFAULT;
    alternateForegroundSemantics = YES;
    BG_COLORCODE = ALTSEM_BG_DEFAULT;
    alternateBackgroundSemantics = YES;
    MOUSE_MODE = MOUSE_REPORTING_NONE;
    MOUSE_FORMAT = MOUSE_FORMAT_XTERM;
    [SCREEN mouseModeDidChange:MOUSE_MODE];
    REPORT_FOCUS = NO;

    TRACE = NO;

    strictAnsiMode = NO;
    allowColumnMode = NO;
    [SCREEN reset];
}

- (BOOL)trace
{
    return TRACE;
}

- (void)setTrace:(BOOL)flag
{
    TRACE = flag;
}

- (BOOL)strictAnsiMode
{
    return (strictAnsiMode);
}

- (void)setStrictAnsiMode: (BOOL)flag
{
    strictAnsiMode = flag;
}

- (BOOL)allowColumnMode
{
    return (allowColumnMode);
}

- (void)setAllowColumnMode: (BOOL)flag
{
    allowColumnMode = flag;
}

- (NSStringEncoding)encoding
{
    return ENCODING;
}

- (void)setEncoding:(NSStringEncoding)encoding
{
    ENCODING = encoding;
}

- (void)cleanStream
{
    current_stream_length = 0;
}

- (void)putStreamData:(NSData*)data
{
    if (current_stream_length + [data length] > total_stream_length) {
        int n = ([data length] + current_stream_length) / STANDARD_STREAM_SIZE;

        total_stream_length += n*STANDARD_STREAM_SIZE;
        STREAM = reallocf(STREAM, total_stream_length);
    }

    memcpy(STREAM + current_stream_length, [data bytes], [data length]);
    current_stream_length += [data length];
    assert(current_stream_length >= 0);
    if (current_stream_length == 0) {
        streamOffset = 0;
	}
}

- (NSData *)streamData
{
    return [NSData dataWithBytes:STREAM + streamOffset
                          length:current_stream_length - streamOffset];
}

- (void)clearStream
{
    streamOffset = current_stream_length;
    assert(streamOffset >= 0);
}

- (VT100TCC)getNextToken
{
    unsigned char *datap;
    int datalen;
    VT100TCC result;

#if 0
    NSLog(@"buffer data = %s", STREAM);
#endif

    // get our current position in the stream
    datap = STREAM + streamOffset;
    datalen = current_stream_length - streamOffset;

    if (datalen == 0) {
        result.type = VT100CC_NULL;
        result.length = 0;
        streamOffset = 0;
        current_stream_length = 0;

        if (total_stream_length >= STANDARD_STREAM_SIZE * 2) {
            // We are done with this stream. Get rid of it and allocate a new one
            // to avoid allowing this to grow too big.
            free(STREAM);
            total_stream_length = STANDARD_STREAM_SIZE;
            STREAM = malloc(total_stream_length);
        }
    } else {
        int rmlen = 0;
        if (*datap >= 0x20 && *datap <= 0x7f) {
            result = decode_ascii_string(datap, datalen, &rmlen);
            result.length = rmlen;
            result.position = datap;
        } else if (iscontrol(datap[0])) {
            result = decode_control(datap, datalen, &rmlen, ENCODING, SCREEN, useCanonicalParser);
            result.length = rmlen;
            result.position = datap;
            [self _setMode:result];
            [self _setCharAttr:result];
            [self _setRGB:result];
        } else {
            if (isString(datap, ENCODING)) {
                // If the encoding is UTF-8 then you get here only if *datap >= 0x80.
                result = decode_string(datap, datalen, &rmlen, ENCODING);
                if (result.type != VT100_WAIT && rmlen == 0) {
                    result.type = VT100_UNKNOWNCHAR;
                    result.u.code = datap[0];
                    rmlen = 1;
                }
            } else {
                // If the encoding is UTF-8 you shouldn't get here.
                result.type = VT100_UNKNOWNCHAR;
                result.u.code = datap[0];
                rmlen = 1;
            }
            result.length = rmlen;
            result.position = datap;
        }


        if (rmlen > 0) {
            NSParameterAssert(current_stream_length >= streamOffset + rmlen);
            if (TRACE && result.type == VT100_UNKNOWNCHAR) {
                //      NSLog(@"INPUT-BUFFER %@, read %d byte, type %d",
                //                      STREAM, rmlen, result.type);
            }
            // mark our current position in the stream
            streamOffset += rmlen;
            assert(streamOffset >= 0);
        }
    }

    if (gDebugLogging) {
        char* hexdigits = "0123456789abcdef";
        int i;
        char loginfo[1000];
        int o = 0;
        for (i = 0; i < result.length && i < 20; ++i) {
            unsigned char c = datap[i];
            if (c < 32) {
                loginfo[o++] = '^';
                loginfo[o++] = datap[i] + '@';
            } else if (c == 32) {
                loginfo[o++] = 'S';
                loginfo[o++] = 'P';
            } else if (c < 128) {
                loginfo[o++] = c;
            } else {
                loginfo[o++] = '0';
                loginfo[o++] = 'x';
                loginfo[o++] = hexdigits[(c/16)];
                loginfo[o++] = hexdigits[c & 0x0f];
            }
            loginfo[o++] = ' ';
        }
        loginfo[o] = 0;
        if (i < result.length) {
            DebugLog([NSString stringWithFormat:@"Read %d bytes (%d shown): %s", result.length, i, loginfo]);
        } else {
            DebugLog([NSString stringWithFormat:@"Read %d bytes: %s", result.length, loginfo]);
        }
    }

    return result;
}

- (NSData *)specialKey:(int)terminfo cursorMod:(char*)cursorMod cursorSet:(char*)cursorSet cursorReset:(char*)cursorReset modflag:(unsigned int)modflag
{
    NSData* prefix = nil;
    NSData* theSuffix;
    if (key_strings[terminfo] && !allowKeypadMode) {
        theSuffix = [NSData dataWithBytes:key_strings[terminfo]
                                   length:strlen(key_strings[terminfo])];
    } else {
        int mod=0;
        static char buf[20];
        static int modValues[] = {
            0, 2, 5, 6, 9, 10, 13, 14
        };
        int theIndex = 0;
        if (modflag & NSAlternateKeyMask) {
            theIndex |= 4;
        }
        if (modflag & NSControlKeyMask) {
            theIndex |= 2;
        }
        if (modflag & NSShiftKeyMask) {
            theIndex |= 1;
        }
        mod = modValues[theIndex];

        if (mod) {
            sprintf(buf, cursorMod, mod);
            theSuffix = [NSData dataWithBytes:buf length:strlen(buf)];
        } else {
            if (CURSOR_MODE) {
                theSuffix = [NSData dataWithBytes:cursorSet
                                           length:strlen(cursorSet)];
            } else {
                theSuffix = [NSData dataWithBytes:cursorReset
                                           length:strlen(cursorReset)];
            }
        }
    }
    NSMutableData* data = [[[NSMutableData alloc] init] autorelease];
    if (prefix) {
        [data appendData:prefix];
    }
    [data appendData:theSuffix];
    return data;
}

- (NSData *)keyArrowUp:(unsigned int)modflag
{
    return [self specialKey:TERMINFO_KEY_UP
                  cursorMod:CURSOR_MOD_UP
                  cursorSet:CURSOR_SET_UP
                cursorReset:CURSOR_RESET_UP
                    modflag:modflag];
}

- (NSData *)keyArrowDown:(unsigned int)modflag
{
    return [self specialKey:TERMINFO_KEY_DOWN
                  cursorMod:CURSOR_MOD_DOWN
                  cursorSet:CURSOR_SET_DOWN
                cursorReset:CURSOR_RESET_DOWN
                    modflag:modflag];
}

- (NSData *)keyArrowLeft:(unsigned int)modflag
{
    return [self specialKey:TERMINFO_KEY_LEFT
                  cursorMod:CURSOR_MOD_LEFT
                  cursorSet:CURSOR_SET_LEFT
                cursorReset:CURSOR_RESET_LEFT
                    modflag:modflag];
}

- (NSData *)keyArrowRight:(unsigned int)modflag
{
    return [self specialKey:TERMINFO_KEY_RIGHT
                  cursorMod:CURSOR_MOD_RIGHT
                  cursorSet:CURSOR_SET_RIGHT
                cursorReset:CURSOR_RESET_RIGHT
                    modflag:modflag];
}

- (NSData *)keyHome:(unsigned int)modflag
{
    return [self specialKey:TERMINFO_KEY_HOME
                  cursorMod:CURSOR_MOD_HOME
                  cursorSet:CURSOR_SET_HOME
                cursorReset:CURSOR_RESET_HOME
                    modflag:modflag];
}

- (NSData *)keyEnd:(unsigned int)modflag
{
    return [self specialKey:TERMINFO_KEY_END
                  cursorMod:CURSOR_MOD_END
                  cursorSet:CURSOR_SET_END
                cursorReset:CURSOR_RESET_END
                    modflag:modflag];
}

- (NSData *)keyInsert
{
    if (key_strings[TERMINFO_KEY_INS]) {
        return [NSData dataWithBytes:key_strings[TERMINFO_KEY_INS]
                              length:strlen(key_strings[TERMINFO_KEY_INS])];
    } else {
        return [NSData dataWithBytes:KEY_INSERT length:conststr_sizeof(KEY_INSERT)];
    }
}


- (NSData *)keyDelete
{
    if (key_strings[TERMINFO_KEY_DEL]) {
        return [NSData dataWithBytes:key_strings[TERMINFO_KEY_DEL]
                              length:strlen(key_strings[TERMINFO_KEY_DEL])];
    } else {
        return [NSData dataWithBytes:KEY_DEL length:conststr_sizeof(KEY_DEL)];
    }
}

- (NSData *)keyBackspace
{
    if (key_strings[TERMINFO_KEY_BACKSPACE]) {
        return [NSData dataWithBytes:key_strings[TERMINFO_KEY_BACKSPACE]
                              length:strlen(key_strings[TERMINFO_KEY_BACKSPACE])];
    } else {
        return [NSData dataWithBytes:KEY_BACKSPACE length:conststr_sizeof(KEY_BACKSPACE)];
    }
}

- (NSData *)keyPageUp:(unsigned int)modflag
{
    NSData* theSuffix;
    if (key_strings[TERMINFO_KEY_PAGEUP]) {
        theSuffix = [NSData dataWithBytes:key_strings[TERMINFO_KEY_PAGEUP]
                                   length:strlen(key_strings[TERMINFO_KEY_PAGEUP])];
    } else {
        theSuffix = [NSData dataWithBytes:KEY_PAGE_UP
                             length:conststr_sizeof(KEY_PAGE_UP)];
    }
    NSMutableData* data = [[[NSMutableData alloc] init] autorelease];
    if (modflag & NSAlternateKeyMask) {
        char esc = 27;
        [data appendData:[NSData dataWithBytes:&esc length:1]];
    }
    [data appendData:theSuffix];
    return data;
}

- (NSData *)keyPageDown:(unsigned int)modflag
{
    NSData* theSuffix;
    if (key_strings[TERMINFO_KEY_PAGEDOWN]) {
        theSuffix = [NSData dataWithBytes:key_strings[TERMINFO_KEY_PAGEDOWN]
                                   length:strlen(key_strings[TERMINFO_KEY_PAGEDOWN])];
    } else {
        theSuffix = [NSData dataWithBytes:KEY_PAGE_DOWN
                                   length:conststr_sizeof(KEY_PAGE_DOWN)];
    }
    NSMutableData* data = [[[NSMutableData alloc] init] autorelease];
    if (modflag & NSAlternateKeyMask) {
        char esc = 27;
        [data appendData:[NSData dataWithBytes:&esc length:1]];
    }
    [data appendData:theSuffix];
    return data;
}

// Reference: http://www.utexas.edu/cc/faqs/unix/VT200-function-keys.html
// http://www.cs.utk.edu/~shuford/terminal/misc_old_terminals_news.txt
- (NSData *)keyFunction:(int)no
{
    char str[256];
    int len;

    if (no <= 5) {
        if (key_strings[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:key_strings[TERMINFO_KEY_F0+no]
                                  length:strlen(key_strings[TERMINFO_KEY_F0+no])];
        }
        else {
            sprintf(str, KEY_FUNCTION_FORMAT, no + 10);
        }
    }
    else if (no <= 10) {
        if (key_strings[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:key_strings[TERMINFO_KEY_F0+no]
                                  length:strlen(key_strings[TERMINFO_KEY_F0+no])];
        }
        else {
            sprintf(str, KEY_FUNCTION_FORMAT, no + 11);
        }
    }
    else if (no <= 14)
        if (key_strings[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:key_strings[TERMINFO_KEY_F0+no]
                                  length:strlen(key_strings[TERMINFO_KEY_F0+no])];
        }
        else {
            sprintf(str, KEY_FUNCTION_FORMAT, no + 12);
        }
    else if (no <= 16)
        if (key_strings[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:key_strings[TERMINFO_KEY_F0+no]
                                  length:strlen(key_strings[TERMINFO_KEY_F0+no])];
        }
        else {
            sprintf(str, KEY_FUNCTION_FORMAT, no + 13);
        }
    else if (no <= 20)
        if (key_strings[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:key_strings[TERMINFO_KEY_F0+no]
                                  length:strlen(key_strings[TERMINFO_KEY_F0+no])];
        }
        else {
            sprintf(str, KEY_FUNCTION_FORMAT, no + 14);
        }
    else if (no <=35)
        if (key_strings[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:key_strings[TERMINFO_KEY_F0+no]
                                  length:strlen(key_strings[TERMINFO_KEY_F0+no])];
        }
        else
            str[0] = 0;
    else
        str[0] = 0;

    len = strlen(str);
    return [NSData dataWithBytes:str length:len];
}

- (NSData*)keypadData:(unichar)unicode keystr:(NSString*)keystr
{
    NSData *theData = nil;

    // numeric keypad mode
    if (![self keypadMode]) {
        return ([keystr dataUsingEncoding:NSUTF8StringEncoding]);
    }
    // alternate keypad mode
    switch (unicode) {
        case '0':
            theData = [NSData dataWithBytes:ALT_KP_0 length:conststr_sizeof(ALT_KP_0)];
            break;
        case '1':
            theData = [NSData dataWithBytes:ALT_KP_1 length:conststr_sizeof(ALT_KP_1)];
            break;
        case '2':
            theData = [NSData dataWithBytes:ALT_KP_2 length:conststr_sizeof(ALT_KP_2)];
            break;
        case '3':
            theData = [NSData dataWithBytes:ALT_KP_3 length:conststr_sizeof(ALT_KP_3)];
            break;
        case '4':
            theData = [NSData dataWithBytes:ALT_KP_4 length:conststr_sizeof(ALT_KP_4)];
            break;
        case '5':
            theData = [NSData dataWithBytes:ALT_KP_5 length:conststr_sizeof(ALT_KP_5)];
            break;
        case '6':
            theData = [NSData dataWithBytes:ALT_KP_6 length:conststr_sizeof(ALT_KP_6)];
            break;
        case '7':
            theData = [NSData dataWithBytes:ALT_KP_7 length:conststr_sizeof(ALT_KP_7)];
            break;
        case '8':
            theData = [NSData dataWithBytes:ALT_KP_8 length:conststr_sizeof(ALT_KP_8)];
            break;
        case '9':
            theData = [NSData dataWithBytes:ALT_KP_9 length:conststr_sizeof(ALT_KP_9)];
            break;
        case '-':
            theData = [NSData dataWithBytes:ALT_KP_MINUS length:conststr_sizeof(ALT_KP_MINUS)];
            break;
        case '+':
            theData = [NSData dataWithBytes:ALT_KP_PLUS length:conststr_sizeof(ALT_KP_PLUS)];
            break;
        case '.':
            theData = [NSData dataWithBytes:ALT_KP_PERIOD length:conststr_sizeof(ALT_KP_PERIOD)];
            break;
        case '/':
            theData = [NSData dataWithBytes:ALT_KP_SLASH length:conststr_sizeof(ALT_KP_SLASH)];
            break;
        case '*':
            theData = [NSData dataWithBytes:ALT_KP_STAR length:conststr_sizeof(ALT_KP_STAR)];
            break;
        case '=':
            theData = [NSData dataWithBytes:ALT_KP_EQUALS length:conststr_sizeof(ALT_KP_EQUALS)];
            break;
        case 0x03:
            theData = [NSData dataWithBytes:ALT_KP_ENTER length:conststr_sizeof(ALT_KP_ENTER)];
            break;
        default:
            theData = [keystr dataUsingEncoding:NSUTF8StringEncoding];
            break;
    }

    return (theData);
}

- (char *)mouseReport:(int)button atX:(int)x Y:(int)y
{
    static char buf[64]; // This should be enough for all formats.
    switch (MOUSE_FORMAT) {
        case MOUSE_FORMAT_XTERM_EXT:
            snprintf(buf, sizeof(buf), "\033[M%c%lc%lc",
                     (wint_t) (32 + button),
                     (wint_t) (32 + x),
                     (wint_t) (32 + y));
            break;
        case MOUSE_FORMAT_URXVT:
            snprintf(buf, sizeof(buf), "\033[%d;%d;%dM", 32 + button, x, y);
            break;
        case MOUSE_FORMAT_SGR:
            if (button & MOUSE_BUTTON_SGR_RELEASE_FLAG) {
                // for mouse release event
                snprintf(buf, sizeof(buf), "\033[<%d;%d;%dm",
                         button ^ MOUSE_BUTTON_SGR_RELEASE_FLAG,
                         x,
                         y);
            } else {
                // for mouse press/motion event
                snprintf(buf, sizeof(buf), "\033[<%d;%d;%dM", button, x, y);
            }
            break;
        case MOUSE_FORMAT_XTERM:
        default:
            snprintf(buf, sizeof(buf), "\033[M%c%c%c", 32 + button, 32 + x, 32 + y);
            break;
    }
    return buf;
}

- (NSData *)mousePress:(int)button withModifiers:(unsigned int)modflag atX:(int)x Y:(int)y
{
    int cb;

    cb = button;
    if (button == MOUSE_BUTTON_SCROLLDOWN || button == MOUSE_BUTTON_SCROLLUP) {
        // convert x11 scroll button number to terminal button code
        const int offset = MOUSE_BUTTON_SCROLLDOWN;
        cb -= offset;
        cb |= MOUSE_BUTTON_SCROLL_FLAG;
    }
    if (modflag & NSControlKeyMask) {
        cb |= MOUSE_BUTTON_CTRL_FLAG;
    }
    if (modflag & NSShiftKeyMask) {
        cb |= MOUSE_BUTTON_SHIFT_FLAG;
    }
    if (modflag & NSAlternateKeyMask) {
        cb |= MOUSE_BUTTON_META_FLAG;
    }
    char *buf = [self mouseReport:cb atX:(x + 1) Y:(y + 1)];

    return [NSData dataWithBytes: buf length: strlen(buf)];
}

- (NSData *)mouseRelease:(int)button withModifiers:(unsigned int)modflag atX:(int)x Y:(int)y
{
    int cb;

    if (MOUSE_FORMAT == MOUSE_FORMAT_SGR) {
        // for SGR 1006 mode
        cb = button | MOUSE_BUTTON_SGR_RELEASE_FLAG;
    } else {
        // for 1000/1005/1015 mode
        cb = 3;
    }

    if (modflag & NSControlKeyMask) {
        cb |= MOUSE_BUTTON_CTRL_FLAG;
    }
    if (modflag & NSShiftKeyMask) {
        cb |= MOUSE_BUTTON_SHIFT_FLAG;
    }
    if (modflag & NSAlternateKeyMask) {
        cb |= MOUSE_BUTTON_META_FLAG;
    }
    char *buf = [self mouseReport:cb atX:(x + 1) Y:(y + 1)];

    return [NSData dataWithBytes: buf length: strlen(buf)];
}

- (NSData *)mouseMotion:(int)button withModifiers:(unsigned int)modflag atX:(int)x Y:(int)y
{
    int cb;

    if (button == MOUSE_BUTTON_NONE) {
        cb = button;
    } else {
        cb = button % 3;
    }
    if (button > 3) {
        cb |= MOUSE_BUTTON_SCROLL_FLAG;
    }
    if (modflag & NSControlKeyMask) {
        cb |= MOUSE_BUTTON_CTRL_FLAG;
    }
    if (modflag & NSShiftKeyMask) {
        cb |= MOUSE_BUTTON_SHIFT_FLAG;
    }
    if (modflag & NSAlternateKeyMask) {
        cb |= MOUSE_BUTTON_META_FLAG;
    }
    char *buf = [self mouseReport:(32 + cb) atX:(x + 1) Y:(y + 1)];

    return [NSData dataWithBytes: buf length: strlen(buf)];
}

- (BOOL)reportFocus
{
    return REPORT_FOCUS;
}

- (BOOL)lineMode
{
    return LINE_MODE;
}

- (BOOL)cursorMode
{
    return CURSOR_MODE;
}

- (BOOL)columnMode
{
    return COLUMN_MODE;
}

- (BOOL)scrollMode
{
    return SCROLL_MODE;
}

- (BOOL)screenMode
{
    return SCREEN_MODE;
}

- (BOOL)originMode
{
    return ORIGIN_MODE;
}

- (BOOL)wraparoundMode
{
    return WRAPAROUND_MODE;
}

- (BOOL)isAnsi
{
    return IS_ANSI;
}


- (BOOL)autorepeatMode
{
    return AUTOREPEAT_MODE;
}

- (BOOL)interlaceMode
{
    return INTERLACE_MODE;
}

- (BOOL)keypadMode
{
    return KEYPAD_MODE;
}

- (void)setKeypadMode:(BOOL)mode
{
    KEYPAD_MODE = mode;
}

- (BOOL)insertMode
{
    return INSERT_MODE;
}

- (BOOL) xon
{
    return XON;
}

- (int) charset
{
    return CHARSET;
}

- (MouseMode)mouseMode
{
    return MOUSE_MODE;
}

- (screen_char_t)foregroundColorCode
{
    screen_char_t result = { 0 };
    if (reversed) {
        result.foregroundColor = BG_COLORCODE;
        result.alternateForegroundSemantics = alternateBackgroundSemantics;
    } else {
        result.foregroundColor = FG_COLORCODE;
        result.alternateForegroundSemantics = alternateForegroundSemantics;
    }
    result.bold = bold;
    result.italic = italic;
    result.underline = under;
    result.blink = blink;
    return result;
}

- (screen_char_t)backgroundColorCode
{
    screen_char_t result = { 0 };
    if (reversed) {
        result.backgroundColor = FG_COLORCODE;
        result.alternateBackgroundSemantics = alternateForegroundSemantics;
    } else {
        result.backgroundColor = BG_COLORCODE;
        result.alternateBackgroundSemantics = alternateBackgroundSemantics;
    }
    return result;
}

- (screen_char_t)foregroundColorCodeReal
{
    screen_char_t result = { 0 };
    result.foregroundColor = FG_COLORCODE;
    result.alternateForegroundSemantics = alternateForegroundSemantics;
    result.bold = bold;
    result.italic = italic;
    result.underline = under;
    result.blink = blink;
    return result;
}

- (screen_char_t)backgroundColorCodeReal
{
    screen_char_t result = { 0 };
    result.backgroundColor = BG_COLORCODE;
    result.alternateBackgroundSemantics = alternateBackgroundSemantics;
    return result;
}

- (NSData *)reportActivePositionWithX:(int)x Y:(int)y withQuestion:(BOOL)q
{
    char buf[64];

    snprintf(buf, sizeof(buf), q?REPORT_POSITION_Q:REPORT_POSITION, y, x);

    return [NSData dataWithBytes:buf length:strlen(buf)];
}

- (NSData *)reportStatus
{
    return [NSData dataWithBytes:REPORT_STATUS
                          length:conststr_sizeof(REPORT_STATUS)];
}

- (NSData *)reportDeviceAttribute
{
    return [NSData dataWithBytes:REPORT_WHATAREYOU
                          length:conststr_sizeof(REPORT_WHATAREYOU)];
}

- (NSData *)reportSecondaryDeviceAttribute
{
    return [NSData dataWithBytes:REPORT_SDA
                          length:conststr_sizeof(REPORT_SDA)];
}

- (void)setInsertMode:(BOOL)mode
{
    INSERT_MODE = mode;
}

- (void)setCursorMode:(BOOL)mode
{
    CURSOR_MODE = mode;
}

- (void)_setMode:(VT100TCC)token
{
    BOOL mode;

    switch (token.type) {
        case VT100CSI_DECSET:
        case VT100CSI_DECRST:
            mode=(token.type == VT100CSI_DECSET);

            switch (token.u.csi.p[0]) {
                case 20: LINE_MODE = mode; break;
                case 1:  [self setCursorMode:mode]; break;
                case 2:  ANSI_MODE = mode; break;
                case 3:  COLUMN_MODE = mode; break;
                case 4:  SCROLL_MODE = mode; break;
                case 5:  SCREEN_MODE = mode; [SCREEN setDirty]; break;
                case 6:  ORIGIN_MODE = mode; break;
                case 7:  WRAPAROUND_MODE = mode; break;
                case 8:  AUTOREPEAT_MODE = mode; break;
                case 9:  INTERLACE_MODE  = mode; break;
                case 25: [SCREEN showCursor: mode]; break;
                case 40: allowColumnMode = mode; break;

                case 1049:
                    // From the xterm release log:
                    // Implement new escape sequence, private mode 1049, which combines
                    // the switch to/from alternate screen mode with screen clearing and
                    // cursor save/restore.  Unlike the existing escape sequence, this
                    // clears the alternate screen when switching to it rather than when
                    // switching to the normal screen, thus retaining the alternate screen
                    // contents for select/paste operations.
                    if (!disableSmcupRmcup) {
                        if (mode) {
                            [self saveCursorAttributes];
                            [SCREEN saveCursorPosition];
                            [SCREEN saveBuffer];
                            [SCREEN clearScreen];
                        } else {
                            [SCREEN restoreBuffer];
                            [self restoreCursorAttributes];
                            [SCREEN restoreCursorPosition];
                        }
                    }
                    break;

                case 2004:
                    // Set bracketed paste mode
                    bracketedPasteMode_ = mode;
                    break;

                case 47:
                    // alternate screen buffer mode
                    if (!disableSmcupRmcup) {
                        if (mode) {
                            [SCREEN saveBuffer];
                        } else {
                            [SCREEN restoreBuffer];
                        }
                    }
                    break;

                case 1000:
                /* case 1001: */ /* MOUSE_REPORTING_HILITE not implemented yet */
                case 1002:
                case 1003:
                    if (mode) {
                        MOUSE_MODE = token.u.csi.p[0] - 1000;
                    } else {
                        MOUSE_MODE = MOUSE_REPORTING_NONE;
                    }
                    [SCREEN mouseModeDidChange:MOUSE_MODE];
                    break;
                case 1004:
                    REPORT_FOCUS = mode;
                    break;

                case 1005:
                    if (mode) {
                        MOUSE_FORMAT = MOUSE_FORMAT_XTERM_EXT;
                    } else {
                        MOUSE_FORMAT = MOUSE_FORMAT_XTERM;
                    }
                    break;


                case 1006:
                    if (mode) {
                        MOUSE_FORMAT = MOUSE_FORMAT_SGR;
                    } else {
                        MOUSE_FORMAT = MOUSE_FORMAT_XTERM;
                    }
                    break;

                case 1015:
                    if (mode) {
                        MOUSE_FORMAT = MOUSE_FORMAT_URXVT;
                    } else {
                        MOUSE_FORMAT = MOUSE_FORMAT_XTERM;
                    }
                    break;
            }
                break;
        case VT100CSI_SM:
        case VT100CSI_RM:
            mode=(token.type == VT100CSI_SM);

            switch (token.u.csi.p[0]) {
                case 4:
                    [self setInsertMode:mode]; break;
            }
                break;
        case VT100CSI_DECKPAM:
            [self setKeypadMode:YES];
            break;
        case VT100CSI_DECKPNM:
            [self setKeypadMode:NO];
            break;
        case VT100CC_SI:
            CHARSET = 0;
            break;
        case VT100CC_SO:
            CHARSET = 1;
            break;
        case VT100CC_DC1:
            XON = YES;
            break;
        case VT100CC_DC3:
            XON = NO;
            break;
        case VT100CSI_DECRC:
            [self restoreCursorAttributes];
            break;
        case VT100CSI_DECSC:
            [self saveCursorAttributes];
            break;
        case VT100CSI_DECSTR:
            WRAPAROUND_MODE = YES;
            ORIGIN_MODE = NO;
            break;
        case VT100CSI_RESET_MODIFIERS:
            if (token.u.csi.count == 0) {
                sendModifiers_[2] = -1;
            } else {
                int resource = token.u.csi.p[0];
                if (resource >= 0 && resource <= NUM_MODIFIABLE_RESOURCES) {
                    sendModifiers_[resource] = -1;
                }
            }
            [SCREEN setSendModifiers:sendModifiers_
                           numValues:NUM_MODIFIABLE_RESOURCES];
            break;

        case VT100CSI_SET_MODIFIERS: {
            if (token.u.csi.count == 0) {
                for (int i = 0; i < NUM_MODIFIABLE_RESOURCES; i++) {
                    sendModifiers_[i] = 0;
                }
            } else {
                int resource = token.u.csi.p[0];
                int value;
                if (token.u.csi.count == 1) {
                    value = 0;
                } else {
                    value = token.u.csi.p[1];
                }
                if (resource >= 0 && resource < NUM_MODIFIABLE_RESOURCES && value >= 0) {
                    sendModifiers_[resource] = value;
                }
            }
            [SCREEN setSendModifiers:sendModifiers_
                           numValues:NUM_MODIFIABLE_RESOURCES];
            break;
        }
    }
}

- (void)resetSGR {
    // all attributes off
    bold = italic = under = blink = reversed = NO;
    FG_COLORCODE = ALTSEM_FG_DEFAULT;
    alternateForegroundSemantics = YES;
    BG_COLORCODE = ALTSEM_BG_DEFAULT;
    alternateBackgroundSemantics = YES;
}

- (void)_setCharAttr:(VT100TCC)token
{
    if (token.type == VT100CSI_SGR) {
        if (token.u.csi.count == 0) {
            [self resetSGR];
        } else {
            int i;
            for (i = 0; i < token.u.csi.count; ++i) {
                int n = token.u.csi.p[i];
                switch (n) {
                    case VT100CHARATTR_ALLOFF:
                        // all attribute off
                        bold = italic = under = blink = reversed = NO;
                        FG_COLORCODE = ALTSEM_FG_DEFAULT;
                        alternateForegroundSemantics = YES;
                        BG_COLORCODE = ALTSEM_BG_DEFAULT;
                        alternateBackgroundSemantics = YES;
                        break;

                    case VT100CHARATTR_BOLD:
                        bold = YES;
                        break;
                    case VT100CHARATTR_NORMAL:
                        bold = NO;
                        break;
                    case VT100CHARATTR_ITALIC:
                        italic = YES;
                        break;
                    case VT100CHARATTR_NOT_ITALIC:
                        italic = NO;
                        break;
                    case VT100CHARATTR_UNDER:
                        under = YES;
                        break;
                    case VT100CHARATTR_NOT_UNDER:
                        under = NO;
                        break;
                    case VT100CHARATTR_BLINK:
                        blink = YES;
                        break;
                    case VT100CHARATTR_STEADY:
                        blink = NO;
                        break;
                    case VT100CHARATTR_REVERSE:
                        reversed = YES;
                        break;
                    case VT100CHARATTR_POSITIVE:
                        reversed = NO;
                        break;
                    case VT100CHARATTR_FG_DEFAULT:
                        FG_COLORCODE = ALTSEM_FG_DEFAULT;
                        alternateForegroundSemantics = YES;
                        break;
                    case VT100CHARATTR_BG_DEFAULT:
                        BG_COLORCODE = ALTSEM_BG_DEFAULT;
                        alternateBackgroundSemantics = YES;
                        break;
                    case VT100CHARATTR_FG_256:
                        if (token.u.csi.count - i >= 3 && token.u.csi.p[i + 1] == 5) {
                            FG_COLORCODE = token.u.csi.p[i + 2];
                            alternateForegroundSemantics = NO;
                            i += 2;
                        }
                        break;
                    case VT100CHARATTR_BG_256:
                        if (token.u.csi.count - i >= 3 && token.u.csi.p[i + 1] == 5) {
                            BG_COLORCODE = token.u.csi.p[i + 2];
                            alternateBackgroundSemantics = NO;
                            i += 2;
                        }
                        break;
                    default:
                        // 8 color support
                        if (n >= VT100CHARATTR_FG_BLACK &&
                            n <= VT100CHARATTR_FG_WHITE) {
                            FG_COLORCODE = n - VT100CHARATTR_FG_BASE - COLORCODE_BLACK;
                            alternateForegroundSemantics = NO;
                        } else if (n >= VT100CHARATTR_BG_BLACK &&
                                   n <= VT100CHARATTR_BG_WHITE) {
                            BG_COLORCODE = n - VT100CHARATTR_BG_BASE - COLORCODE_BLACK;
                            alternateBackgroundSemantics = NO;
                        }
                        // 16 color support
                        if (n >= VT100CHARATTR_FG_HI_BLACK &&
                            n <= VT100CHARATTR_FG_HI_WHITE) {
                            FG_COLORCODE = n - VT100CHARATTR_FG_HI_BASE - COLORCODE_BLACK + 8;
                            alternateForegroundSemantics = NO;
                        } else if (n >= VT100CHARATTR_BG_HI_BLACK &&
                                   n <= VT100CHARATTR_BG_HI_WHITE) {
                            BG_COLORCODE = n - VT100CHARATTR_BG_HI_BASE - COLORCODE_BLACK + 8;
                            alternateBackgroundSemantics = NO;
                        }
                }
            }
        }
    } else if (token.type == VT100CSI_DECSTR) {
        [self resetSGR];
    }
}


- (void)_setRGB:(VT100TCC)token
{
    if (token.type == XTERMCC_SET_RGB) {
        // The format of this command is "<index>;rgb:<redhex>/<greenhex>/<bluehex>", e.g. "105;rgb:00/cc/ff"
        // TODO(georgen): xterm has extended this quite a bit and we're behind. Catch up.
        const char *s = [token.u.string UTF8String];
        int theIndex = 0;
        while (isdigit(*s)) {
            theIndex = 10*theIndex + *s++ - '0';
        }
        if (*s++ != ';') {
            return;
        }
        if (*s++ != 'r') {
            return;
        }
        if (*s++ != 'g') {
            return;
        }
        if (*s++ != 'b') {
            return;
        }
        if (*s++ != ':') {
            return;
        }
        int r = 0, g = 0, b = 0;

        while (isxdigit(*s)) {
            r = 16*r + (*s>='a' ? *s++ - 'a' + 10 : *s>='A' ? *s++ - 'A' + 10 : *s++ - '0');
        }
        if (*s++ != '/') {
            return;
        }
        while (isxdigit(*s)) {
            g = 16*g + (*s>='a' ? *s++ - 'a' + 10 : *s>='A' ? *s++ - 'A' + 10 : *s++ - '0');
        }
        if (*s++ != '/') {
            return;
        }
        while (isxdigit(*s)) {
            b = 16*b + (*s>='a' ? *s++ - 'a' + 10 : *s>='A' ? *s++ - 'A' + 10 : *s++ - '0');
        }
        if (theIndex >= 0 && theIndex <= 255 &&
            r >= 0 && r <= 255 &&
            g >= 0 && g <= 255 &&
            b >= 0 && b <= 255) {
            [[SCREEN session] setColorTable:theIndex
                                              color:[NSColor colorWithCalibratedRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1]];
        }
    } else if (token.type == XTERMCC_SET_KVP) {
        // argument is of the form key=value
        // key: Sequence of characters not = or ^G
        // value: Sequence of characters not ^G
        NSString* argument = token.u.string;
        NSRange eqRange = [argument rangeOfString:@"="];
        NSString* key;
        NSString* value;
        if (eqRange.location != NSNotFound) {
            key = [argument substringToIndex:eqRange.location];;
            value = [argument substringFromIndex:eqRange.location+1];
        } else {
            key = argument;
            value = @"";
        }
        if ([key isEqualToString:@"CursorShape"]) {
            // Value must be an integer. Bogusly, non-numbers are treated as 0.
            int shape = [value intValue];
            int shapeMap[] = { CURSOR_BOX, CURSOR_VERTICAL, CURSOR_UNDERLINE };
            if (shape >= 0 && shape < sizeof(shapeMap)/sizeof(int)) {
                [[[SCREEN session] TEXTVIEW] setCursorType:shapeMap[shape]];
            }
        } else if ([key isEqualToString:@"SetMark"]) {
            [[SCREEN session] saveScrollPosition];
        } else if ([key isEqualToString:@"StealFocus"]) {
            [NSApp activateIgnoringOtherApps:YES];
            [[[SCREEN display] window] makeKeyAndOrderFront:nil];
        } else if ([key isEqualToString:@"ClearScrollback"]) {
            [SCREEN clearBuffer];
        } else if ([key isEqualToString:@"CurrentDir"]) {
            long long lineNumber = [SCREEN absoluteLineNumberOfCursor];
            [[[SCREEN session] TEXTVIEW] logWorkingDirectoryAtLine:lineNumber
                                                     withDirectory:value];
        } else if ([key isEqualToString:@"SetProfile"]) {
            Profile *newProfile;
            if ([value length]) {
                newProfile = [[ProfileModel sharedInstance] bookmarkWithName:value];
            } else {
                newProfile = [[ProfileModel sharedInstance] defaultBookmark];
            }
            if (newProfile) {
                NSString *name = [[[SCREEN session] addressBookEntry] objectForKey:KEY_NAME];
                NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:newProfile];
                [dict setObject:name forKey:KEY_NAME];
                [[SCREEN session] setAddressBookEntry:dict];
                [[SCREEN session] setPreferencesFromAddressBookEntry:dict];
                [[SCREEN session] remarry];
            }
        } else if ([key isEqualToString:@"CopyToClipboard"]) {
            if ([[PreferencePanel sharedInstance] allowClipboardAccess]) {
                if ([value isEqualToString:@"ruler"]) {
                    [[SCREEN session] setPasteboard:NSGeneralPboard];
                } else if ([value isEqualToString:@"find"]) {
                    [[SCREEN session] setPasteboard:NSFindPboard];
                } else if ([value isEqualToString:@"font"]) {
                    [[SCREEN session] setPasteboard:NSFontPboard];
                } else {
                    [[SCREEN session] setPasteboard:NSGeneralPboard];
                }
            } else {
                NSLog(@"Clipboard access denied for CopyToClipboard");
            }
        } else if ([key isEqualToString:@"EndCopy"]) {
            [[SCREEN session] setPasteboard:nil];
        } else if ([key isEqualToString:@"RequestAttention"]) {
            if ([value boolValue]) {
                shouldBounceDockIcon = [NSApp requestUserAttention:NSCriticalRequest];
            } else {
                [NSApp cancelUserAttentionRequest:shouldBounceDockIcon];
            }
        }
    } else if (token.type == XTERMCC_SET_PALETTE) {
        NSString* argument = token.u.string;
        if ([argument length] == 7) {
            int n, r, g, b;
            int count = 0;
            count += sscanf([[argument substringWithRange:NSMakeRange(0, 1)] UTF8String], "%x", &n);
            if (count == 0) {
                unichar c = [argument characterAtIndex:0];
                n = c - 'a' + 10;
                // fg = 16
                // bg = 17
                // bold = 18
                // selection = 19
                // selected text = 20
                // cursor = 21
                // cursor text = 22
                if (n >= 16 && n <= 22) {
                    ++count;
                }
            }
            count += sscanf([[argument substringWithRange:NSMakeRange(1, 2)] UTF8String], "%x", &r);
            count += sscanf([[argument substringWithRange:NSMakeRange(3, 2)] UTF8String], "%x", &g);
            count += sscanf([[argument substringWithRange:NSMakeRange(5, 2)] UTF8String], "%x", &b);
            if (count == 4 &&
                n >= 0 &&
                n <= 22 &&
                r >= 0 &&
                r <= 255 &&
                g >= 0 &&
                g <= 255 &&
                b >= 0 &&
                b <= 255) {
                NSColor* theColor = [NSColor colorWithCalibratedRed:((double)r)/255.0
                                                              green:((double)g)/255.0
                                                               blue:((double)b)/255.0
                                                              alpha:1];
                switch (n) {
                    case 16:
                        [[[SCREEN session] TEXTVIEW] setFGColor:theColor];
                        break;
                    case 17:
                        [[[SCREEN session] TEXTVIEW] setBGColor:theColor];
                        break;
                    case 18:
                        [[[SCREEN session] TEXTVIEW] setBoldColor:theColor];
                        break;
                    case 19:
                        [[[SCREEN session] TEXTVIEW] setSelectionColor:theColor];
                        break;
                    case 20:
                        [[[SCREEN session] TEXTVIEW] setSelectedTextColor:theColor];
                        break;
                    case 21:
                        [[[SCREEN session] TEXTVIEW] setCursorColor:theColor];
                        break;
                    case 22:
                        [[[SCREEN session] TEXTVIEW] setCursorTextColor:theColor];
                        break;
                    default:
                        [[[SCREEN session] TEXTVIEW] setColorTable:n color:theColor];
                        break;
                }
            }
        }
    } else if (token.type == XTERMCC_PROPRIETARY_ETERM_EXT) {
        NSString* argument = token.u.string;
        NSArray* parts = [argument componentsSeparatedByString:@";"];
        NSString* func = nil;
        if ([parts count] >= 1) {
            func = [parts objectAtIndex:0];
        }
        if (func) {
            if ([func isEqualToString:@"1"]) {
                // Adjusts a color modifier. This attempts to roughly follow the pattern that Eterm
                // estabilshed.
                //
                // ESC ] 6 ; 1 ; class ; color ; attribute ; value BEL
                //
                // Adjusts a color modifier.
                // class: determines which image class will have its color modifier altered:
                //   legal values: bg (background), or a number 0-15 (color palette entries).
                // color: The color component to modify.
                //   legal values: red, green, or blue.
                // attribute: how to modify it.
                //   legal values: brightness
                // value: the new value for this attribute.
                //   legal values: decimal integers in 0-255.
                if ([parts count] == 4) {
                    NSString* class = [parts objectAtIndex:1];
                    NSString* color = [parts objectAtIndex:2];
                    NSString* attribute = [parts objectAtIndex:3];
                    if ([class isEqualToString:@"bg"] &&
                        [color isEqualToString:@"*"] &&
                        [attribute isEqualToString:@"default"]) {

                        NSTabViewItem* tabViewItem = [[[SCREEN session] ptytab] tabViewItem];
                        id<WindowControllerInterface> term = [[[SCREEN session] ptytab] parentWindow];
                        [term setTabColor:nil forTabViewItem:tabViewItem];
                    }
                } else if ([parts count] == 5) {
                    NSString* class = [parts objectAtIndex:1];
                    NSString* color = [parts objectAtIndex:2];
                    NSString* attribute = [parts objectAtIndex:3];
                    NSString* value = [parts objectAtIndex:4];
                    if ([class isEqualToString:@"bg"] &&
                        [attribute isEqualToString:@"brightness"]) {
                        double numValue = MIN(1, ([value intValue] / 255.0));
                        if (numValue >= 0 && numValue <= 1) {
                            NSTabViewItem* tabViewItem = [[[SCREEN session] ptytab] tabViewItem];
                            id<WindowControllerInterface> term = [[[SCREEN session] ptytab] parentWindow];
                            NSColor* curColor = [term tabColorForTabViewItem:tabViewItem];
                            double red, green, blue;
                            red = [curColor redComponent];
                            green = [curColor greenComponent];
                            blue = [curColor blueComponent];
                            if ([color isEqualToString:@"red"]) {
                                [term setTabColor:[NSColor colorWithCalibratedRed:numValue
                                                                            green:green
                                                                             blue:blue
                                                                            alpha:1]
                                                                   forTabViewItem:tabViewItem];
                            } else if ([color isEqualToString:@"green"]) {
                                [term setTabColor:[NSColor colorWithCalibratedRed:red
                                                                            green:numValue
                                                                             blue:blue
                                                                            alpha:1]
                                                                   forTabViewItem:tabViewItem];
                            } else if ([color isEqualToString:@"blue"]) {
                                [term setTabColor:[NSColor colorWithCalibratedRed:red
                                                                            green:green
                                                                             blue:numValue
                                                                            alpha:1]
                                                                   forTabViewItem:tabViewItem];
                            }
                        }
                    }
                }
            }
        }
    }
}

- (void) setScreen:(VT100Screen*) sc
{
    SCREEN=sc;
}

- (void)setDisableSmcupRmcup:(BOOL)value
{
    disableSmcupRmcup = value;
}

- (void)setUseCanonicalParser:(BOOL)value
{
    useCanonicalParser = value;
}

- (BOOL)bracketedPasteMode
{
    return bracketedPasteMode_;
}

- (void)setMouseMode:(MouseMode)mode
{
    MOUSE_MODE = mode;
    [SCREEN mouseModeDidChange:MOUSE_MODE];
}

- (void)setMouseFormat:(MouseFormat)format
{
    MOUSE_FORMAT = format;
}

@end
