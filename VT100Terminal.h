// Parses input into escape codes, text, etc. Although it's called VT100Terminal, it's more of an
// xterm emulator. The real work of acting on escape codes is handled by the delegate.

#import <Cocoa/Cocoa.h>
#import "iTermCursor.h"
#import "ScreenChar.h"
#import "VT100Grid.h"

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

#define VT100CSIPARAM_MAX    16  // Maximum number of CSI parameters in VT100TCC.u.csi.p.

// A parsed token.
typedef struct {
    VT100TerminalTokenType type;
    unsigned char *position;  // Pointer into stream of where this token's data began.
    int length;  // Length of parsed data in stream.
    union {
        NSString *string;  // For VT100_STRING, VT100_ASCIISTRING
        unsigned char code;  // For VT100_UNKNOWNCHAR and VT100CSI_SCS0...SCS3.
        struct {  // For CSI codes.
            int p[VT100CSIPARAM_MAX];  // Array of CSI parameters.
            int count;  // Number of values in p.
            BOOL question; // used by old parser
            int modifier;  // used by old parser
        } csi;
    } u;
} VT100TCC;

typedef enum {
    MOUSE_REPORTING_NONE = -1,
    MOUSE_REPORTING_NORMAL = 0,
    MOUSE_REPORTING_HILITE = 1,
    MOUSE_REPORTING_BUTTON_MOTION = 2,
    MOUSE_REPORTING_ALL_MOTION = 3,
} MouseMode;

typedef enum {
    MOUSE_FORMAT_XTERM = 0,       // Regular 1000 mode
    MOUSE_FORMAT_XTERM_EXT = 1,   // UTF-8 1005 mode
    MOUSE_FORMAT_URXVT = 2,       // rxvt's 1015 mode
    MOUSE_FORMAT_SGR = 3          // SGR 1006 mode
} MouseFormat;

typedef enum {
    // X11 button number
    MOUSE_BUTTON_LEFT = 0,       // left button
    MOUSE_BUTTON_MIDDLE = 1,     // middle button
    MOUSE_BUTTON_RIGHT = 2,      // right button
    MOUSE_BUTTON_NONE = 3,       // no button pressed - for 1000/1005/1015 mode
    MOUSE_BUTTON_SCROLLDOWN = 4, // scroll down
    MOUSE_BUTTON_SCROLLUP = 5    // scroll up
} MouseButtonNumber;

// Indexes into key_strings.
typedef enum {
    TERMINFO_KEY_LEFT, TERMINFO_KEY_RIGHT, TERMINFO_KEY_UP, TERMINFO_KEY_DOWN,
    TERMINFO_KEY_HOME, TERMINFO_KEY_END, TERMINFO_KEY_PAGEDOWN,
    TERMINFO_KEY_PAGEUP, TERMINFO_KEY_F0, TERMINFO_KEY_F1, TERMINFO_KEY_F2,
    TERMINFO_KEY_F3, TERMINFO_KEY_F4, TERMINFO_KEY_F5, TERMINFO_KEY_F6,
    TERMINFO_KEY_F7, TERMINFO_KEY_F8, TERMINFO_KEY_F9, TERMINFO_KEY_F10,
    TERMINFO_KEY_F11, TERMINFO_KEY_F12, TERMINFO_KEY_F13, TERMINFO_KEY_F14,
    TERMINFO_KEY_F15, TERMINFO_KEY_F16, TERMINFO_KEY_F17, TERMINFO_KEY_F18,
    TERMINFO_KEY_F19, TERMINFO_KEY_F20, TERMINFO_KEY_F21, TERMINFO_KEY_F22,
    TERMINFO_KEY_F23, TERMINFO_KEY_F24, TERMINFO_KEY_F25, TERMINFO_KEY_F26,
    TERMINFO_KEY_F27, TERMINFO_KEY_F28, TERMINFO_KEY_F29, TERMINFO_KEY_F30,
    TERMINFO_KEY_F31, TERMINFO_KEY_F32, TERMINFO_KEY_F33, TERMINFO_KEY_F34,
    TERMINFO_KEY_F35, TERMINFO_KEY_BACKSPACE, TERMINFO_KEY_BACK_TAB,
    TERMINFO_KEY_TAB, TERMINFO_KEY_DEL, TERMINFO_KEY_INS, TERMINFO_KEY_HELP,
    TERMINFO_KEYS
} VT100TerminalTerminfoKeys;

