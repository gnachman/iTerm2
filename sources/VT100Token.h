#import <Foundation/Foundation.h>

#import "iTermMalloc.h"
#import "iTermParser.h"
#import "ScreenChar.h"

typedef enum {
    // Any control character between 0-0x1f inclusive can by a token type. For these, the value
    // matters. Make sure to update the -codeName method when changing this enum.
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
    VT100CC_DEL = 127, // Backspaces

    VT100CC_C1_IND = 0x84,
    VT100CC_C1_NEL = 0x85,
    VT100CC_C1_HTS = 0x88,
    VT100CC_C1_RI = 0x8d,
    VT100CC_C1_SS2 = 0x8e,
    VT100CC_C1_SS3 = 0x8f,
    VT100CC_C1_DCS = 0x90,
    VT100CC_C1_SPA = 0x96,
    VT100CC_C1_EPA = 0x97,
    VT100CC_C1_SOS = 0x98,
    VT100CC_C1_DECID = 0x9a,
    VT100CC_C1_CSI = 0x9b,
    VT100CC_C1_ST = 0x9c,
    VT100CC_C1_OSC = 0x9d,
    VT100CC_C1_PM = 0x9e,
    VT100CC_C1_APC = 0x9f,

    VT100_WAIT = 1000,
    VT100_NOTSUPPORT,
    VT100_SKIP,
    VT100_STRING,
    VT100_ASCIISTRING,
    VT100_UNKNOWNCHAR,
    VT100_INVALID_SEQUENCE,
    VT100_BINARY_GARBAGE,

    VT100CSI_CPR,                   // Cursor Position Report
    VT100CSI_CUB,                   // Cursor Backward
    VT100CSI_CUD,                   // Cursor Down
    VT100CSI_CUF,                   // Cursor Forward
    VT100CSI_CUP,                   // Cursor Position
    VT100CSI_CHT,                   // Cursor Forward Tabulation Ps tab stops
    VT100CSI_CUU,                   // Cursor Up
    VT100CSI_CNL,                   // Cursor Next Line
    VT100CSI_CPL,                   // Cursor Preceding Line
    VT100CSI_DA,                    // Device Attributes
    VT100CSI_DA2,                   // Secondary Device Attributes
    VT100CSI_DA3,                   // Tertiary DA
    VT100CSI_XDA,                   // Extended device attributes (https://github.com/mintty/mintty/issues/881)
    VT100CSI_DECALN,                // Screen Alignment Display
    VT100CSI_DECDHL,                // Double Height Line
    VT100CSI_DECDWL,                // Double Width Line
    VT100CSI_DECID,                 // Identify Terminal
    VT100CSI_DECKPAM,               // Keypad Application Mode
    VT100CSI_DECKPNM,               // Keypad Numeric Mode
    VT100CSI_DECRC,                 // Restore Cursor
    VT100CSI_DECRST,
    VT100CSI_DECSC,                 // Save Cursor
    VT100CSI_DECSET,
    VT100CSI_DECSTBM,               // Set Top and Bottom Margins
    VT100CSI_DSR,                   // Device Status Report
    VT100CSI_ED,                    // Erase In Display
    VT100CSI_EL,                    // Erase In Line
    VT100CSI_HTS,                   // Horizontal Tabulation Set
    VT100CC_SPA,                    // Start of Guarded/Protected Area
    VT100CC_EPA,                    // End of Guarded/Protected Area
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
    VT100CSI_DECCARA,               // Change Attributes in Rectangular Area
    VT100CSI_DECRARA,               // Reverse Attributes in Rectangular Area. Also used to build team spirit.
    VT100CSI_DECSACE,               // Select Attribute Change Extent
    VT100CSI_DECCRA,                // Copy Rectangular Area
    VT100CSI_DECFRA,                // Fill Rectangular Area
    VT100CSI_DECERA,                // Erase Rectangular Area
    VT100CSI_SM,                    // Set Mode
    VT100CSI_TBC,                   // Tabulation Clear
    VT100CSI_DECSCUSR,              // Select the Style of the Cursor
    VT100CSI_DECSTR,                // Soft reset
    VT100CSI_DECDSR,                // Device Status Report (DEC specific)
    VT100CSI_SET_MODIFIERS,         // CSI > Ps; Pm m (Whether to set modifiers for different kinds of key presses; no official name)
    VT100CSI_RESET_MODIFIERS,       // CSI > Ps n (Set all modifiers values to -1, disabled)
    VT100CSI_XTREPORTSGR,           // Report SGR
    XTERMCC_XTPUSHCOLORS,           // Push colors
    XTERMCC_XTPOPCOLORS,            // Pop colors
    XTERMCC_XTREPORTCOLORS,         // Report current entry on plaette stack
    XTERMCC_XTSMGRAPHICS,           // Set or request graphics attributes
    XTERMCC_XTPUSHSGR,              // Push video attributes
    XTERMCC_XTPOPSGR,               // Pop video attributes

    VT100CSI_DECSLRM,               // Set left-right margin
    VT100CSI_DECRQCRA,              // Request Checksum of Rectangular Area
    VT100CSI_REP,                   // Repeat
    VT100CSI_DECRQM_DEC,            // Request Mode - Host To Terminal (DEC Private)
    VT100CSI_DECRQM_ANSI,           // Request Mode - Host To Terminal (ANSI)
    VT100_DECFI,                    // Forward Index
    VT100_DECBI,                    // Back Index
    VT100CSI_DECRQPSR,              // Request presentation state report
    VT100CSI_SD,                    // Scroll down
    VT100CSI_HPR,                   // Character position relative
    VT100CSI_DECSCPP,               // Select 80 or 132 columns per page
    VT100CSI_DECSNLS,               // Select number of lines per screen
    VT100CSI_DECIC,                 // Insert column
    VT100CSI_DECDC,                 // Delete column
    VT100CSI_DECSERA,               // Selective Erase Rectangular Area
    VT100CSI_DECSED,                // Selective Erase in Display
    VT100CSI_DECSEL,                // Selective Erase in Line
    VT100CSI_DECSCA,                // Select Character Protection Attribute

    // https://sw.kovidgoyal.net/kitty/keyboard-protocol.html
    VT100CSI_PUSH_KEY_REPORTING_MODE,
    VT100CSI_POP_KEY_REPORTING_MODE,
    VT100CSI_QUERY_KEY_REPORTING_MODE,

    // some xterm extensions
    XTERMCC_WIN_TITLE,            // Set window title
    XTERMCC_ICON_TITLE,
    XTERMCC_WINICON_TITLE,
    VT100CSI_ICH,                 // Insert blank
    VT100CSI_SL,                  // Shift left
    VT100CSI_SR,                  // Shift right
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
    VT100_DECSLPP,
    XTERMCC_SET_RGB,
    // This is not a real xterm code. It is from eTerm, which extended the xterm
    // protocol for its own purposes. We don't follow the eTerm protocol,
    // but we follow the template it set.
    // http://www.eterm.org/docs/view.php?doc=ref#escape
    XTERMCC_PROPRIETARY_ETERM_EXT,
    XTERMCC_PWD_URL,
    XTERMCC_LINK,
    XTERMCC_TEXT_FOREGROUND_COLOR,
    XTERMCC_TEXT_BACKGROUND_COLOR,
    XTERMCC_SET_PALETTE,
    XTERMCC_SET_KVP,
    // OSC 1337;File=(args):(data) gets changed by the parser from XTERMCC_SET_KVP to a
    // series of incidental tokens beginning with XTERMCC_MULTITOKEN_HEADER_SET_KVP.
    // See comment above XTERMCC_MULTITOKEN_BODY for details.
    XTERMCC_MULTITOKEN_HEADER_SET_KVP,
    XTERMCC_PASTE64,
    XTERMCC_FINAL_TERM,
    XTERMCC_FRAMER_WRAPPER,
    XTERMCC_RESET_COLOR,
    XTERMCC_RESET_VT100_TEXT_FOREGROUND_COLOR,
    XTERMCC_RESET_VT100_TEXT_BACKGROUND_COLOR,
    XTERMCC_RESET_TEXT_CURSOR_COLOR,
    XTERMCC_RESET_HIGHLIGHT_COLOR,
    XTERMCC_RESET_HIGHLIGHT_FOREGROUND_COLOR,

    XTERMCC_SET_TEXT_CURSOR_COLOR,
    XTERMCC_SET_HIGHLIGHT_COLOR,
    XTERMCC_SET_HIGHLIGHT_FOREGROUND_COLOR,

    // If a sequence is split into multiple tokens, the first will be one of the above whose name
    // includes MULTITOKEN_HEADER, then zero or more of these, and then XTERMCC_MULTITOKEN_END.
    XTERMCC_MULTITOKEN_BODY,
    XTERMCC_MULTITOKEN_END,

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

    // DCS
    DCS_REQUEST_TERMCAP_TERMINFO,  // Request Termcap/Terminfo String
    // https://gitlab.com/gnachman/iterm2/wikis/synchronized-updates-spec
    DCS_BEGIN_SYNCHRONIZED_UPDATE,
    DCS_END_SYNCHRONIZED_UPDATE,
    DCS_SIXEL,
    DCS_DECRQSS,
    DCS_DECRSPS_DECCIR,
    DCS_DECRSPS_DECTABSR,
    DCS_XTSETTCAP,

    // Toggle between ansi/vt52
    STRICT_ANSI_MODE,

    // iTerm extension
    ITERM_USER_NOTIFICATION,
    DCS_TMUX_HOOK,  // Enter tmux mode

    // Wraps an escape code. The escape code is in csi.string.
    DCS_TMUX_CODE_WRAP,

    TMUX_LINE,  // A line of input from tmux
    TMUX_EXIT,  // Exit tmux mode

    // Ambiguous codes - disambiguated at execution time.
    VT100CSI_DECSLRM_OR_ANSICSI_SCP,

    // ISO-2022 codes for choosing character encoding. There are a bunch of other encodings that
    // there are escape codes for but they're really old-fashioned, so only these two are supported
    // so far.
    ISO2022_SELECT_LATIN_1,
    ISO2022_SELECT_UTF_8,

    DCS_SSH_HOOK,
    SSH_INIT,
    SSH_LINE,
    SSH_UNHOOK,  // Leave conductor mode and behave like a regular session
    SSH_BEGIN,
    SSH_END,   // At the end of a command
    SSH_OUTPUT,  // %output
    SSH_TERMINATE,  // %terminate
    SSH_RECOVERY_BOUNDARY
} VT100TerminalTokenType;

