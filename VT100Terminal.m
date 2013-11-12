#import "VT100Terminal.h"
#import "DebugLogging.h"
#import <apr-1/apr_base64.h>  // for xterm's base64 decoding (paste64)
#include <term.h>

#define STANDARD_STREAM_SIZE 100000
#define MAX_XTERM_TEMP_BUFFER_LENGTH 1024

@implementation VT100Terminal

@synthesize delegate = delegate_;

#define iscontrol(c)  ((c) <= 0x1f)

// Code to detect if characters are properly encoded for each encoding.

// Traditional Chinese (Big5)
// 1st   0xa1-0xfe
// 2nd   0x40-0x7e || 0xa1-0xfe
//
// Simplifed Chinese (EUC_CN)
// 1st   0x81-0xfe
// 2nd   0x40-0x7e || 0x80-0xfe
#define iseuccn(c)   ((c) >= 0x81 && (c) <= 0xfe)
#define isbig5(c)    ((c) >= 0xa1 && (c) <= 0xfe)
#define issjiskanji(c)  (((c) >= 0x81 && (c) <= 0x9f) ||  \
                         ((c) >= 0xe0 && (c) <= 0xef))
#define iseuckr(c)   ((c) >= 0xa1 && (c) <= 0xfe)

#define isGBEncoding(e)     ((e)==0x80000019 || (e)==0x80000421|| \
                             (e)==0x80000631 || (e)==0x80000632|| \
                             (e)==0x80000930)
#define isBig5Encoding(e)   ((e)==0x80000002 || (e)==0x80000423|| \
                             (e)==0x80000931 || (e)==0x80000a03|| \
                             (e)==0x80000a06)
#define isJPEncoding(e)     ((e)==0x80000001 || (e)==0x8||(e)==0x15)
#define isSJISEncoding(e)   ((e)==0x80000628 || (e)==0x80000a01)
#define isKREncoding(e)     ((e)==0x80000422 || (e)==0x80000003|| \
                             (e)==0x80000840 || (e)==0x80000940)
#define ESC  0x1b
#define DEL  0x7f

// Codes to send for keypresses
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

// Reporting formats
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

// character attributes
#define VT100CHARATTR_ALLOFF   0
#define VT100CHARATTR_BOLD     1
#define VT100CHARATTR_ITALIC   3
#define VT100CHARATTR_UNDER    4
#define VT100CHARATTR_BLINK    5
#define VT100CHARATTR_REVERSE  7

// xterm additions
#define VT100CHARATTR_NORMAL        22
#define VT100CHARATTR_NOT_ITALIC    23
#define VT100CHARATTR_NOT_UNDER     24
#define VT100CHARATTR_STEADY        25
#define VT100CHARATTR_POSITIVE      27

typedef enum {
    COLORCODE_BLACK = 0,
    COLORCODE_RED = 1,
    COLORCODE_GREEN = 2,
    COLORCODE_YELLOW = 3,
    COLORCODE_BLUE = 4,
    COLORCODE_PURPLE = 5,
    COLORCODE_WATER = 6,
    COLORCODE_WHITE = 7,
    COLORCODE_256 = 8,
    COLORS
} colorCode;

// Color constants
// Color codes for 8-color mode. Black and white are the limits; other codes can be constructed
// similarly.
#define VT100CHARATTR_FG_BASE  30
#define VT100CHARATTR_BG_BASE  40

#define VT100CHARATTR_FG_BLACK     (VT100CHARATTR_FG_BASE + COLORCODE_BLACK)
#define VT100CHARATTR_FG_WHITE     (VT100CHARATTR_FG_BASE + COLORCODE_WHITE)
#define VT100CHARATTR_FG_256       (VT100CHARATTR_FG_BASE + COLORCODE_256)
#define VT100CHARATTR_FG_DEFAULT   (VT100CHARATTR_FG_BASE + 9)

#define VT100CHARATTR_BG_BLACK     (VT100CHARATTR_BG_BASE + COLORCODE_BLACK)
#define VT100CHARATTR_BG_WHITE     (VT100CHARATTR_BG_BASE + COLORCODE_WHITE)
#define VT100CHARATTR_BG_256       (VT100CHARATTR_BG_BASE + COLORCODE_256)
#define VT100CHARATTR_BG_DEFAULT   (VT100CHARATTR_BG_BASE + 9)

// Color codes for 16-color mode. Black and white are the limits; other codes can be constructed
// similarly.
#define VT100CHARATTR_FG_HI_BASE  90
#define VT100CHARATTR_BG_HI_BASE  100

#define VT100CHARATTR_FG_HI_BLACK     (VT100CHARATTR_FG_HI_BASE + COLORCODE_BLACK)
#define VT100CHARATTR_FG_HI_WHITE     (VT100CHARATTR_FG_HI_BASE + COLORCODE_WHITE)

#define VT100CHARATTR_BG_HI_BLACK     (VT100CHARATTR_BG_HI_BASE + COLORCODE_BLACK)
#define VT100CHARATTR_BG_HI_WHITE     (VT100CHARATTR_BG_HI_BASE + COLORCODE_WHITE)

typedef enum {
    // Keyboard modifier flags
    MOUSE_BUTTON_SHIFT_FLAG = 4,
    MOUSE_BUTTON_META_FLAG = 8,
    MOUSE_BUTTON_CTRL_FLAG = 16,

    // scroll flag
    MOUSE_BUTTON_SCROLL_FLAG = 64,  // this is a scroll event

    // for SGR 1006 style, internal use only
    MOUSE_BUTTON_SGR_RELEASE_FLAG = 128  // mouse button was released

} MouseButtonModifierFlag;


#define VT100CSIPARAM_MAX    16  // Maximum number of CSI parameters in VT100TCC.u.csi.p.
#define VT100CSISUBPARAM_MAX    16  // Maximum number of CSI sub-parameters in VT100TCC.u.csi.p.

typedef struct {
    int p[VT100CSIPARAM_MAX];
    int count;
    int cmd;
    int sub[VT100CSIPARAM_MAX][VT100CSISUBPARAM_MAX];
    int subCount[VT100CSIPARAM_MAX];
    BOOL question; // used by old parser
    int modifier;  // used by old parser
} CSIParam;

// Sets the |n|th parameter's value in CSIParam |pm| to |d|, but only if it's currently negative.
// |pm|.count is incremented if necessary.
#define SET_PARAM_DEFAULT(pm, n, d) \
(((pm).p[(n)] = (pm).p[(n)] < 0 ? (d):(pm).p[(n)]), \
 ((pm).count  = (pm).count > (n) + 1 ? (pm).count : (n) + 1 ))

typedef enum {
    // Any control character between 0-0x1f inclusive can by a token type. For these, the value
    // matters.
    VT100CC_NULL = 0,
    VT100CC_SOH = 1,   // Not used
    VT100CC_STX = 2,   // Not used
    VT100CC_ETX = 3,   // Not used
    VT100CC_EOT = 4,   // Not used
    VT100CC_ENQ = 5,   // Transmit ANSWERBACK message
    VT100CC_ACK = 6,   // Not used
    VT100CC_BEL = 7,   // Sound bell
    VT100CC_BS = 8,    // Move cursor to the left
    VT100CC_HT = 9,    // Move cursor to the next tab stop
    VT100CC_LF = 10,   // line feed or new line operation
    VT100CC_VT = 11,   // Same as <LF>.
    VT100CC_FF = 12,   // Same as <LF>.
    VT100CC_CR = 13,   // Move the cursor to the left margin
    VT100CC_SO = 14,   // Invoke the G1 character set
    VT100CC_SI = 15,   // Invoke the G0 character set
    VT100CC_DLE = 16,  // Not used
    VT100CC_DC1 = 17,  // Causes terminal to resume transmission (XON).
    VT100CC_DC2 = 18,  // Not used
    VT100CC_DC3 = 19,  // Causes terminal to stop transmitting all codes except XOFF and XON (XOFF).
    VT100CC_DC4 = 20,  // Not used
    VT100CC_NAK = 21,  // Not used
    VT100CC_SYN = 22,  // Not used
    VT100CC_ETB = 23,  // Not used
    VT100CC_CAN = 24,  // Cancel a control sequence
    VT100CC_EM = 25,   // Not used
    VT100CC_SUB = 26,  // Same as <CAN>.
    VT100CC_ESC = 27,  // Introduces a control sequence.
    VT100CC_FS = 28,   // Not used
    VT100CC_GS = 29,   // Not used
    VT100CC_RS = 30,   // Not used
    VT100CC_US = 31,   // Not used
    VT100CC_DEL = 255, // Ignored on input; not stored in buffer.

    VT100_WAIT = 1000,
    VT100_NOTSUPPORT,
    VT100_SKIP,
    VT100_STRING,
    VT100_ASCIISTRING,
    VT100_UNKNOWNCHAR,
    VT100_INVALID_SEQUENCE,

    VT100CSI_CPR,                   // Cursor Position Report
    VT100CSI_CUB,                   // Cursor Backward
    VT100CSI_CUD,                   // Cursor Down
    VT100CSI_CUF,                   // Cursor Forward
    VT100CSI_CUP,                   // Cursor Position
    VT100CSI_CUU,                   // Cursor Up
    VT100CSI_DA,                    // Device Attributes
    VT100CSI_DA2,                   // Secondary Device Attributes
    VT100CSI_DECALN,                // Screen Alignment Display
    VT100CSI_DECDHL,                // Double Height Line
    VT100CSI_DECDWL,                // Double Width Line
    VT100CSI_DECID,                 // Identify Terminal
    VT100CSI_DECKPAM,               // Keypad Application Mode
    VT100CSI_DECKPNM,               // Keypad Numeric Mode
    VT100CSI_DECLL,                 // Load LEDS
    VT100CSI_DECRC,                 // Restore Cursor
    VT100CSI_DECREPTPARM,           // Report Terminal Parameters
    VT100CSI_DECREQTPARM,           // Request Terminal Parameters
    VT100CSI_DECRST,
    VT100CSI_DECSC,                 // Save Cursor
    VT100CSI_DECSET,
    VT100CSI_DECSTBM,               // Set Top and Bottom Margins
    VT100CSI_DECSWL,                // Single-width Line
    VT100CSI_DECTST,                // Invoke Confidence Test
    VT100CSI_DSR,                   // Device Status Report
    VT100CSI_ED,                    // Erase In Display
    VT100CSI_EL,                    // Erase In Line
    VT100CSI_HTS,                   // Horizontal Tabulation Set
    VT100CSI_HVP,                   // Horizontal and Vertical Position
    VT100CSI_IND,                   // Index
    VT100CSI_NEL,                   // Next Line
    VT100CSI_RI,                    // Reverse Index
    VT100CSI_RIS,                   // Reset To Initial State
    VT100CSI_RM,                    // Reset Mode
    VT100CSI_SCS,
    VT100CSI_SCS0,                  // Select Character Set 0
    VT100CSI_SCS1,                  // Select Character Set 1
    VT100CSI_SCS2,                  // Select Character Set 2
    VT100CSI_SCS3,                  // Select Character Set 3
    VT100CSI_SGR,                   // Select Graphic Rendition
    VT100CSI_SM,                    // Set Mode
    VT100CSI_TBC,                   // Tabulation Clear
    VT100CSI_DECSCUSR,              // Select the Style of the Cursor
    VT100CSI_DECSTR,                // Soft reset
    VT100CSI_DECDSR,                // Device Status Report (DEC specific)
    VT100CSI_SET_MODIFIERS,         // CSI > Ps; Pm m (Whether to set modifiers for different kinds of key presses; no official name)
    VT100CSI_RESET_MODIFIERS,       // CSI > Ps n (Set all modifiers values to -1, disabled)
    VT100CSI_DECSLRM,               // Set left-right margin

    // some xterm extensions
    XTERMCC_WIN_TITLE,            // Set window title
    XTERMCC_ICON_TITLE,
    XTERMCC_WINICON_TITLE,
    XTERMCC_INSBLNK,              // Insert blank
    XTERMCC_INSLN,                // Insert lines
    XTERMCC_DELCH,                // delete blank
    XTERMCC_DELLN,                // delete lines
    XTERMCC_WINDOWSIZE,           // (8,H,W) NK: added for Vim resizing window
    XTERMCC_WINDOWSIZE_PIXEL,     // (8,H,W) NK: added for Vim resizing window
    XTERMCC_WINDOWPOS,            // (3,Y,X) NK: added for Vim positioning window
    XTERMCC_ICONIFY,
    XTERMCC_DEICONIFY,
    XTERMCC_RAISE,
    XTERMCC_LOWER,
    XTERMCC_SU,                  // scroll up
    XTERMCC_SD,                  // scroll down
    XTERMCC_REPORT_WIN_STATE,
    XTERMCC_REPORT_WIN_POS,
    XTERMCC_REPORT_WIN_PIX_SIZE,
    XTERMCC_REPORT_WIN_SIZE,
    XTERMCC_REPORT_SCREEN_SIZE,
    XTERMCC_REPORT_ICON_TITLE,
    XTERMCC_REPORT_WIN_TITLE,
    XTERMCC_PUSH_TITLE,
    XTERMCC_POP_TITLE,
    XTERMCC_SET_RGB,
    XTERMCC_PROPRIETARY_ETERM_EXT,
    XTERMCC_SET_PALETTE,
    XTERMCC_SET_KVP,
    XTERMCC_PASTE64,

    // Some ansi stuff
    ANSICSI_CHA,     // Cursor Horizontal Absolute
    ANSICSI_VPA,     // Vert Position Absolute
    ANSICSI_VPR,     // Vert Position Relative
    ANSICSI_ECH,     // Erase Character
    ANSICSI_PRINT,   // Print to Ansi
    ANSICSI_SCP,     // Save cursor position
    ANSICSI_RCP,     // Restore cursor position
    ANSICSI_CBT,     // Back tab

    ANSI_RIS,        // Reset to initial state (there's also a CSI version)

    // Toggle between ansi/vt52
    STRICT_ANSI_MODE,

    // iTerm extension
    ITERM_GROWL,
    DCS_TMUX,
} VT100TerminalTokenType;