#define NUM_CHARSETS 4  // G0...G3. Values returned from -charset go from 0 to this.
#define NUM_MODIFIABLE_RESOURCES 5

@protocol VT100TerminalDelegate
// Append a string at the cursor's position and advance the cursor, scrolling if necessary. If
// |ascii| is set then the string contains only ascii characters.
- (void)terminalAppendString:(NSString *)string isAscii:(BOOL)isAscii;

// Play/display the bell.
- (void)terminalRingBell;

// Move the cursor back, possibly wrapping around to the previous line.
- (void)terminalBackspace;

// Move the cursor to the next tab stop, erasing until that point.
- (void)terminalAppendTabAtCursor;

// Move the cursor down, scrolling if necessary.
- (void)terminalLineFeed;

// Move the cursor left one place.
- (void)terminalCursorLeft:(int)n;

// Move the cursor down one row.
- (void)terminalCursorDown:(int)n;

// Move the cursor right one place.
- (void)terminalCursorRight:(int)n;

// Move the cursor up one row.
- (void)terminalCursorUp:(int)n;

// Move the cursor to a 1-based coordinate.
- (void)terminalMoveCursorToX:(int)x y:(int)y;

// Returns if it's safe to send reports.
- (BOOL)terminalShouldSendReport;

// Sends a report.
- (void)terminalSendReport:(NSData *)report;

// Replaces the screen contents with a test pattern.
- (void)terminalShowTestPattern;

// Restores the cursor position and charset flags.
- (void)terminalRestoreCursorAndCharsetFlags;

// Saves the cursor position and charset flags.
- (void)terminalSaveCursorAndCharsetFlags;

// Returns the cursor's position relative to the scroll region's origin. 1-based.
- (int)terminalRelativeCursorX;

// Returns the cursor's position relative to the scroll region's origin. 1-based.
- (int)terminalRelativeCursorY;

// Reset the top/bottom scroll region.
- (void)terminalResetTopBottomScrollRegion;

// Set the top/bottom scrollr egion.
- (void)terminalSetScrollRegionTop:(int)top bottom:(int)bottom;

// Erase all characters before the cursor and/or after the cursor.
- (void)terminalEraseInDisplayBeforeCursor:(BOOL)before afterCursor:(BOOL)after;

// Erase all lines before/after the cursor. If erasing both, the screen is copied into the
// scrollback buffer.
- (void)terminalEraseLineBeforeCursor:(BOOL)before afterCursor:(BOOL)after;

// Set a tabstop at the current cursor column.
- (void)terminalSetTabStopAtCursor;

// Move the cursor to the left margin.
- (void)terminalCarriageReturn;

// Scroll down one line.
- (void)terminalIndex;

// Scroll up one line.
- (void)terminalReverseIndex;

// Clear the screen, preserving the cursor's line.
- (void)terminalResetPreservingPrompt:(BOOL)preservePrompt;

// Saves the cursor, resets the scroll region, and restores the cursor position and charset flags.
- (void)terminalSoftReset;

// Changes the cursor type.
- (void)terminalSetCursorType:(ITermCursorType)cursorType;

// Changes whether the cursor blinks.
- (void)terminalSetCursorBlinking:(BOOL)blinking;

// Sets the left/right scroll region.
- (void)terminalSetLeftMargin:(int)scrollLeft rightMargin:(int)scrollRight;

// Sets whether one charset is in linedrawing mode.
- (void)terminalSetCharset:(int)charset toLineDrawingMode:(BOOL)lineDrawingMode;

// Remove all tab stops.
- (void)terminalRemoveTabStops;

// Remove the tab stop at the cursor's current column.
- (void)terminalRemoveTabStopAtCursor;

// Tries to resize the screen to |width|.
- (void)terminalSetWidth:(int)width;

// Moves cursor to previous tab stop.
- (void)terminalBackTab;

// Sets the cursor's x coordinate. 1-based.
- (void)terminalSetCursorX:(int)x;

// Sets the cursor's y coordinate. 1-based.
- (void)terminalSetCursorY:(int)y;

// Erases some number of characters after the cursor, replacing them with blanks.
- (void)terminalEraseCharactersAfterCursor:(int)j;

// Send the current print buffer to the printer.
- (void)terminalPrintBuffer;

