// Parses input into escape codes, text, etc. Although it's called VT100Terminal, it's more of an
// xterm emulator. The real work of acting on escape codes is handled by the delegate.

#import <Cocoa/Cocoa.h>
#import "iTermCursor.h"
#import "ScreenChar.h"
#import "VT100Grid.h"

typedef struct VT100TCC VT100TCC;

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
- (BOOL)terminalIsAppendingToPasteboard;
- (void)terminalAppendDataToPasteboard:(NSData *)data;

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
    BOOL KEYPAD_MODE;       // YES=Application, NO=Numeric
    BOOL INSERT_MODE;       // YES=Insert, NO=Replace
    int  CHARSET;           // G0...G3
    BOOL XON;               // YES=XON, NO=XOFF. Not currently used.
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

    VT100TCC *lastToken_;
}

@property(nonatomic, assign) id<VT100TerminalDelegate> delegate;

- (id)init;
- (void)dealloc;

- (void)setTermType:(NSString *)termtype;

- (NSStringEncoding)encoding;
- (void)setEncoding:(NSStringEncoding)encoding;

- (void)putStreamData:(NSData*)data;

// Returns true if a new token was parsed, false if there was nothing left to do.
- (BOOL)parseNextToken;
- (NSData *)streamData;
- (void)clearStream;

- (void)setForegroundColor:(int)fgColorCode alternateSemantics:(BOOL)altsem;
- (void)setBackgroundColor:(int)bgColorCode alternateSemantics:(BOOL)altsem;

- (void)resetCharset;
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

- (BOOL)reportFocus;
- (NSData *)mousePress:(int)button withModifiers:(unsigned int)modflag atX:(int)x Y:(int)y;
- (NSData *)mouseRelease:(int)button withModifiers:(unsigned int)modflag atX:(int)x Y:(int)y;
- (NSData *)mouseMotion:(int)button withModifiers:(unsigned int)modflag atX:(int)x Y:(int)y;

- (BOOL)screenMode;  // Reversed text?
- (BOOL)originMode;
- (BOOL)wraparoundMode;
- (BOOL)isAnsi;
- (BOOL)autorepeatMode;
- (BOOL)insertMode;
- (int)charset;
- (MouseMode)mouseMode;

- (screen_char_t)foregroundColorCode;
- (screen_char_t)backgroundColorCode;
- (screen_char_t)foregroundColorCodeReal;
- (screen_char_t)backgroundColorCodeReal;

- (NSData *)reportActivePositionWithX:(int)x Y:(int)y withQuestion:(BOOL)q;

- (void)setDisableSmcupRmcup:(BOOL)value;
- (void)setUseCanonicalParser:(BOOL)value;

- (BOOL)bracketedPasteMode;

- (void)setInsertMode:(BOOL)mode;
- (void)setCursorMode:(BOOL)mode;
- (void)setKeypadMode:(BOOL)mode;
- (void)setMouseMode:(MouseMode)mode;
- (void)setMouseFormat:(MouseFormat)format;

// Call appropriate delegate methods to handle the last parsed token. Call this after -parseNextToken
// returns YES.
- (void)executeToken;

// Inspect previous parsed token. Can use after -parseNextToken returns YES.
- (BOOL)lastTokenWasASCII;
- (NSString *)lastTokenString;

@end