// A parsed token.
struct VT100TCC {
    VT100TerminalTokenType type;
    unsigned char *position;  // Pointer into stream of where this token's data began.
    int length;  // Length of parsed data in stream.
    union {
        NSString *string;  // For VT100_STRING, VT100_ASCIISTRING
        unsigned char code;  // For VT100_UNKNOWNCHAR and VT100CSI_SCS0...SCS3.
        CSIParam csi;  // 'cmd' not used here.
    } u;
};


// functions
static BOOL isCSI(unsigned char *, int);
static BOOL isXTERM(unsigned char *, int);
static BOOL isString(unsigned char *, NSStringEncoding);
static int getCSIParam(unsigned char *, int, CSIParam *, id<VT100TerminalDelegate>);
static int getCSIParamCanonically(unsigned char *, int, CSIParam *, id<VT100TerminalDelegate>);
static VT100TCC decode_csi(unsigned char *, int, int *, id<VT100TerminalDelegate>);
static VT100TCC decode_csi_canonically(unsigned char *, int, int *, id<VT100TerminalDelegate>);
static VT100TCC decode_xterm(unsigned char *, int, int *,NSStringEncoding);
static VT100TCC decode_ansi(unsigned char *,int, int *, id<VT100TerminalDelegate>);
static VT100TCC decode_other(unsigned char *, int, int *, NSStringEncoding);
static VT100TCC decode_control(unsigned char *, int, int *, NSStringEncoding, id<VT100TerminalDelegate>, BOOL);
static VT100TCC decode_utf8(unsigned char *, int, int *);
static VT100TCC decode_euccn(unsigned char *, int, int *);
static VT100TCC decode_big5(unsigned char *,int, int *);
static VT100TCC decode_string(unsigned char *, int, int *,
                              NSStringEncoding);

// Prevents runaway memory usage
static const int kMaxScreenColumns = 4096;
static const int kMaxScreenRows = 4096;

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

    if (encoding== NSUTF8StringEncoding) {
        if (*code >= 0x80) {
            result = YES;
        }
    } else if (isGBEncoding(encoding)) {
        if (iseuccn(*code))
            result = YES;
    } else if (isBig5Encoding(encoding)) {
        if (isbig5(*code))
            result = YES;
    } else if (isJPEncoding(encoding)) {
        if (*code ==0x8e || *code==0x8f|| (*code>=0xa1&&*code<=0xfe))
            result = YES;
    } else if (isSJISEncoding(encoding)) {
        if (*code >= 0x80)
            result = YES;
    } else if (isKREncoding(encoding)) {
        if (iseuckr(*code))
            result = YES;
    } else if (*code>=0x20) {
        result = YES;
    }

    return result;
}

static int advanceAndEatControlChars(unsigned char **ppdata,
                                     int *pdatalen,
                                     id<VT100TerminalDelegate> delegate)
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
                [delegate terminalRingBell];
                break;
            case VT100CC_BS:
                [delegate terminalBackspace];
                break;
            case VT100CC_HT:
                [delegate terminalAppendTabAtCursor];
                break;
            case VT100CC_LF:
            case VT100CC_VT:
            case VT100CC_FF:
                [delegate terminalLineFeed];
                break;
            case VT100CC_CR:
                [delegate terminalCarriageReturn];
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
                [delegate terminalDeleteCharactersAtCursor:1];
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
                       CSIParam *param, id<VT100TerminalDelegate> delegate)
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
    } else if (datalen > 0 && *datap == '>') {
        // check for secondary device attribute modifier
        param->modifier = '>';
        param->question = NO;
        datap++;
        datalen--;
    } else {
        param->question = NO;
    }

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
            if (param->count < VT100CSIPARAM_MAX) {
                param->p[param->count] = n;
            }
            // increment the parameter count
            param->count++;

            // set the numeric parameter flag
            readNumericParameter = YES;
        } else if (*datap == ';') {
            datap++;
            datalen--;

            // If we got an implied (blank) parameter, increment the parameter count again
            if (readNumericParameter == NO)
                param->count++;
            // reset the parameter flag
            readNumericParameter = NO;
        } else if (isalpha(*datap)||*datap=='@') {
            datalen--;
            param->cmd = unrecognized?0xff:*datap;
            datap++;
            break;
        } else if (*datap == ' ') {
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
        } else if (*datap=='\'') {
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
        } else if (*datap=='&') {
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
        } else if (*datap == '!') {
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
        } else {
            switch (*datap) {
                case VT100CC_ENQ:
                    break;
                case VT100CC_BEL:
                    [delegate terminalRingBell];
                    break;
                case VT100CC_BS:
                    [delegate terminalBackspace];
                    break;
                case VT100CC_HT:
                    [delegate terminalAppendTabAtCursor];
                    break;
                case VT100CC_LF:
                case VT100CC_VT:
                case VT100CC_FF:
                    [delegate terminalLineFeed];
                    break;
                case VT100CC_CR:
                    [delegate terminalCarriageReturn];
                    break;
                case VT100CC_SO:
                case VT100CC_SI:
                case VT100CC_DC1:
                case VT100CC_DC3:
                case VT100CC_CAN:
                case VT100CC_SUB:
                    break;
                case VT100CC_DEL:
                    [delegate terminalDeleteCharactersAtCursor:1];
                    break;
                default:
                    // Unrecognized escape sequence.
                    param->cmd = 0xff;
                    unrecognized = YES;
                    break;
            }
            if (unrecognized == NO) {
                datalen--;
                datap++;
            }
        }
        if (unrecognized) {
            break;
        }
    }
    return datap - orgp;
}