// Future input (linefeeds, carriage returns, and appended strings) should be saved for printing and not displayed.
- (void)terminalBeginRedirectingToPrintBuffer;

// Send the current screen contents to the printer.
- (void)terminalPrintScreen;

// Sets the window's title.
- (void)terminalSetWindowTitle:(NSString *)title;

// Sets the icon's title.
- (void)terminalSetIconTitle:(NSString *)title;

// Pastes a string to the shell.
- (void)terminalPasteString:(NSString *)string;

// Inserts |n| blank chars after the cursor, moving chars to the right of them over.
- (void)terminalInsertEmptyCharAtCursor:(int)n;

// Inserts |n| blank lines after the cursor, moving lines below them down.
- (void)terminalInsertBlankLinesAfterCursor:(int)n;

// Deletes |n| characters after the cursor, moving later chars left.
- (void)terminalDeleteCharactersAtCursor:(int)n;

// Deletes |n| lines after the cursor, moving later lines up.
- (void)terminalDeleteLinesAtCursor:(int)n;

// Tries to resize the screen to |rows| by |columns|.
- (void)terminalSetRows:(int)rows andColumns:(int)columns;

// Tries to resize the window to the given pixel size.
- (void)terminalSetPixelWidth:(int)width height:(int)height;

// Tries to move the window's top left coordinate to the given point.
- (void)terminalMoveWindowTopLeftPointTo:(NSPoint)point;

// Either miniaturizes or unminiaturizes, depending on |mini|.
- (void)terminalMiniaturize:(BOOL)mini;

// Either raises or iconfies, depending on |raise|.
- (void)terminalRaise:(BOOL)raise;

// Scroll the screen's scroll region up by |n| lines.
- (void)terminalScrollUp:(int)n;

// Scroll the screen's scroll region down by |n| lines.
- (void)terminalScrollDown:(int)n;

// Returns if the window is miniaturized.
- (BOOL)terminalWindowIsMiniaturized;

// Returns the top-left pixel coordinate of the window.
- (NSPoint)terminalWindowTopLeftPixelCoordinate;

// Returns the size of the window in rows/columns.
- (int)terminalWindowWidth;
- (int)terminalWindowHeight;

// Returns the size of the screen the window is on in cells.
- (int)terminalScreenHeightInCells;
- (int)terminalScreenWidthInCells;

// Returns the current icon (tab)/window title.
- (NSString *)terminalIconTitle;
- (NSString *)terminalWindowTitle;

// Saves the current window/icon (depending on isWindow) title in a stack.
- (void)terminalPushCurrentTitleForWindow:(BOOL)isWindow;

// Restores the window/icon (depending on isWindow) title from a stack.
- (void)terminalPopCurrentTitleForWindow:(BOOL)isWindow;

// Posts a message to Growl.
- (void)terminalPostGrowlNotification:(NSString *)message;

// Enters Tmux mode.
- (void)terminalStartTmuxMode;

// Returns the size of the terminal in cells.
- (int)terminalWidth;
- (int)terminalHeight;

// Called when the mouse reporting mode changes.
- (void)terminalMouseModeDidChangeTo:(MouseMode)mouseMode;

// Called when the terminal needs to be redrawn.
- (void)terminalNeedsRedraw;

// Sets whether the left/right scroll region should be used.
- (void)terminalSetUseColumnScrollRegion:(BOOL)use;
- (BOOL)terminalUseColumnScrollRegion;

// Switches the currently visible buffer.
- (void)terminalShowAltBuffer;
- (void)terminalShowPrimaryBuffer;

// Clears the screen, preserving the wrapped line the cursor is on.
- (void)terminalClearScreen;

// Not quite sure, kind of a mess right now. See comment in -[PTYSession setSendModifiers:].
- (void)terminalSendModifiersDidChangeTo:(int *)modifiers
                               numValues:(int)numValues;

// Sets a color table entry.
- (void)terminalColorTableEntryAtIndex:(int)theIndex didChangeToColor:(NSColor *)theColor;

// Saves the current scroll position in the window.
- (void)terminalSaveScrollPosition;

// Make the current terminal visible and give it keyboard focus.
- (void)terminalStealFocus;

// Erase the screen (preserving the line the cursor is on) and the scrollback buffer.
- (void)terminalClearBuffer;