// A preinitialized array of screen_char_t. When ASCII data is present, it will have the codes
// populated and all other fields zeroed out.
#define kStaticScreenCharsCount 16
typedef struct {
    screen_char_t *buffer;
    int length;
    screen_char_t staticBuffer[kStaticScreenCharsCount];
} ScreenChars;

// Tokens with type VT100_ASCIISTRING are stored in |asciiData| with this type.
// |buffer| will point at |staticBuffer| or a malloc()ed buffer, depending on
// |length|.
typedef struct {
    char *buffer;
    int length;
    char staticBuffer[128];
    ScreenChars *screenChars;
} AsciiData;

#define SSH_OUTPUT_AUTOPOLL_PID -1000
typedef struct {
    int8_t channel;
    int32_t pid;
    int depth: 23;
    unsigned int valid: 1;
} SSHInfo;

NS_INLINE NSString *SSHInfoDescription(SSHInfo info) {
    if (!info.valid) {
        return @"<SSHInfo: invalid>";
    }
    return [NSString stringWithFormat:@"<SSHInfo: channel=%@ pid=%@ depth=%@>",
            @(info.channel), @(info.pid), @(info.depth)];
}

@interface VT100Token : NSObject {
@public
    VT100TerminalTokenType type;

    // data is populated because the current mode uses the raw input. data is
    // always set for ascii strings regardless of mode.
    BOOL savingData;