static int getCSIParamCanonically(unsigned char *datap,
                                  int datalen,
                                  CSIParam *param,
                                  id<VT100TerminalDelegate> delegate)
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

    if (!advanceAndEatControlChars(&datap, &datalen, delegate)) {
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
                if (!advanceAndEatControlChars(&datap, &datalen, delegate))
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
                    if (!advanceAndEatControlChars(&datap, &datalen, delegate)) {
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

                if (!advanceAndEatControlChars(&datap, &datalen, delegate)) {
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
                if (!advanceAndEatControlChars(&datap, &datalen, delegate)) {
                    goto cancel;
                }
                break;

            default:
                // '<', '=', '>', or '?'
                unrecognized = YES;
                if (!advanceAndEatControlChars(&datap, &datalen, delegate)) {
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
        if (!advanceAndEatControlChars(&datap, &datalen, delegate)) {
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
            if (!advanceAndEatControlChars(&datap, &datalen, delegate)) {
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

static VT100TCC decode_ansi(unsigned char *datap,
                            int datalen,
                            int *rmlen,
                            id<VT100TerminalDelegate> delegate)
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
                           id<VT100TerminalDelegate> delegate)
{
    VT100TCC result;
    CSIParam param;
    memset(&param, 0, sizeof(param));
    memset(&result, 0, sizeof(result));
    int paramlen;
    int i;

    paramlen = getCSIParam(datap, datalen, &param, delegate);
    result.type = VT100_WAIT;

    // Check for unkown
    if (param.cmd == 0xff) {
        result.type = VT100_UNKNOWNCHAR;
        *rmlen = paramlen;
    } else if (paramlen > 0 && param.cmd > 0) {
        // process
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
                    SET_PARAM_DEFAULT(param, 1, [delegate terminalHeight]);
                    break;

                case 'y':
                    if (param.count == 2) {
                        result.type = VT100CSI_DECTST;
                    } else {
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
                            SET_PARAM_DEFAULT(param, 1, 0);     // X position in px
                            SET_PARAM_DEFAULT(param, 2, 0);     // Y position in px
                            break;
                        case 4:
                            result.type = XTERMCC_WINDOWSIZE_PIXEL;
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
                    } else {
                        result.type = VT100_NOTSUPPORT;
                    }
                    break;


                    // ANSI
                case 'Z':
                    result.type = ANSICSI_CBT;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    break;
                case 'G':
                    result.type = ANSICSI_CHA;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    break;
                case 'd':
                    result.type = ANSICSI_VPA;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    break;
                case 'e':
                    result.type = ANSICSI_VPR;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    break;
                case 'X':
                    result.type = ANSICSI_ECH;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    break;
                case 'i':
                    result.type = ANSICSI_PRINT;
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;
                case 's':
                    if ([delegate terminalUseColumnScrollRegion]) {
                        result.type = VT100CSI_DECSLRM;
                        SET_PARAM_DEFAULT(param, 0, 1);
                        SET_PARAM_DEFAULT(param, 1, 1);
                    } else {
                        result.type = ANSICSI_SCP;
                        SET_PARAM_DEFAULT(param, 0, 0);
                    }
                    break;
                case 'u':
                    result.type = ANSICSI_RCP;
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;
                default:
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
                    result.type = VT100_NOTSUPPORT;
                    break;

            }
        }

        // copy CSI parameter
        for (i = 0; i < VT100CSIPARAM_MAX; ++i) {
            result.u.csi.p[i] = param.p[i];
        }
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
                                       id<VT100TerminalDelegate> delegate)
{
    VT100TCC result;
    CSIParam param;
    memset(&param, 0, sizeof(param));
    memset(&result, 0, sizeof(result));
    int paramlen;
    int i;

    paramlen = getCSIParamCanonically(datap, datalen, &param, delegate);
    result.type = VT100_WAIT;

    // Check for unkown
    if (param.cmd == 0xff) {
        result.type = VT100_UNKNOWNCHAR;
        *rmlen = paramlen;
    } else if (paramlen > 0 && param.cmd > 0) {
        // process
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
                SET_PARAM_DEFAULT(param, 1, [delegate terminalHeight]);
                break;

            case 'y':
                if (param.count == 2)
                    result.type = VT100CSI_DECTST;
                else
                {
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
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
            case 'L':
                result.type = XTERMCC_INSLN;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
            case 'P':
                result.type = XTERMCC_DELCH;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
            case 'M':
                result.type = XTERMCC_DELLN;
                SET_PARAM_DEFAULT(param, 0, 1);
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
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
            case 'T':
                if (param.count < 2) {
                    result.type = XTERMCC_SD;
                    SET_PARAM_DEFAULT(param, 0, 1);
                }
                else
                    result.type = VT100_NOTSUPPORT;
                break;

            // ANSI
            case 'Z':
                result.type = ANSICSI_CBT;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
            case 'G':
                result.type = ANSICSI_CHA;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
            case 'd':
                result.type = ANSICSI_VPA;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
            case 'e':
                result.type = ANSICSI_VPR;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
            case 'X':
                result.type = ANSICSI_ECH;
                SET_PARAM_DEFAULT(param, 0, 1);
                break;
            case 'i':
                result.type = ANSICSI_PRINT;
                SET_PARAM_DEFAULT(param, 0, 0);
                break;
            case 's':
                if ([delegate terminalUseColumnScrollRegion]) {
                    result.type = VT100CSI_DECSLRM;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    SET_PARAM_DEFAULT(param, 1, 1);
                } else {
                    result.type = ANSICSI_SCP;
                    SET_PARAM_DEFAULT(param, 0, 0);
                }
                break;
            case 'u':
                result.type = ANSICSI_RCP;
                SET_PARAM_DEFAULT(param, 0, 0);
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
                result.type = VT100_NOTSUPPORT;
                break;

        }

        // copy CSI parameter
        for (i = 0; i < VT100CSIPARAM_MAX; ++i) {
            result.u.csi.p[i] = param.p[i];
            result.u.csi.subCount[i] = param.subCount[i];
            for (int j = 0; j < VT100CSISUBPARAM_MAX; j++) {
                result.u.csi.sub[i][j] = param.sub[i][j];
            }
        }
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
    char s[MAX_XTERM_TEMP_BUFFER_LENGTH] = { 0 };
    char *c = NULL;

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
            if (c - s < MAX_XTERM_TEMP_BUFFER_LENGTH) {
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
            if (c2 < 0) {
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
                               id<VT100TerminalDelegate> delegate,
                               BOOL canonical)
{
    VT100TCC result;

    if (isCSI(datap, datalen)) {
        if (canonical) {
            result = decode_csi_canonically(datap, datalen, rmlen, delegate);
        } else {
            result = decode_csi(datap, datalen, rmlen, delegate);
        }
    } else if (isXTERM(datap, datalen)) {
        result = decode_xterm(datap, datalen, rmlen, enc);
    } else if (isANSI(datap, datalen)) {
        result = decode_ansi(datap, datalen, rmlen, delegate);
    } else if (isDCS(datap, datalen)) {
        result = decode_dcs(datap, datalen, rmlen, enc);
    } else {
        NSCParameterAssert(datalen > 0);

        switch (*datap) {
            case VT100CC_NULL:
                result.type = VT100_SKIP;
                *rmlen = 0;
                while (datalen > 0 && *datap == '\0') {
                    ++datap;
                    --datalen;
                    ++*rmlen;
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
        if (iseuccn(*p) && len > 1) {
            if ((*(p+1) >= 0x40 &&
                 *(p+1) <= 0x7e) ||
                (*(p+1) >= 0x80 &&
                 *(p+1) <= 0xfe)) {
                p += 2;
                len -= 2;
            } else {
                *p = ONECHAR_UNKNOWN;
                p++;
                len--;
            }
        } else {
            break;
        }
    }
    if (len == datalen) {
        *rmlen = 0;
        result.type = VT100_WAIT;
    } else {
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
        if (isbig5(*p) && len > 1) {
            if ((*(p+1) >= 0x40 &&
                 *(p+1) <= 0x7e) ||
                (*(p+1) >= 0xa1 &&
                 *(p+1)<=0xfe)) {
                p += 2;
                len -= 2;
            } else {
                *p = ONECHAR_UNKNOWN;
                p++;
                len--;
            }
        } else {
            break;
        }
    }
    if (len == datalen) {
        *rmlen = 0;
        result.type = VT100_WAIT;
    } else {
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
        } else if (len > 2  && *p == 0x8f ) {
            p += 3;
            len -= 3;
        } else if (len > 1 && *p >= 0xa1 && *p <= 0xfe ) {
            p += 2;
            len -= 2;
        } else {
            break;
        }
    }
    if (len == datalen) {
        *rmlen = 0;
        result.type = VT100_WAIT;
    } else {
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
        if (issjiskanji(*p) && len > 1) {
            p += 2;
            len -= 2;
        } else if (*p>=0x80) {
            p++;
            len--;
        } else {
            break;
        }
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
        if (iseuckr(*p) && len > 1) {
            p += 2;
            len -= 2;
        } else {
            break;
        }
    }
    if (len == datalen) {
        *rmlen = 0;
        result.type = VT100_WAIT;
    } else {
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
        if (*p >= 0x80) {
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

    result.u.string = [[[NSString alloc] initWithBytes:datap
                                                length:*rmlen
                                              encoding:NSASCIIStringEncoding] autorelease];

    if (result.u.string == nil) {
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
    } else if (isGBEncoding(encoding)) {
        // Chinese-GB
        result = decode_euccn(datap, datalen, rmlen);
    } else if (isBig5Encoding(encoding)) {
        result = decode_big5(datap, datalen, rmlen);
    } else if (isJPEncoding(encoding)) {
        result = decode_euc_jp(datap, datalen, rmlen);
    } else if (isSJISEncoding(encoding)) {
        result = decode_sjis(datap, datalen, rmlen);
    } else if (isKREncoding(encoding)) {
        // korean
        result = decode_euckr(datap, datalen, rmlen);
    } else {
        result = decode_other_enc(datap, datalen, rmlen);
    }

    if (result.type == VT100_INVALID_SEQUENCE) {
        // Output only one replacement symbol, even if rmlen is higher.
        datap[0] = ONECHAR_UNKNOWN;
        result.u.string = ReplacementString();
        result.type = VT100_STRING;
    } else if (result.type != VT100_WAIT) {
        result.u.string = [[[NSString alloc] initWithBytes:datap
                                                    length:*rmlen
                                                  encoding:encoding] autorelease];

        if (result.u.string == nil) {
            // Invalid bytes, can't encode.
            int i;
            if (encoding == NSUTF8StringEncoding) {
                unsigned char temp[*rmlen * 3];
                memcpy(temp, datap, *rmlen);
                int length = *rmlen;
                // Replace every byte with unicode replacement char <?>.
                for (i = *rmlen - 1; i >= 0 && !result.u.string; i--) {
                    result.u.string = SetReplacementCharInArray(temp, &length, i);
                }
            } else {
                // Repalce every byte with ?, the replacement char for non-unicode encodings.
                for (i = *rmlen - 1; i >= 0 && !result.u.string; i--) {
                    datap[i] = ONECHAR_UNKNOWN;
                    result.u.string = [[[NSString alloc] initWithBytes:datap length:*rmlen encoding:encoding] autorelease];
                }
            }
        }
    }
    return result;
}

#pragma mark - Instance methods

- (id)init
{
    self = [super init];
    if (self) {
        encoding_ = NSASCIIStringEncoding;
        total_stream_length = STANDARD_STREAM_SIZE;
        stream_ = malloc(total_stream_length);
        current_stream_length = 0;

        termType = nil;
        for (int i = 0; i < TERMINFO_KEYS; i ++) {
            keyStrings_[i] = NULL;
        }

        lineMode_ = NO;
        cursorMode_ = NO;
        columnMode_ = NO;
        scrollMode_ = NO;
        screenMode_ = NO;
        originMode_ = NO;
        wraparoundMode_ = YES;
        autorepeatMode_ = YES;
        keypadMode_ = NO;
        insertMode_ = NO;
        saveCharset_ = charset_ = NO;
        xon_ = YES;
        bold_ = italic_ = blink_ = reversed_ = under_ = NO;
        saveBold_ = saveItalic_ = saveBlink_ = saveReversed_ = saveUnder_ = NO;
        fgColorCode_ = ALTSEM_FG_DEFAULT;
        fgGreen_ = 0;
        fgBlue_ = 0;
        fgColorMode_ = ColorModeAlternate;
        bgColorCode_ = ALTSEM_BG_DEFAULT;
        bgGreen_ = 0;
        bgBlue_ = 0;
        bgColorMode_ = ColorModeAlternate;
        saveForeground_ = fgColorCode_;
        saveFgColorMode_ = fgColorMode_;
        saveBackground_ = bgColorCode_;
        saveBgColorMode_ = bgColorMode_;
        mouseMode_ = MOUSE_REPORTING_NONE;
        mouseFormat_ = MOUSE_FORMAT_XTERM;

        strictAnsiMode_ = NO;
        allowColumnMode_ = NO;
        allowKeypadMode_ = YES;

        streamOffset_ = 0;

        numLock_ = YES;
        lastToken_ = malloc(sizeof(VT100TCC));
    }
    return self;
}

- (void)dealloc
{
    free(stream_);
    [termType release];

    for (int i = 0; i < TERMINFO_KEYS; i ++) {
        if (keyStrings_[i]) {
            free(keyStrings_[i]);
        }
        keyStrings_[i] = NULL;
    }
    free(lastToken_);

    [super dealloc];
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

    allowKeypadMode_ = [termType rangeOfString:@"xterm"].location != NSNotFound;

    int r;

    setupterm((char *)[termtype UTF8String], fileno(stdout), &r);

    if (r != 1) {
        NSLog(@"Terminal type %s is not defined.\n",[termtype UTF8String]);
        for (int i = 0; i < TERMINFO_KEYS; i ++) {
            if (keyStrings_[i]) {
                free(keyStrings_[i]);
            }
            keyStrings_[i] = NULL;
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

        for (int i = 0; i < TERMINFO_KEYS; i ++) {
            if (keyStrings_[i]) {
                free(keyStrings_[i]);
            }
            keyStrings_[i] = key_names[i] ? strdup(key_names[i]) : NULL;
        }
    }

    isAnsi_ = [termType rangeOfString:@"ANSI"
                              options:NSCaseInsensitiveSearch | NSAnchoredSearch ].location != NSNotFound;
}

- (void)saveTextAttributes
{
    saveBold_ = bold_;
    saveItalic_ = italic_;
    saveUnder_ = under_;
    saveBlink_ = blink_;
    saveReversed_ = reversed_;
    saveCharset_ = charset_;
    saveForeground_ = fgColorCode_;
    saveFgGreen_ = fgGreen_;
    saveFgBlue_ = fgBlue_;
    saveFgColorMode_ = fgColorMode_;
    saveBackground_ = bgColorCode_;
    saveBgGreen_ = bgGreen_;
    saveBgBlue_ = bgBlue_;
    saveBgColorMode_ = bgColorMode_;
}

- (void)restoreTextAttributes
{
    bold_ = saveBold_;
    italic_ = saveItalic_;
    under_ = saveUnder_;
    blink_ = saveBlink_;
    reversed_ = saveReversed_;
    charset_ = saveCharset_;
    fgColorCode_ = saveForeground_;
    fgGreen_ = saveFgGreen_;
    fgBlue_ = saveFgBlue_;
    fgColorMode_ = saveFgColorMode_;
    bgColorCode_ = saveBackground_;
    bgGreen_ = saveBgGreen_;
    bgBlue_ = saveBgBlue_;
    bgColorMode_ = saveBgColorMode_;
}

- (void)setForegroundColor:(int)fgColorCode alternateSemantics:(BOOL)altsem
{
    fgColorCode_ = fgColorCode;
    fgColorMode_ = (altsem ? ColorModeAlternate : ColorModeNormal);
}

- (void)setBackgroundColor:(int)bgColorCode alternateSemantics:(BOOL)altsem
{
    bgColorCode_ = bgColorCode;
    bgColorMode_ = (altsem ? ColorModeAlternate : ColorModeNormal);
}

- (void)resetCharset {
    charset_ = NO;
    for (int i = 0; i < NUM_CHARSETS; i++) {
        [delegate_ terminalSetCharset:i toLineDrawingMode:NO];
    }
}

- (void)resetPreservingPrompt:(BOOL)preservePrompt
{
    lineMode_ = NO;
    cursorMode_ = NO;
    columnMode_ = NO;
    scrollMode_ = NO;
    screenMode_ = NO;
    originMode_ = NO;
    wraparoundMode_ = YES;
    autorepeatMode_ = YES;
    keypadMode_ = NO;
    insertMode_ = NO;
    bracketedPasteMode_ = NO;
    saveCharset_ = charset_ = NO;
    xon_ = YES;
    bold_ = italic_ = blink_ = reversed_ = under_ = NO;
    saveBold_ = saveItalic_ = saveBlink_ = saveReversed_ = saveUnder_ = NO;
    fgColorCode_ = ALTSEM_FG_DEFAULT;
    fgGreen_ = 0;
    fgBlue_ = 0;
    fgColorMode_ = ColorModeAlternate;
    bgColorCode_ = ALTSEM_BG_DEFAULT;
    bgGreen_ = 0;
    bgBlue_ = 0;
    bgColorMode_ = ColorModeAlternate;
    mouseMode_ = MOUSE_REPORTING_NONE;
    mouseFormat_ = MOUSE_FORMAT_XTERM;
    [delegate_ terminalMouseModeDidChangeTo:mouseMode_];
    [delegate_ terminalSetUseColumnScrollRegion:NO];
    reportFocus_ = NO;

    strictAnsiMode_ = NO;
    allowColumnMode_ = NO;
    [delegate_ terminalResetPreservingPrompt:preservePrompt];
}

- (BOOL)strictAnsiMode
{
    return strictAnsiMode_;
}

- (void)setStrictAnsiMode: (BOOL)flag
{
    strictAnsiMode_ = flag;
}

- (BOOL)allowColumnMode_
{
    return allowColumnMode_;
}

- (void)setAllowColumnMode: (BOOL)flag
{
    allowColumnMode_ = flag;
}

- (NSStringEncoding)encoding
{
    return encoding_;
}

- (void)setEncoding:(NSStringEncoding)encoding
{
    encoding_ = encoding;
}

- (void)putStreamData:(NSData *)data
{
    if (current_stream_length + [data length] > total_stream_length) {
        // Grow the stream if needed.
        int n = ([data length] + current_stream_length) / STANDARD_STREAM_SIZE;

        total_stream_length += n * STANDARD_STREAM_SIZE;
        stream_ = reallocf(stream_, total_stream_length);
    }

    memcpy(stream_ + current_stream_length, [data bytes], [data length]);
    current_stream_length += [data length];
    assert(current_stream_length >= 0);
    if (current_stream_length == 0) {
        streamOffset_ = 0;
    }
}

- (NSData *)streamData
{
    return [NSData dataWithBytes:stream_ + streamOffset_
                          length:current_stream_length - streamOffset_];
}

- (void)clearStream
{
    streamOffset_ = current_stream_length;
    assert(streamOffset_ >= 0);
}

- (BOOL)parseNextToken
{
    unsigned char *datap;
    int datalen;

    // get our current position in the stream
    datap = stream_ + streamOffset_;
    datalen = current_stream_length - streamOffset_;

    if (datalen == 0) {
        lastToken_->type = VT100CC_NULL;
        lastToken_->length = 0;
        streamOffset_ = 0;
        current_stream_length = 0;

        if (total_stream_length >= STANDARD_STREAM_SIZE * 2) {
            // We are done with this stream. Get rid of it and allocate a new one
            // to avoid allowing this to grow too big.
            free(stream_);
            total_stream_length = STANDARD_STREAM_SIZE;
            stream_ = malloc(total_stream_length);
        }
    } else {
        int rmlen = 0;
        if (*datap >= 0x20 && *datap <= 0x7f) {
            *lastToken_ = decode_ascii_string(datap, datalen, &rmlen);
            lastToken_->length = rmlen;
            lastToken_->position = datap;
        } else if (iscontrol(datap[0])) {
            *lastToken_ = decode_control(datap, datalen, &rmlen, encoding_, delegate_, useCanonicalParser_);
            lastToken_->length = rmlen;
            lastToken_->position = datap;
            [self updateModesFromToken:*lastToken_];
            [self updateCharacterAttributesFromToken:*lastToken_];
            [self handleProprietaryToken:*lastToken_];
        } else {
            if (isString(datap, encoding_)) {
                // If the encoding is UTF-8 then you get here only if *datap >= 0x80.
                *lastToken_ = decode_string(datap, datalen, &rmlen, encoding_);
                if (lastToken_->type != VT100_WAIT && rmlen == 0) {
                    lastToken_->type = VT100_UNKNOWNCHAR;
                    lastToken_->u.code = datap[0];
                    rmlen = 1;
                }
            } else {
                // If the encoding is UTF-8 you shouldn't get here.
                lastToken_->type = VT100_UNKNOWNCHAR;
                lastToken_->u.code = datap[0];
                rmlen = 1;
            }
            lastToken_->length = rmlen;
            lastToken_->position = datap;
        }


        if (rmlen > 0) {
            NSParameterAssert(current_stream_length >= streamOffset_ + rmlen);
            // mark our current position in the stream
            streamOffset_ += rmlen;
            assert(streamOffset_ >= 0);
        }
    }

    if (gDebugLogging) {
        NSMutableString *loginfo = [NSMutableString string];
        NSMutableString *ascii = [NSMutableString string];
        int i = 0;
        int start = 0;
        while (i < lastToken_->length) {
            unsigned char c = datap[i];
            [loginfo appendFormat:@"%02x ", (int)c];
            [ascii appendFormat:@"%c", (c>=32 && c<128) ? c : '.'];
            if (i == lastToken_->length - 1 || loginfo.length > 60) {
                DebugLog([NSString stringWithFormat:@"Bytes %d-%d of %d: %@ (%@)", start, i, (int)lastToken_->length, loginfo, ascii]);
                [loginfo setString:@""];
                [ascii setString:@""];
                start = i;
            }
            i++;
        }
    }

    return lastToken_->type != VT100_WAIT && lastToken_->type != VT100CC_NULL;
}

- (NSData *)specialKey:(int)terminfo
             cursorMod:(char*)cursorMod
             cursorSet:(char*)cursorSet
           cursorReset:(char*)cursorReset
               modflag:(unsigned int)modflag
{
    NSData* prefix = nil;
    NSData* theSuffix;
    if (keyStrings_[terminfo] && !allowKeypadMode_) {
        theSuffix = [NSData dataWithBytes:keyStrings_[terminfo]
                                   length:strlen(keyStrings_[terminfo])];
    } else {
        int mod = 0;
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
            if (cursorMode_) {
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
    if (keyStrings_[TERMINFO_KEY_INS]) {
        return [NSData dataWithBytes:keyStrings_[TERMINFO_KEY_INS]
                              length:strlen(keyStrings_[TERMINFO_KEY_INS])];
    } else {
        return [NSData dataWithBytes:KEY_INSERT length:conststr_sizeof(KEY_INSERT)];
    }
}


- (NSData *)keyDelete
{
    if (keyStrings_[TERMINFO_KEY_DEL]) {
        return [NSData dataWithBytes:keyStrings_[TERMINFO_KEY_DEL]
                              length:strlen(keyStrings_[TERMINFO_KEY_DEL])];
    } else {
        return [NSData dataWithBytes:KEY_DEL length:conststr_sizeof(KEY_DEL)];
    }
}

- (NSData *)keyBackspace
{
    if (keyStrings_[TERMINFO_KEY_BACKSPACE]) {
        return [NSData dataWithBytes:keyStrings_[TERMINFO_KEY_BACKSPACE]
                              length:strlen(keyStrings_[TERMINFO_KEY_BACKSPACE])];
    } else {
        return [NSData dataWithBytes:KEY_BACKSPACE length:conststr_sizeof(KEY_BACKSPACE)];
    }
}

- (NSData *)keyPageUp:(unsigned int)modflag
{
    NSData* theSuffix;
    if (keyStrings_[TERMINFO_KEY_PAGEUP]) {
        theSuffix = [NSData dataWithBytes:keyStrings_[TERMINFO_KEY_PAGEUP]
                                   length:strlen(keyStrings_[TERMINFO_KEY_PAGEUP])];
    } else {
        theSuffix = [NSData dataWithBytes:KEY_PAGE_UP
                             length:conststr_sizeof(KEY_PAGE_UP)];
    }
    NSMutableData* data = [[[NSMutableData alloc] init] autorelease];
    if (modflag & NSAlternateKeyMask) {
        char esc = ESC;
        [data appendData:[NSData dataWithBytes:&esc length:1]];
    }
    [data appendData:theSuffix];
    return data;
}

- (NSData *)keyPageDown:(unsigned int)modflag
{
    NSData* theSuffix;
    if (keyStrings_[TERMINFO_KEY_PAGEDOWN]) {
        theSuffix = [NSData dataWithBytes:keyStrings_[TERMINFO_KEY_PAGEDOWN]
                                   length:strlen(keyStrings_[TERMINFO_KEY_PAGEDOWN])];
    } else {
        theSuffix = [NSData dataWithBytes:KEY_PAGE_DOWN
                                   length:conststr_sizeof(KEY_PAGE_DOWN)];
    }
    NSMutableData* data = [[[NSMutableData alloc] init] autorelease];
    if (modflag & NSAlternateKeyMask) {
        char esc = ESC;
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
        if (keyStrings_[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:keyStrings_[TERMINFO_KEY_F0+no]
                                  length:strlen(keyStrings_[TERMINFO_KEY_F0+no])];
        }
        else {
            sprintf(str, KEY_FUNCTION_FORMAT, no + 10);
        }
    }
    else if (no <= 10) {
        if (keyStrings_[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:keyStrings_[TERMINFO_KEY_F0+no]
                                  length:strlen(keyStrings_[TERMINFO_KEY_F0+no])];
        }
        else {
            sprintf(str, KEY_FUNCTION_FORMAT, no + 11);
        }
    }
    else if (no <= 14)
        if (keyStrings_[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:keyStrings_[TERMINFO_KEY_F0+no]
                                  length:strlen(keyStrings_[TERMINFO_KEY_F0+no])];
        }
        else {
            sprintf(str, KEY_FUNCTION_FORMAT, no + 12);
        }
    else if (no <= 16)
        if (keyStrings_[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:keyStrings_[TERMINFO_KEY_F0+no]
                                  length:strlen(keyStrings_[TERMINFO_KEY_F0+no])];
        }
        else {
            sprintf(str, KEY_FUNCTION_FORMAT, no + 13);
        }
    else if (no <= 20)
        if (keyStrings_[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:keyStrings_[TERMINFO_KEY_F0+no]
                                  length:strlen(keyStrings_[TERMINFO_KEY_F0+no])];
        }
        else {
            sprintf(str, KEY_FUNCTION_FORMAT, no + 14);
        }
    else if (no <=35)
        if (keyStrings_[TERMINFO_KEY_F0+no]) {
            return [NSData dataWithBytes:keyStrings_[TERMINFO_KEY_F0+no]
                                  length:strlen(keyStrings_[TERMINFO_KEY_F0+no])];
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
    switch (mouseFormat_) {
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

    if (mouseFormat_ == MOUSE_FORMAT_SGR) {
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
    return reportFocus_;
}

- (BOOL)lineMode
{
    return lineMode_;
}

- (BOOL)cursorMode
{
    return cursorMode_;
}

- (BOOL)columnMode
{
    return columnMode_;
}

- (BOOL)scrollMode
{
    return scrollMode_;
}

- (BOOL)screenMode
{
    return screenMode_;
}

- (BOOL)originMode
{
    return originMode_;
}

- (BOOL)wraparoundMode
{
    return wraparoundMode_;
}

- (void)setWraparoundMode:(BOOL)mode
{
    wraparoundMode_ = mode;
}

- (BOOL)isAnsi
{
    return isAnsi_;
}

- (BOOL)autorepeatMode
{
    return autorepeatMode_;
}

- (BOOL)keypadMode
{
    return keypadMode_;
}

- (void)setKeypadMode:(BOOL)mode
{
    keypadMode_ = mode;
}

- (BOOL)insertMode
{
    return insertMode_;
}

- (int)charset
{
    return charset_;
}

- (MouseMode)mouseMode
{
    return mouseMode_;
}

- (screen_char_t)foregroundColorCode
{
    screen_char_t result = { 0 };
    if (reversed_) {
        result.foregroundColor = bgColorCode_;
        result.fgGreen = bgGreen_;
        result.fgBlue = bgBlue_;
        result.foregroundColorMode = bgColorMode_;
    } else {
        result.foregroundColor = fgColorCode_;
        result.fgGreen = fgGreen_;
        result.fgBlue = fgBlue_;
        result.foregroundColorMode = fgColorMode_;
    }
    result.bold = bold_;
    result.italic = italic_;
    result.underline = under_;
    result.blink = blink_;
    return result;
}

- (screen_char_t)backgroundColorCode
{
    screen_char_t result = { 0 };
    if (reversed_) {
        result.backgroundColor = fgColorCode_;
        result.bgGreen = fgGreen_;
        result.bgBlue = fgBlue_;
        result.backgroundColorMode = fgColorMode_;
    } else {
        result.backgroundColor = bgColorCode_;
        result.bgGreen = bgGreen_;
        result.bgBlue = bgBlue_;
        result.backgroundColorMode = bgColorMode_;
    }
    return result;
}

- (screen_char_t)foregroundColorCodeReal
{
    screen_char_t result = { 0 };
    result.foregroundColor = fgColorCode_;
    result.fgGreen = fgGreen_;
    result.fgBlue = fgBlue_;
    result.foregroundColorMode = fgColorMode_;
    result.bold = bold_;
    result.italic = italic_;
    result.underline = under_;
    result.blink = blink_;
    return result;
}

- (screen_char_t)backgroundColorCodeReal
{
    screen_char_t result = { 0 };
    result.backgroundColor = bgColorCode_;
    result.bgGreen = bgGreen_;
    result.bgBlue = bgBlue_;
    result.backgroundColorMode = bgColorMode_;
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
    insertMode_ = mode;
}

- (void)setCursorMode:(BOOL)mode
{
    cursorMode_ = mode;
}

- (void)updateModesFromToken:(VT100TCC)token
{
    BOOL mode;
    int i;

    switch (token.type) {
        case VT100CSI_DECSET:
        case VT100CSI_DECRST:
            mode=(token.type == VT100CSI_DECSET);

            for (i = 0; i < token.u.csi.count; i++) {
                switch (token.u.csi.p[i]) {
                    case 20:
                        lineMode_ = mode;
                        break;
                    case 1:
                        [self setCursorMode:mode];
                        break;
                    case 2:
                        ansiMode_ = mode;
                        break;
                    case 3:
                        columnMode_ = mode;
                        break;
                    case 4:
                        scrollMode_ = mode;
                        break;
                    case 5:
                        screenMode_ = mode;
                        [delegate_ terminalNeedsRedraw];
                        break;
                    case 6:
                        originMode_ = mode;
                        [delegate_ terminalMoveCursorToX:1 y:1];
                        break;
                    case 7:
                        wraparoundMode_ = mode;
                        break;
                    case 8:
                        autorepeatMode_ = mode;
                        break;
                    case 9:
                        // TODO: This should send mouse x&y on button press.
                        break;
                    case 25:
                        [delegate_ terminalSetCursorVisible:mode];
                        break;
                    case 40:
                        allowColumnMode_ = mode;
                        break;
                    case 69:
                        [delegate_ terminalSetUseColumnScrollRegion:mode];
                        break;

                    case 1049:
                        // From the xterm release log:
                        // Implement new escape sequence, private mode 1049, which combines
                        // the switch to/from alternate screen mode with screen clearing and
                        // cursor save/restore.  Unlike the existing escape sequence, this
                        // clears the alternate screen when switching to it rather than when
                        // switching to the normal screen, thus retaining the alternate screen
                        // contents for select/paste operations.
                        if (!disableSmcupRmcup_) {
                            if (mode) {
                                [self saveTextAttributes];
                                [delegate_ terminalSaveCharsetFlags];
                                [delegate_ terminalShowAltBuffer];
                                [delegate_ terminalClearScreen];
                            } else {
                                [delegate_ terminalShowPrimaryBufferRestoringCursor:YES];
                                [self restoreTextAttributes];
                                [delegate_ terminalRestoreCharsetFlags];
                            }
                        }
                        break;

                    case 2004:
                        // Set bracketed paste mode
                        bracketedPasteMode_ = mode;
                        break;

                    case 47:
                        // alternate screen buffer mode
                        if (!disableSmcupRmcup_) {
                            if (mode) {
                                [delegate_ terminalShowAltBuffer];
                            } else {
                                [delegate_ terminalShowPrimaryBufferRestoringCursor:NO];
                            }
                        }
                        break;

                    case 1000:
                    /* case 1001: */ /* MOUSE_REPORTING_HILITE not implemented yet */
                    case 1002:
                    case 1003:
                        if (mode) {
                            mouseMode_ = token.u.csi.p[i] - 1000;
                        } else {
                            mouseMode_ = MOUSE_REPORTING_NONE;
                        }
                        [delegate_ terminalMouseModeDidChangeTo:mouseMode_];
                        break;
                    case 1004:
                        reportFocus_ = mode;
                        break;

                    case 1005:
                        if (mode) {
                            mouseFormat_ = MOUSE_FORMAT_XTERM_EXT;
                        } else {
                            mouseFormat_ = MOUSE_FORMAT_XTERM;
                        }
                        break;


                    case 1006:
                        if (mode) {
                            mouseFormat_ = MOUSE_FORMAT_SGR;
                        } else {
                            mouseFormat_ = MOUSE_FORMAT_XTERM;
                        }
                        break;

                    case 1015:
                        if (mode) {
                            mouseFormat_ = MOUSE_FORMAT_URXVT;
                        } else {
                            mouseFormat_ = MOUSE_FORMAT_XTERM;
                        }
                        break;
                }
            }
            break;
        case VT100CSI_SM:
        case VT100CSI_RM:
            mode=(token.type == VT100CSI_SM);

            for (i = 0; i < token.u.csi.count; i++) {
                switch (token.u.csi.p[i]) {
                    case 4:
                        [self setInsertMode:mode]; break;
                }
            }
            break;
        case VT100CSI_DECKPAM:
            [self setKeypadMode:YES];
            break;
        case VT100CSI_DECKPNM:
            [self setKeypadMode:NO];
            break;
        case VT100CC_SI:
            charset_ = 0;
            break;
        case VT100CC_SO:
            charset_ = 1;
            break;
        case VT100CC_DC1:
            xon_ = YES;
            break;
        case VT100CC_DC3:
            xon_ = NO;
            break;
        case VT100CSI_DECRC:
            [self restoreTextAttributes];
            [delegate_ terminalRestoreCursor];
            break;
        case VT100CSI_DECSC:
            [self saveTextAttributes];
            [delegate_ terminalSaveCursor];
            break;
        case VT100CSI_DECSTR:
            wraparoundMode_ = YES;
            originMode_ = NO;
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
            [delegate_ terminalSendModifiersDidChangeTo:sendModifiers_
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
            [delegate_ terminalSendModifiersDidChangeTo:sendModifiers_
                                              numValues:NUM_MODIFIABLE_RESOURCES];
            break;
        }

        default:
            break;
    }
}

- (void)resetSGR {
    // all attributes off
    bold_ = italic_ = under_ = blink_ = reversed_ = NO;
    fgColorCode_ = ALTSEM_FG_DEFAULT;
    fgGreen_ = 0;
    fgBlue_ = 0;
    fgColorMode_ = ColorModeAlternate;
    bgColorCode_ = ALTSEM_BG_DEFAULT;
    bgGreen_ = 0;
    bgBlue_ = 0;
    bgColorMode_ = ColorModeAlternate;
}

- (void)updateCharacterAttributesFromToken:(VT100TCC)token
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
                        bold_ = italic_ = under_ = blink_ = reversed_ = NO;
                        fgColorCode_ = ALTSEM_FG_DEFAULT;
                        fgGreen_ = 0;
                        fgBlue_ = 0;
                        bgColorCode_ = ALTSEM_BG_DEFAULT;
                        bgGreen_ = 0;
                        bgBlue_ = 0;
                        fgColorMode_ = ColorModeAlternate;
                        bgColorMode_ = ColorModeAlternate;
                        break;
                    case VT100CHARATTR_BOLD:
                        bold_ = YES;
                        break;
                    case VT100CHARATTR_NORMAL:
                        bold_ = NO;
                        break;
                    case VT100CHARATTR_ITALIC:
                        italic_ = YES;
                        break;
                    case VT100CHARATTR_NOT_ITALIC:
                        italic_ = NO;
                        break;
                    case VT100CHARATTR_UNDER:
                        under_ = YES;
                        break;
                    case VT100CHARATTR_NOT_UNDER:
                        under_ = NO;
                        break;
                    case VT100CHARATTR_BLINK:
                        blink_ = YES;
                        break;
                    case VT100CHARATTR_STEADY:
                        blink_ = NO;
                        break;
                    case VT100CHARATTR_REVERSE:
                        reversed_ = YES;
                        break;
                    case VT100CHARATTR_POSITIVE:
                        reversed_ = NO;
                        break;
                    case VT100CHARATTR_FG_DEFAULT:
                        fgColorCode_ = ALTSEM_FG_DEFAULT;
                        fgGreen_ = 0;
                        fgBlue_ = 0;
                        fgColorMode_ = ColorModeAlternate;
                        break;
                    case VT100CHARATTR_BG_DEFAULT:
                        bgColorCode_ = ALTSEM_BG_DEFAULT;
                        bgGreen_ = 0;
                        bgBlue_ = 0;
                        bgColorMode_ = ColorModeAlternate;
                        break;
                    case VT100CHARATTR_FG_256:
                        /*
                         First subparam means:   # additional subparams:  Accepts optional params:
                         1: transparent          0                        NO
                         2: RGB                  3                        YES
                         3: CMY                  3                        YES
                         4: CMYK                 4                        YES
                         5: Indexed color        1                        NO
                         
                         Optional paramters go at position 7 and 8, and indicate toleranace as an
                         integer; and color space (0=CIELUV, 1=CIELAB). Example:
                         
                         CSI 38:2:255:128:64:0:5:1 m
                         
                         Also accepted for xterm compatibility, but never with optional parameters:
                         CSI 38;2;255;128;64 m
                         
                         Set the foreground color to red=255, green=128, blue=64 with a tolerance of
                         5 in the CIELAB color space. The 0 at the 6th position has no meaning and
                         is just a filler. */
                        
                        if (token.u.csi.subCount[i] > 0) {
                            // Preferred syntax using colons to delimit subparameters
                            if (token.u.csi.subCount[i] >= 2 && token.u.csi.sub[i][0] == 5) {
                                // CSI 38:5:P m
                                fgColorCode_ = token.u.csi.sub[i][1];
                                fgGreen_ = 0;
                                fgBlue_ = 0;
                                fgColorMode_ = ColorModeNormal;
                            } else if (token.u.csi.subCount[i] >= 4 && token.u.csi.sub[i][0] == 2) {
                                // CSI 38:2:R:G:B m
                                // 24-bit color
                                fgColorCode_ = token.u.csi.sub[i][1];
                                fgGreen_ = token.u.csi.sub[i][2];
                                fgBlue_ = token.u.csi.sub[i][3];
                                fgColorMode_ = ColorMode24bit;
                            }
                        } else if (token.u.csi.count - i >= 3 && token.u.csi.p[i + 1] == 5) {
                            // CSI 38;5;P m
                            fgColorCode_ = token.u.csi.p[i + 2];
                            fgGreen_ = 0;
                            fgBlue_ = 0;
                            fgColorMode_ = ColorModeNormal;
                            i += 2;
                        } else if (token.u.csi.count - i >= 5 && token.u.csi.p[i + 1] == 2) {
                            // CSI 38;2;R;G;B m
                            // 24-bit color support
                            fgColorCode_ = token.u.csi.p[i + 2];
                            fgGreen_ = token.u.csi.p[i + 3];
                            fgBlue_ = token.u.csi.p[i + 4];
                            fgColorMode_ = ColorMode24bit;
                            i += 4;
                        }
                        break;
                    case VT100CHARATTR_BG_256:
                        if (token.u.csi.subCount[i] > 0) {
                            // Preferred syntax using colons to delimit subparameters
                            if (token.u.csi.subCount[i] >= 2 && token.u.csi.sub[i][0] == 5) {
                                // CSI 48:5:P m
                                bgColorCode_ = token.u.csi.sub[i][1];
                                bgGreen_ = 0;
                                bgBlue_ = 0;
                                bgColorMode_ = ColorModeNormal;
                            } else if (token.u.csi.subCount[i] >= 4 && token.u.csi.sub[i][0] == 2) {
                                // CSI 48:2:R:G:B m
                                // 24-bit color
                                bgColorCode_ = token.u.csi.sub[i][1];
                                bgGreen_ = token.u.csi.sub[i][2];
                                bgBlue_ = token.u.csi.sub[i][3];
                                bgColorMode_ = ColorMode24bit;
                            }
                        } else if (token.u.csi.count - i >= 3 && token.u.csi.p[i + 1] == 5) {
                            // CSI 48;5;P m
                            bgColorCode_ = token.u.csi.p[i + 2];
                            bgGreen_ = 0;
                            bgBlue_ = 0;
                            bgColorMode_ = ColorModeNormal;
                            i += 2;
                        } else if (token.u.csi.count - i >= 5 && token.u.csi.p[i + 1] == 2) {
                            // CSI 48;2;R;G;B m
                            // 24-bit color
                            bgColorCode_ = token.u.csi.p[i + 2];
                            bgGreen_ = token.u.csi.p[i + 3];
                            bgBlue_ = token.u.csi.p[i + 4];
                            bgColorMode_ = ColorMode24bit;
                            i += 4;
                        }
                        break;
                    default:
                        // 8 color support
                        if (n >= VT100CHARATTR_FG_BLACK &&
                            n <= VT100CHARATTR_FG_WHITE) {
                            fgColorCode_ = n - VT100CHARATTR_FG_BASE - COLORCODE_BLACK;
                            fgGreen_ = 0;
                            fgBlue_ = 0;
                            fgColorMode_ = ColorModeNormal;
                        } else if (n >= VT100CHARATTR_BG_BLACK &&
                                   n <= VT100CHARATTR_BG_WHITE) {
                            bgColorCode_ = n - VT100CHARATTR_BG_BASE - COLORCODE_BLACK;
                            bgGreen_ = 0;
                            bgBlue_ = 0;
                            bgColorMode_ = ColorModeNormal;
                        }
                        // 16 color support
                        if (n >= VT100CHARATTR_FG_HI_BLACK &&
                            n <= VT100CHARATTR_FG_HI_WHITE) {
                            fgColorCode_ = n - VT100CHARATTR_FG_HI_BASE - COLORCODE_BLACK + 8;
                            fgGreen_ = 0;
                            fgBlue_ = 0;
                            fgColorMode_ = ColorModeNormal;
                        } else if (n >= VT100CHARATTR_BG_HI_BLACK &&
                                   n <= VT100CHARATTR_BG_HI_WHITE) {
                            bgColorCode_ = n - VT100CHARATTR_BG_HI_BASE - COLORCODE_BLACK + 8;
                            bgGreen_ = 0;
                            bgBlue_ = 0;
                            bgColorMode_ = ColorModeNormal;
                        }
                }
            }
        }
    } else if (token.type == VT100CSI_DECSTR) {
        [self resetSGR];
    }
}

- (NSColor *)colorForXtermCCSetPaletteString:(NSString *)argument colorNumberPtr:(int *)numberPtr {
    if ([argument length] == 7) {
        int n, r, g, b;
        int count = 0;
        count += sscanf([[argument substringWithRange:NSMakeRange(0, 1)] UTF8String], "%x", &n);
        if (count == 0) {
            unichar c = [argument characterAtIndex:0];
            n = c - 'a' + 10;
            // fg = 16 ('g')
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
            *numberPtr = n;
            return theColor;
        }
    }
    return nil;
}

- (void)handleProprietaryToken:(VT100TCC)token
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
            [delegate_ terminalColorTableEntryAtIndex:theIndex
                                     didChangeToColor:[NSColor colorWithCalibratedRed:r/255.0
                                                                                green:g/255.0
                                                                                 blue:b/255.0
                                                                                alpha:1]];
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
            ITermCursorType shapeMap[] = { CURSOR_BOX, CURSOR_VERTICAL, CURSOR_UNDERLINE };
            if (shape >= 0 && shape < sizeof(shapeMap)/sizeof(int)) {
                [delegate_ terminalSetCursorType:shapeMap[shape]];
            }
        } else if ([key isEqualToString:@"SetMark"]) {
            [delegate_ terminalSaveScrollPosition];
        } else if ([key isEqualToString:@"StealFocus"]) {
            [delegate_ terminalStealFocus];
        } else if ([key isEqualToString:@"ClearScrollback"]) {
            [delegate_ terminalClearBuffer];
        } else if ([key isEqualToString:@"CurrentDir"]) {
            [delegate_ terminalCurrentDirectoryDidChangeTo:value];
        } else if ([key isEqualToString:@"SetProfile"]) {
            [delegate_ terminalProfileShouldChangeTo:(NSString *)value];
        } else if ([key isEqualToString:@"CopyToClipboard"]) {
            [delegate_ terminalSetPasteboard:value];
        } else if ([key isEqualToString:@"EndCopy"]) {
            [delegate_ terminalCopyBufferToPasteboard];
        } else if ([key isEqualToString:@"RequestAttention"]) {
            [delegate_ terminalRequestAttention:[value boolValue]];  // true: request, false: cancel
        }
    } else if (token.type == XTERMCC_SET_PALETTE) {
        int n;
        NSColor *theColor = [self colorForXtermCCSetPaletteString:token.u.string
                                                   colorNumberPtr:&n];
        if (theColor) {
            switch (n) {
                case 16:
                    [delegate_ terminalSetForegroundColor:theColor];
                    break;
                case 17:
                    [delegate_ terminalSetBackgroundGColor:theColor];
                    break;
                case 18:
                    [delegate_ terminalSetBoldColor:theColor];
                    break;
                case 19:
                    [delegate_ terminalSetSelectionColor:theColor];
                    break;
                case 20:
                    [delegate_ terminalSetSelectedTextColor:theColor];
                    break;
                case 21:
                    [delegate_ terminalSetCursorColor:theColor];
                    break;
                case 22:
                    [delegate_ terminalSetCursorTextColor:theColor];
                    break;
                default:
                    [delegate_ terminalSetColorTableEntryAtIndex:n color:theColor];
                    break;
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
                        [delegate_ terminalSetCurrentTabColor:nil];
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
                            if ([color isEqualToString:@"red"]) {
                                [delegate_ terminalSetTabColorRedComponentTo:numValue];
                            } else if ([color isEqualToString:@"green"]) {
                                [delegate_ terminalSetTabColorGreenComponentTo:numValue];
                            } else if ([color isEqualToString:@"blue"]) {
                                [delegate_ terminalSetTabColorBlueComponentTo:numValue];
                            }
                        }
                    }
                }
            }
        }
    }
}

- (void)setDisableSmcupRmcup:(BOOL)value
{
    disableSmcupRmcup_ = value;
}

- (void)setUseCanonicalParser:(BOOL)value
{
    useCanonicalParser_ = value;
}

- (BOOL)bracketedPasteMode
{
    return bracketedPasteMode_;
}

- (void)setMouseMode:(MouseMode)mode
{
    mouseMode_ = mode;
    [delegate_ terminalMouseModeDidChangeTo:mouseMode_];
}

- (void)setMouseFormat:(MouseFormat)format
{
    mouseFormat_ = format;
}

- (void)handleDeviceStatusReportWithToken:(VT100TCC)token withQuestion:(BOOL)withQuestion {
    if ([delegate_ terminalShouldSendReport]) {
        switch (token.u.csi.p[0]) {
            case 3: // response from VT100 -- Malfunction -- retry
                break;

            case 5: // Command from host -- Please report status
                [delegate_ terminalSendReport:[self reportStatus]];
                break;

            case 6: // Command from host -- Please report active position
                if ([self originMode]) {
                    // This is compatible with Terminal but not xterm :(. xterm seems to always do what
                    // we do in the else clause.
                    [delegate_ terminalSendReport:[self reportActivePositionWithX:[delegate_ terminalRelativeCursorX]
                                                                                Y:[delegate_ terminalRelativeCursorY]
                                                                     withQuestion:withQuestion]];
                } else {
                    [delegate_ terminalSendReport:[self reportActivePositionWithX:[delegate_ terminalCursorX]
                                                                                Y:[delegate_ terminalCursorY]
                                                                     withQuestion:withQuestion]];
                }
                break;

            case 0: // Response from VT100 -- Ready, No malfuctions detected
            default:
                break;
        }
    }
}

- (NSString *)decodedBase64PasteCommand:(NSString *)commandString {
    //
    // - write access
    //   ESC ] 5 2 ; Pc ; <base64 encoded string> ST
    //
    // - read access
    //   ESC ] 5 2 ; Pc ; ? ST
    //
    // Pc consists from:
    //   'p', 's', 'c', '0', '1', '2', '3', '4', '5', '6', '7'
    //
    // Note: Pc is ignored now.
    //
    const char *buffer = [commandString UTF8String];

    // ignore first parameter now
    while (strchr("psc01234567", *buffer)) {
        ++buffer;
    }
    if (*buffer != ';') {
        return nil; // fail to parse
    }
    ++buffer;
    if (*buffer == '?') { // PASTE64(OSC 52) read access
        // Now read access is not implemented due to security issues.
        return nil;
    }

    // decode base64 string.
    int destLength = apr_base64_decode_len(buffer);
    if (destLength < 1) {
        return nil;
    }
    NSMutableData *data = [NSMutableData dataWithLength:destLength];
    char *decodedBuffer = [data mutableBytes];
    int resultLength = apr_base64_decode(decodedBuffer, buffer);
    if (resultLength < 0) {
        return nil;
    }

    // sanitize buffer
    const char *inputIterator = decodedBuffer;
    char *outputIterator = decodedBuffer;
    int outputLength = 0;
    for (int i = 0; i < resultLength + 1; ++i) {
        char c = *inputIterator;
        if (c == 0x00) {
            *outputIterator = 0; // terminate string with NULL
            break;
        }
        if (c > 0 && c < 0x20) { // if c is control character
            // check if c is TAB/LF/CR
            if (c != 0x9 && c != 0xa && c != 0xd) {
                // skip it
                ++inputIterator;
                continue;
            }
        }
        *outputIterator = c;
        ++inputIterator;
        ++outputIterator;
        ++outputLength;
    }
    [data setLength:outputLength];

    NSString *resultString = [[[NSString alloc] initWithData:data
                                                    encoding:[self encoding]] autorelease];
    return resultString;
}

- (void)executeToken {
    VT100TCC token = *lastToken_;
    // First, handle sending input to pasteboard.
    if (token.type != VT100_SKIP) {  // VT100_SKIP = there was no data to read
        if ([delegate_ terminalIsAppendingToPasteboard]) {
            // We are probably copying text to the clipboard until esc]50;EndCopy^G is received.
            if (token.type != XTERMCC_SET_KVP ||
                ![token.u.string hasPrefix:@"CopyToClipboard"]) {
                // Append text to clipboard except for initial command that turns on copying to
                // the clipboard.
                [delegate_ terminalAppendDataToPasteboard:[NSData dataWithBytes:token.position
                                                                         length:token.length]];
            }
        }
    }

    switch (token.type) {
            // our special code
        case VT100_STRING:
        case VT100_ASCIISTRING:
            [delegate_ terminalAppendString:token.u.string isAscii:lastToken_->type == VT100_ASCIISTRING];
            break;

        case VT100_UNKNOWNCHAR:
            break;
        case VT100_NOTSUPPORT:
            break;

            //  VT100 CC
        case VT100CC_ENQ:
            break;
        case VT100CC_BEL:
            [delegate_ terminalRingBell];
            break;
        case VT100CC_BS:
            [delegate_ terminalBackspace];
            break;
        case VT100CC_HT:
            [delegate_ terminalAppendTabAtCursor];
            break;
        case VT100CC_LF:
        case VT100CC_VT:
        case VT100CC_FF:
            [delegate_ terminalLineFeed];
            break;
        case VT100CC_CR:
            [delegate_ terminalCarriageReturn];
            break;
        case VT100CC_SO:
        case VT100CC_SI:
        case VT100CC_DC1:
        case VT100CC_DC3:
        case VT100CC_CAN:
        case VT100CC_SUB:
            break;
        case VT100CC_DEL:
            [delegate_ terminalDeleteCharactersAtCursor:1];
            break;

            // VT100 CSI
        case VT100CSI_CPR:
            break;
        case VT100CSI_CUB:
            [delegate_ terminalCursorLeft:token.u.csi.p[0] > 0 ? token.u.csi.p[0] : 1];
            break;
        case VT100CSI_CUD:
            [delegate_ terminalCursorDown:token.u.csi.p[0] > 0 ? token.u.csi.p[0] : 1];
            break;
        case VT100CSI_CUF:
            [delegate_ terminalCursorRight:token.u.csi.p[0] > 0 ? token.u.csi.p[0] : 1];
            break;
        case VT100CSI_CUP:
            [delegate_ terminalMoveCursorToX:token.u.csi.p[1] y:token.u.csi.p[0]];
            break;
        case VT100CSI_CUU:
            [delegate_ terminalCursorUp:token.u.csi.p[0] > 0 ? token.u.csi.p[0] : 1];
            break;
        case VT100CSI_DA:
            if ([delegate_ terminalShouldSendReport]) {
                [delegate_ terminalSendReport:[self reportDeviceAttribute]];
            }
            break;
        case VT100CSI_DA2:
            if ([delegate_ terminalShouldSendReport]) {
                [delegate_ terminalSendReport:[self reportSecondaryDeviceAttribute]];
            }
            break;
        case VT100CSI_DECALN:
            [delegate_ terminalShowTestPattern];
            break;
        case VT100CSI_DECDHL:
        case VT100CSI_DECDWL:
        case VT100CSI_DECID:
        case VT100CSI_DECKPAM:
        case VT100CSI_DECKPNM:
        case VT100CSI_DECLL:
            break;
        case VT100CSI_DECRC:
            [self restoreTextAttributes];
            [delegate_ terminalRestoreCursor];
            break;
        case VT100CSI_DECREPTPARM:
        case VT100CSI_DECREQTPARM:
            break;
        case VT100CSI_DECSC:
            [self saveTextAttributes];
            [delegate_ terminalSaveCursor];
            break;
        case VT100CSI_DECSTBM:
            [delegate_ terminalSetScrollRegionTop:token.u.csi.p[0] == 0 ? 0 : token.u.csi.p[0] - 1
                                           bottom:token.u.csi.p[1] == 0 ? [delegate_ terminalHeight] - 1 : token.u.csi.p[1] - 1];
            break;
        case VT100CSI_DECSWL:
        case VT100CSI_DECTST:
            break;
        case VT100CSI_DSR:
            [self handleDeviceStatusReportWithToken:token withQuestion:NO];
            break;
        case VT100CSI_DECDSR:
            [self handleDeviceStatusReportWithToken:token withQuestion:YES];
            break;
        case VT100CSI_ED:
            switch (token.u.csi.p[0]) {
                case 1:
                    [delegate_ terminalEraseInDisplayBeforeCursor:YES afterCursor:NO];
                    break;

                case 2:
                    [delegate_ terminalEraseInDisplayBeforeCursor:YES afterCursor:YES];
                    break;

                // TODO: case 3 should erase history.
                case 0:
                default:
                    [delegate_ terminalEraseInDisplayBeforeCursor:NO afterCursor:YES];
                    break;
            }
            break;
        case VT100CSI_EL:
            switch (token.u.csi.p[0]) {
                case 1:
                    [delegate_ terminalEraseLineBeforeCursor:YES afterCursor:NO];
                    break;
                case 2:
                    [delegate_ terminalEraseLineBeforeCursor:YES afterCursor:YES];
                    break;
                case 0:
                    [delegate_ terminalEraseLineBeforeCursor:NO afterCursor:YES];
                    break;
            }
            break;
        case VT100CSI_HTS:
            [delegate_ terminalSetTabStopAtCursor];
            break;
        case VT100CSI_HVP:
            [delegate_ terminalMoveCursorToX:token.u.csi.p[1] y:token.u.csi.p[0]];
            break;
        case VT100CSI_NEL:
            [delegate_ terminalCarriageReturn];
            // fall through
        case VT100CSI_IND:
            [delegate_ terminalLineFeed];  // TODO Make sure this is kosher. How does xterm handle index with scroll regions?
            break;
        case VT100CSI_RI:
            [delegate_ terminalReverseIndex];
            break;
        case VT100CSI_RIS:
            // As far as I can tell, this is not part of the standard and should not be
            // supported.  -- georgen 7/31/11
            break;

        case ANSI_RIS:
            [delegate_ terminalResetPreservingPrompt:NO];
            break;
        case VT100CSI_RM:
            break;
        case VT100CSI_DECSTR:
            [delegate_ terminalSoftReset];
            break;
        case VT100CSI_DECSCUSR:
            switch (token.u.csi.p[0]) {
                case 0:
                case 1:
                    [delegate_ terminalSetCursorBlinking:true];
                    [delegate_ terminalSetCursorType:CURSOR_BOX];
                    break;
                case 2:
                    [delegate_ terminalSetCursorBlinking:false];
                    [delegate_ terminalSetCursorType:CURSOR_BOX];
                    break;
                case 3:
                    [delegate_ terminalSetCursorBlinking:true];
                    [delegate_ terminalSetCursorType:CURSOR_UNDERLINE];
                    break;
                case 4:
                    [delegate_ terminalSetCursorBlinking:false];
                    [delegate_ terminalSetCursorType:CURSOR_UNDERLINE];
                    break;
                case 5:
                    [delegate_ terminalSetCursorBlinking:true];
                    [delegate_ terminalSetCursorType:CURSOR_VERTICAL];
                    break;
                case 6:
                    [delegate_ terminalSetCursorBlinking:false];
                    [delegate_ terminalSetCursorType:CURSOR_VERTICAL];
                    break;
            }
            break;

        case VT100CSI_DECSLRM: {
            int scrollLeft = token.u.csi.p[0] - 1;
            int scrollRight = token.u.csi.p[1] - 1;
            int width = [delegate_ terminalWidth];
            if (scrollLeft < 0) {
                scrollLeft = 0;
            }
            if (scrollRight == 0) {
                scrollRight = width - 1;
            }
            // check wrong parameter
            if (scrollRight - scrollLeft < 1) {
                scrollLeft = 0;
                scrollRight = width - 1;
            }
            if (scrollRight > width - 1) {
                scrollRight = width - 1;
            }
            [delegate_ terminalSetLeftMargin:scrollLeft rightMargin:scrollRight];
            break;
        }

            /* My interpretation of this:
             * http://www.cl.cam.ac.uk/~mgk25/unicode.html#term
             * is that UTF-8 terminals should ignore SCS because
             * it's either a no-op (in the case of iso-8859-1) or
             * insane. Also, mosh made fun of Terminal and I don't
             * want to be made fun of:
             * "Only Mosh will never get stuck in hieroglyphs when a nasty
             * program writes to the terminal. (See Markus Kuhn's discussion of
             * the relationship between ISO 2022 and UTF-8.)"
             * http://mosh.mit.edu/#techinfo
             *
             * I'm going to throw this out there (4/15/2012) and see if this breaks
             * anything for anyone.
             *
             * UPDATE: In bug 1997, we see that it breaks line-drawing chars, which
             * are in SCS0. Indeed, mosh fails to draw these as well.
             *
             * UPDATE: In bug 2358, we see that SCS1 is also legitimately used in
             * UTF-8.
             *
             * Here's my take on the way things work. There are four charsets: G0
             * (default), G1, G2, and G3. They are switched between with codes like SI
             * (^O), SO (^N), LS2 (ESC n), and LS3 (ESC o). You can get the current
             * character set from [terminal_ charset], and that gives you a number from
             * 0 to 3 inclusive. It is an index into Screen's charsetUsesLineDrawingMode_ array.
             * In iTerm2, it is an array of booleans where 0 means normal behavior and 1 means
             * line-drawing. There should be a bunch of other values too (like
             * locale-specific char sets). This is pretty far away from the spec,
             * but it works well enough for common behavior, and it seems the spec
             * doesn't work well with common behavior (esp line drawing).
             */
        case VT100CSI_SCS0:
            [delegate_ terminalSetCharset:0 toLineDrawingMode:(token.u.code=='0')];
            break;
        case VT100CSI_SCS1:
            [delegate_ terminalSetCharset:1 toLineDrawingMode:(token.u.code=='0')];
            break;
        case VT100CSI_SCS2:
            [delegate_ terminalSetCharset:2 toLineDrawingMode:(token.u.code=='0')];
            break;
        case VT100CSI_SCS3:
            [delegate_ terminalSetCharset:3 toLineDrawingMode:(token.u.code=='0')];
            break;
        case VT100CSI_SGR:
        case VT100CSI_SM:
            break;
        case VT100CSI_TBC:
            switch (token.u.csi.p[0]) {
                case 3:
                    [delegate_ terminalRemoveTabStops];
                    break;

                case 0:
                    [delegate_ terminalRemoveTabStopAtCursor];
            }
            break;

        case VT100CSI_DECSET:
        case VT100CSI_DECRST:
            if (token.u.csi.p[0] == 3 && // DECCOLM
                allowColumnMode_) {
                [delegate_ terminalSetWidth:([self columnMode] ? 132 : 80)];
            }
            break;

            // ANSI CSI
        case ANSICSI_CBT:
            [delegate_ terminalBackTab:token.u.csi.p[0]];
            break;
        case ANSICSI_CHA:
            [delegate_ terminalSetCursorX:token.u.csi.p[0]];
            break;
        case ANSICSI_VPA:
            [delegate_ terminalSetCursorY:token.u.csi.p[0]];
            break;
        case ANSICSI_VPR:
            [delegate_ terminalCursorDown:token.u.csi.p[0] > 0 ? token.u.csi.p[0] : 1];
            break;
        case ANSICSI_ECH:
            [delegate_ terminalEraseCharactersAfterCursor:token.u.csi.p[0]];
            break;

        case STRICT_ANSI_MODE:
            [self setStrictAnsiMode:!strictAnsiMode_];
            break;

        case ANSICSI_PRINT:
            switch (token.u.csi.p[0]) {
                case 4:
                    [delegate_ terminalPrintBuffer];
                    break;
                case 5:
                    [delegate_ terminalBeginRedirectingToPrintBuffer];
                    break;
                default:
                    [delegate_ terminalPrintScreen];
            }
            break;
        case ANSICSI_SCP:
            [delegate_ terminalSaveCursor];
            [delegate_ terminalSaveCharsetFlags];
            break;
        case ANSICSI_RCP:
            [delegate_ terminalRestoreCursor];
            [delegate_ terminalRestoreCharsetFlags];
            break;

            // XTERM extensions
        case XTERMCC_WIN_TITLE:
            [delegate_ terminalSetWindowTitle:token.u.string];
            break;
        case XTERMCC_WINICON_TITLE:
            [delegate_ terminalSetWindowTitle:token.u.string];
            [delegate_ terminalSetIconTitle:token.u.string];
            break;
        case XTERMCC_PASTE64: {
            NSString *decoded = [self decodedBase64PasteCommand:token.u.string];
            if (decoded) {
                [delegate_ terminalPasteString:decoded];
            }
        }
            break;
        case XTERMCC_ICON_TITLE:
            [delegate_ terminalSetIconTitle:token.u.string];
            break;
        case XTERMCC_INSBLNK:
            [delegate_ terminalInsertEmptyCharsAtCursor:token.u.csi.p[0]];
            break;
        case XTERMCC_INSLN:
            [delegate_ terminalInsertBlankLinesAfterCursor:token.u.csi.p[0]];
            break;
        case XTERMCC_DELCH:
            [delegate_ terminalDeleteCharactersAtCursor:token.u.csi.p[0]];
            break;
        case XTERMCC_DELLN:
            [delegate_ terminalDeleteLinesAtCursor:token.u.csi.p[0]];
            break;
        case XTERMCC_WINDOWSIZE:
            [delegate_ terminalSetRows:MIN(token.u.csi.p[1], kMaxScreenRows)
                            andColumns:MIN(token.u.csi.p[2], kMaxScreenColumns)];
            break;
        case XTERMCC_WINDOWSIZE_PIXEL:
            [delegate_ terminalSetPixelWidth:token.u.csi.p[2]
                                      height:token.u.csi.p[1]];

            break;
        case XTERMCC_WINDOWPOS:
            [delegate_ terminalMoveWindowTopLeftPointTo:NSMakePoint(token.u.csi.p[1], token.u.csi.p[2])];
            break;
        case XTERMCC_ICONIFY:
            [delegate_ terminalMiniaturize:YES];
            break;
        case XTERMCC_DEICONIFY:
            [delegate_ terminalMiniaturize:NO];
            break;
        case XTERMCC_RAISE:
            [delegate_ terminalRaise:YES];
            break;
        case XTERMCC_LOWER:
            [delegate_ terminalRaise:NO];
            break;
        case XTERMCC_SU:
            [delegate_ terminalScrollUp:token.u.csi.p[0]];
            break;
        case XTERMCC_SD:
            [delegate_ terminalScrollDown:token.u.csi.p[0]];
            break;
        case XTERMCC_REPORT_WIN_STATE: {
            NSString *s = [NSString stringWithFormat:@"\033[%dt",
                           ([delegate_ terminalWindowIsMiniaturized] ? 2 : 1)];
            [delegate_ terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_REPORT_WIN_POS: {
            NSPoint topLeft = [delegate_ terminalWindowTopLeftPixelCoordinate];
            NSString *s = [NSString stringWithFormat:@"\033[3;%d;%dt",
                           (int)topLeft.x, (int)topLeft.y];
            [delegate_ terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_REPORT_WIN_PIX_SIZE: {
            // TODO: Some kind of adjustment for panes?
            NSString *s = [NSString stringWithFormat:@"\033[4;%d;%dt",
                           [delegate_ terminalWindowHeightInPixels],
                           [delegate_ terminalWindowWidthInPixels]];
            [delegate_ terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_REPORT_WIN_SIZE: {
            NSString *s = [NSString stringWithFormat:@"\033[8;%d;%dt",
                           [delegate_ terminalHeight],
                           [delegate_ terminalWidth]];
            [delegate_ terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_REPORT_SCREEN_SIZE: {
            NSString *s = [NSString stringWithFormat:@"\033[9;%d;%dt",
                           [delegate_ terminalScreenHeightInCells],
                           [delegate_ terminalScreenWidthInCells]];
            [delegate_ terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_REPORT_ICON_TITLE: {
            NSString *s = [NSString stringWithFormat:@"\033]L%@\033\\",
                           [delegate_ terminalIconTitle]];
            [delegate_ terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_REPORT_WIN_TITLE: {
            NSString *s = [NSString stringWithFormat:@"\033]L%@\033\\",
                           [delegate_ terminalWindowTitle]];
            [delegate_ terminalSendReport:[s dataUsingEncoding:NSUTF8StringEncoding]];
            break;
        }
        case XTERMCC_PUSH_TITLE: {
            switch (token.u.csi.p[1]) {
                case 0:
                    [delegate_ terminalPushCurrentTitleForWindow:YES];
                    [delegate_ terminalPushCurrentTitleForWindow:NO];
                    break;
                case 1:
                    [delegate_ terminalPushCurrentTitleForWindow:NO];
                    break;
                case 2:
                    [delegate_ terminalPushCurrentTitleForWindow:YES];
                    break;
            }
            break;
        }
        case XTERMCC_POP_TITLE: {
            switch (token.u.csi.p[1]) {
                case 0:
                    [delegate_ terminalPopCurrentTitleForWindow:YES];
                    [delegate_ terminalPopCurrentTitleForWindow:NO];
                    break;
                case 1:
                    [delegate_ terminalPopCurrentTitleForWindow:NO];
                    break;
                case 2:
                    [delegate_ terminalPopCurrentTitleForWindow:YES];
                    break;
            }
            break;
        }
            // Our iTerm specific codes
        case ITERM_GROWL:
            [delegate_ terminalPostGrowlNotification:token.u.string];
            break;
            
        case DCS_TMUX:
            [delegate_ terminalStartTmuxMode];
            break;

        case XTERMCC_SET_KVP:
            break;

        case VT100CC_NULL:
        case VT100CC_SOH:
        case VT100_INVALID_SEQUENCE:
        case VT100_SKIP:
        case VT100_WAIT:
        case VT100CC_ACK:
        case VT100CC_DC2:
        case VT100CC_DC4:
        case VT100CC_DLE:
        case VT100CC_EM:
        case VT100CC_EOT:
        case VT100CC_ESC:
        case VT100CC_ETB:
        case VT100CC_ETX:
        case VT100CC_FS:
        case VT100CC_GS:
        case VT100CC_NAK:
        case VT100CC_RS:
        case VT100CC_STX:
        case VT100CC_SYN:
        case VT100CC_US:
        case VT100CSI_RESET_MODIFIERS:
        case VT100CSI_SCS:
        case VT100CSI_SET_MODIFIERS:
        case XTERMCC_PROPRIETARY_ETERM_EXT:
        case XTERMCC_SET_PALETTE:
        case XTERMCC_SET_RGB:
            break;

        default:
            NSLog(@"Unexpected token type %d", (int)token.type);
            break;
    }
}

- (BOOL)lastTokenWasASCII {
    return lastToken_->type == VT100_ASCIISTRING;
}

- (NSString *)lastTokenString {
    if (lastToken_->type == VT100_STRING ||
        lastToken_->type == VT100_ASCIISTRING) {
        return lastToken_->u.string;
    } else {
        return nil;
    }
}

@end