// Called when the current directory may have changed.
- (void)terminalCurrentDirectoryDidChangeTo:(NSString *)value;

// The profile should change to one with the name |value|.
- (void)terminalProfileShouldChangeTo:(NSString *)value;

// Sets the current pasteboard. Legal values are ruler, find, and font. Other values, including
// empty string, are treated as the default pasteboard.
- (void)terminalSetPasteboard:(NSString *)value;

// Signal the user that the terminal wants attention.
- (void)terminalRequestAttention:(BOOL)request;

// Set various colors.
- (void)terminalSetForegroundColor:(NSColor *)color;
- (void)terminalSetBackgroundGColor:(NSColor *)color;
- (void)terminalSetBoldColor:(NSColor *)color;
- (void)terminalSetSelectionColor:(NSColor *)color;
- (void)terminalSetSelectedTextColor:(NSColor *)color;
- (void)terminalSetCursorColor:(NSColor *)color;
- (void)terminalSetCursorTextColor:(NSColor *)color;
- (void)terminalSetColorTableEntryAtIndex:(int)n color:(NSColor *)color;

// Change the color tint of the current tab.
- (void)terminalSetCurrentTabColor:(NSColor *)color;
- (void)terminalSetTabColorRedComponentTo:(CGFloat)color;
- (void)terminalSetTabColorGreenComponentTo:(CGFloat)color;
- (void)terminalSetTabColorBlueComponentTo:(CGFloat)color;

// Returns the current cursor position.
- (int)terminalCursorX;
- (int)terminalCursorY;

// Shows/hides the cursor.
- (void)terminalSetCursorVisible:(BOOL)visible;

@end

@interface VT100Terminal : NSObject <VT100GridDelegate>
{
    NSString          *termType;
    NSStringEncoding  ENCODING;
    id<VT100TerminalDelegate> delegate_;

    unsigned char     *STREAM;
    int               current_stream_length;
    int               total_stream_length;

    BOOL LINE_MODE;         // YES=Newline, NO=Line feed
    BOOL CURSOR_MODE;       // YES=Application, NO=Cursor
    BOOL ANSI_MODE;         // YES=ANSI, NO=VT52
    BOOL COLUMN_MODE;       // YES=132 Column, NO=80 Column
    BOOL SCROLL_MODE;       // YES=Smooth, NO=Jump
    BOOL SCREEN_MODE;       // YES=Reverse, NO=Normal
    BOOL ORIGIN_MODE;       // YES=Relative, NO=Absolute
    BOOL WRAPAROUND_MODE;   // YES=On, NO=Off
    BOOL AUTOREPEAT_MODE;   // YES=On, NO=Off
    BOOL INTERLACE_MODE;    // YES=On, NO=Off
    BOOL KEYPAD_MODE;       // YES=Application, NO=Numeric
    BOOL INSERT_MODE;       // YES=Insert, NO=Replace
    int  CHARSET;           // G0...G3
    BOOL XON;               // YES=XON, NO=XOFF
    BOOL numLock;           // YES=ON, NO=OFF, default=YES;
    BOOL shouldBounceDockIcon; // YES=Bounce, NO=cancel;
    MouseMode MOUSE_MODE;
    MouseFormat MOUSE_FORMAT;
    BOOL REPORT_FOCUS;

    int FG_COLORCODE;
    int FG_GREEN;
    int FG_BLUE;
    ColorMode FG_COLORMODE;
    int BG_COLORCODE;
    int BG_GREEN;
    int BG_BLUE;
    ColorMode BG_COLORMODE;
    int bold, italic, under, blink, reversed;

    int saveBold, saveItalic, saveUnder, saveBlink, saveReversed;
    int saveCHARSET;
    int saveForeground;
    int saveFgGreen;
    int saveFgBlue;
    ColorMode saveFgColorMode;
    int saveBackground;
    int saveBgGreen;
    int saveBgBlue;
    ColorMode saveBgColorMode;

    BOOL TRACE;

    BOOL strictAnsiMode;
    BOOL allowColumnMode;

    BOOL allowKeypadMode;

    int streamOffset;

    BOOL IS_ANSI;
    BOOL disableSmcupRmcup;
    BOOL useCanonicalParser;

    // Indexed by values in VT100TerminalTerminfoKeys. Gives strings to send for various special keys.
    char *key_strings[TERMINFO_KEYS];