    unsigned char code;  // For VT100_UNKNOWNCHAR and VT100CSI_SCS0...SCS3.
}

// For VT100_STRING
@property(nonatomic, retain) NSString *string;

// For saved data (when copying to clipboard) or sixel payload.
@property(nonatomic, retain) NSData *savedData;

// For XTERMCC_SET_KVP.
@property(nonatomic, retain) NSString *kvpKey;
@property(nonatomic, retain) NSString *kvpValue;

// For VT100CSI_ codes that take parameters.
@property(nonatomic, readonly) CSIParam *csi;

// Is this an ascii string?
@property(nonatomic, readonly) BOOL isAscii;

// Is this a string or ascii string?
@property(nonatomic, readonly) BOOL isStringType;

// For ascii strings (type==VT100_ASCIISTRING).
@property(nonatomic, readonly) AsciiData *asciiData;
@property(nonatomic) VT100TerminalTokenType type;
@property(nonatomic) SSHInfo sshInfo;

+ (instancetype)token;
+ (instancetype)newTokenForControlCharacter:(unsigned char)controlCharacter;

- (void)setAsciiBytes:(char *)bytes length:(int)length;

// Returns a string for |asciiData|, for convenience (this is slow).
- (NSString *)stringForAsciiData;

- (void)translateFromScreenTerminal;

@end