    // http://www.xfree86.org/current/ctlseqs.html#Bracketed%20Paste%20Mode
    BOOL bracketedPasteMode_;
    int sendModifiers_[NUM_MODIFIABLE_RESOURCES];
}

@property(nonatomic, assign) id<VT100TerminalDelegate> delegate;

+ (void)initialize;

- (id)init;
- (void)dealloc;

- (NSString *)termtype;
- (void)setTermType:(NSString *)termtype;

- (BOOL)trace;
- (void)setTrace:(BOOL)flag;

- (BOOL)strictAnsiMode;
- (void)setStrictAnsiMode: (BOOL)flag;

- (BOOL)allowColumnMode;
- (void)setAllowColumnMode: (BOOL)flag;

- (NSStringEncoding)encoding;
- (void)setEncoding:(NSStringEncoding)encoding;

- (void)cleanStream;
- (void)putStreamData:(NSData*)data;
- (VT100TCC)getNextToken;
- (NSData *)streamData;
- (void)clearStream;

- (void)saveCursorAttributes;
- (void)restoreCursorAttributes;

- (void)setForegroundColor:(int)fgColorCode alternateSemantics:(BOOL)altsem;
- (void)setBackgroundColor:(int)bgColorCode alternateSemantics:(BOOL)altsem;

- (void)resetCharset;
- (void)reset;
- (void)resetPreservingPrompt:(BOOL)preservePrompt;

- (NSData *)keyArrowUp:(unsigned int)modflag;
- (NSData *)keyArrowDown:(unsigned int)modflag;
- (NSData *)keyArrowLeft:(unsigned int)modflag;
- (NSData *)keyArrowRight:(unsigned int)modflag;
- (NSData *)keyHome:(unsigned int)modflag;
- (NSData *)keyEnd:(unsigned int)modflag;
- (NSData *)keyInsert;
- (NSData *)keyDelete;
- (NSData *)keyBackspace;
- (NSData *)keyPageUp:(unsigned int)modflag;
- (NSData *)keyPageDown:(unsigned int)modflag;
- (NSData *)keyFunction:(int)no;
- (NSData *)keypadData: (unichar) unicode keystr: (NSString *) keystr;

- (char *)mouseReport:(int)button atX:(int)x Y:(int)y;
- (BOOL)reportFocus;
- (NSData *)mousePress:(int)button withModifiers:(unsigned int)modflag atX:(int)x Y:(int)y;
- (NSData *)mouseRelease:(int)button withModifiers:(unsigned int)modflag atX:(int)x Y:(int)y;
- (NSData *)mouseMotion:(int)button withModifiers:(unsigned int)modflag atX:(int)x Y:(int)y;

- (BOOL)lineMode;
- (BOOL)cursorMode;
- (BOOL)columnMode;
- (BOOL)scrollMode;
- (BOOL)screenMode;
- (BOOL)originMode;
- (BOOL)wraparoundMode;
- (BOOL)isAnsi;
- (BOOL)autorepeatMode;
- (BOOL)interlaceMode;
- (BOOL)keypadMode;
- (BOOL)insertMode;
- (int)charset;
- (BOOL)xon;
- (MouseMode)mouseMode;

- (screen_char_t)foregroundColorCode;
- (screen_char_t)backgroundColorCode;
- (screen_char_t)foregroundColorCodeReal;
- (screen_char_t)backgroundColorCodeReal;

- (NSData *)reportActivePositionWithX:(int)x Y:(int)y withQuestion:(BOOL)q;
- (NSData *)reportStatus;
- (NSData *)reportDeviceAttribute;
- (NSData *)reportSecondaryDeviceAttribute;

- (void)_setMode:(VT100TCC)token;
- (void)_setCharAttr:(VT100TCC)token;
- (void)_setRGB:(VT100TCC)token;

- (void)setDisableSmcupRmcup:(BOOL)value;
- (void)setUseCanonicalParser:(BOOL)value;

- (BOOL)bracketedPasteMode;

- (void)setInsertMode:(BOOL)mode;
- (void)setCursorMode:(BOOL)mode;
- (void)setKeypadMode:(BOOL)mode;
- (void)setMouseMode:(MouseMode)mode;
- (void)setMouseFormat:(MouseFormat)format;

// Call appropriate delegate methods to handle token.
- (void)executeToken:(VT100TCC)token;

@end

