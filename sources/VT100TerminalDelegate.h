//
//  VT100TerminalDelegate.h
//  iTerm
//
//  Created by George Nachman on 10/26/13.
//
//

#import <Foundation/Foundation.h>
#import "VT100Token.h"

typedef NS_ENUM(NSInteger, MouseMode) {
    MOUSE_REPORTING_NONE = -1,
    MOUSE_REPORTING_NORMAL = 0,
    MOUSE_REPORTING_HILITE = 1,
    MOUSE_REPORTING_BUTTON_MOTION = 2,
    MOUSE_REPORTING_ALL_MOTION = 3,
};

typedef NS_ENUM(NSInteger, VT100TerminalSemanticTextType) {
    kVT100TerminalSemanticTextTypeFilename = 1,
    kVT100TerminalSemanticTextTypeDirectory = 2,
    kVT100TerminalSemanticTextTypeProcessId = 3,

    kVT100TerminalSemanticTextTypeMax
};

typedef NS_ENUM(NSInteger, VT100TerminalUnits) {
    kVT100TerminalUnitsCells,
    kVT100TerminalUnitsPixels,
    kVT100TerminalUnitsPercentage,
    kVT100TerminalUnitsAuto,
};

@protocol VT100TerminalDelegate <NSObject>
// Append a string at the cursor's position and advance the cursor, scrolling if necessary.
- (void)terminalAppendString:(NSString *)string;
- (void)terminalAppendAsciiData:(AsciiData *)asciiData;

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
- (void)terminalCursorDown:(int)n andToStartOfLine:(BOOL)toStart;

// Move the cursor right one place.
- (void)terminalCursorRight:(int)n;

// Move the cursor up one row.
- (void)terminalCursorUp:(int)n andToStartOfLine:(BOOL)toStart;

// Move the cursor to a 1-based coordinate.
- (void)terminalMoveCursorToX:(int)x y:(int)y;

// Returns if it's safe to send reports.
- (BOOL)terminalShouldSendReport;

// Sends a report.
- (void)terminalSendReport:(NSData *)report;

// Replaces the screen contents with a test pattern.
- (void)terminalShowTestPattern;

// Returns the cursor's position relative to the scroll region's origin. 1-based.
- (int)terminalRelativeCursorX;

// Returns the cursor's position relative to the scroll region's origin. 1-based.
- (int)terminalRelativeCursorY;

// Set the top/bottom scroll region. 0-based. Inclusive.
- (void)terminalSetScrollRegionTop:(int)top bottom:(int)bottom;

// Returns the scroll region, or the whole screen if none is set.
- (VT100GridRect)terminalScrollRegion;

// Sums the visible characters in the given rectangle onscreen.
- (int)terminalChecksumInRectangle:(VT100GridRect)rect;

// Erase all characters before the cursor and/or after the cursor.
- (void)terminalEraseInDisplayBeforeCursor:(BOOL)before afterCursor:(BOOL)after;

// Erase all lines before/after the cursor. If erasing both, the screen is copied into the
// scrollback buffer.
- (void)terminalEraseLineBeforeCursor:(BOOL)before afterCursor:(BOOL)after;

// Set a tabstop at the current cursor column.
- (void)terminalSetTabStopAtCursor;

// Move the cursor to the left margin.
- (void)terminalCarriageReturn;

// Scroll up one line.
- (void)terminalReverseIndex;

// Clear the screen, preserving the cursor's line.
- (void)terminalResetPreservingPrompt:(BOOL)preservePrompt;

// Changes the cursor type.
- (void)terminalSetCursorType:(ITermCursorType)cursorType;

// Changes whether the cursor blinks.
- (void)terminalSetCursorBlinking:(BOOL)blinking;

// Sets the left/right scroll region.
- (void)terminalSetLeftMargin:(int)scrollLeft rightMargin:(int)scrollRight;

// Sets whether one charset is in linedrawing mode.
- (void)terminalSetCharset:(int)charset toLineDrawingMode:(BOOL)lineDrawingMode;
- (BOOL)terminalLineDrawingFlagForCharset:(int)index;

// Remove all tab stops.
- (void)terminalRemoveTabStops;

// Remove the tab stop at the cursor's current column.
- (void)terminalRemoveTabStopAtCursor;

// Tries to resize the screen to |width|.
- (void)terminalSetWidth:(int)width;

// Moves cursor to previous tab stop.
- (void)terminalBackTab:(int)n;

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
- (void)terminalInsertEmptyCharsAtCursor:(int)n;

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

// Returns the size of the window in pixels.
- (int)terminalWindowWidthInPixels;
- (int)terminalWindowHeightInPixels;

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

// Posts a message to Growl/Notiication center. Returns YES if the message was posted.
- (BOOL)terminalPostGrowlNotification:(NSString *)message;

// Enters Tmux mode.
- (void)terminalStartTmuxMode;

// Handles input during tmux mode. A single line of input will be in the token's string.
- (void)terminalHandleTmuxInput:(VT100Token *)token;

// Are we currently in tmux mode?
- (BOOL)terminalInTmuxMode;

// Returns the size of the terminal in cells.
- (int)terminalWidth;
- (int)terminalHeight;

// Returns the size of a single cell. May contain non-integer values.
- (NSSize)terminalCellSizeInPoints;

// Called when the mouse reporting mode changes.
- (void)terminalMouseModeDidChangeTo:(MouseMode)mouseMode;

// Called when the terminal needs to be redrawn.
- (void)terminalNeedsRedraw;

// Sets whether the left/right scroll region should be used.
- (void)terminalSetUseColumnScrollRegion:(BOOL)use;
- (BOOL)terminalUseColumnScrollRegion;

// Switches the currently visible buffer.
- (void)terminalShowAltBuffer;
- (BOOL)terminalIsShowingAltBuffer;

// Show main (primary) buffer. Does nothing if already on the alt grid.
- (void)terminalShowPrimaryBuffer;

// Clears the screen, preserving the wrapped line the cursor is on.
- (void)terminalClearScreen;

// Erase scrollback history, leave screen alone.
- (void)terminalClearScrollbackBuffer;

// Saves the current scroll position in the window.
- (void)terminalSaveScrollPositionWithArgument:(NSString *)argument;

// Make the current terminal visible and give it keyboard focus.
- (void)terminalStealFocus;

// Erase the screen (preserving the line the cursor is on) and the scrollback buffer.
- (void)terminalClearBuffer;

// Called when the current directory may have changed.
- (void)terminalCurrentDirectoryDidChangeTo:(NSString *)value;

// Sets the username@hostname or hostname of the current cursor location.
- (void)terminalSetRemoteHost:(NSString *)remoteHost;

// The profile should change to one with the name |value|.
- (void)terminalProfileShouldChangeTo:(NSString *)value;

// Set a note. Value is message or length|message or x|y|length|message
- (void)terminalAddNote:(NSString *)value show:(BOOL)show;

// Sets the current pasteboard. Legal values are ruler, find, and font. Other values, including
// empty string, are treated as the default pasteboard.
- (void)terminalSetPasteboard:(NSString *)value;
- (void)terminalCopyBufferToPasteboard;
- (BOOL)terminalIsAppendingToPasteboard;
- (void)terminalAppendDataToPasteboard:(NSData *)data;

// Download of a base64-encoded file
// nil = name unknown, -1 = size unknown.
- (void)terminalWillReceiveFileNamed:(NSString *)name ofSize:(int)size;
- (void)terminalWillReceiveInlineFileNamed:(NSString *)name
                                    ofSize:(int)size
                                     width:(int)width
                                     units:(VT100TerminalUnits)widthUnits
                                    height:(int)height
                                     units:(VT100TerminalUnits)heightUnits
                       preserveAspectRatio:(BOOL)preserveAspectRatio
                                     inset:(NSEdgeInsets)inset;

// Download completed normally
- (void)terminalDidFinishReceivingFile;

// Got another chunk of base-64 encoded data for the current download.
// Preceded by terminalWillReceiveFileNamed:size:.
- (void)terminalDidReceiveBase64FileData:(NSString *)data;

// Got bogus data, abort download.
// Preceded by terminalWillReceiveFileNamed:size: and possibly some
// terminalDidReceiveBase64FileData: calls.
- (void)terminalFileReceiptEndedUnexpectedly;

// Signal the user that the terminal wants attention.
- (void)terminalRequestAttention:(BOOL)request;

// Set various colors.
- (void)terminalSetForegroundColor:(NSColor *)color;
- (void)terminalSetBackgroundColor:(NSColor *)color;
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

- (NSColor *)terminalColorForIndex:(int)index;

// Returns the current cursor position.
- (int)terminalCursorX;
- (int)terminalCursorY;

// Shows/hides the cursor.
- (void)terminalSetCursorVisible:(BOOL)visible;

- (void)terminalSetHighlightCursorLine:(BOOL)highlight;

// FinalTerm features
- (void)terminalPromptDidStart;
- (void)terminalCommandDidStart;
- (void)terminalCommandDidEnd;
- (void)terminalSemanticTextDidStartOfType:(VT100TerminalSemanticTextType)type;
- (void)terminalSemanticTextDidEndOfType:(VT100TerminalSemanticTextType)type;
- (void)terminalProgressAt:(double)fraction label:(NSString *)label;
- (void)terminalProgressDidFinish;
- (void)terminalReturnCodeOfLastCommandWas:(int)returnCode;
- (void)terminalFinalTermCommand:(NSArray *)argv;
- (void)terminalSetShellIntegrationVersion:(NSString *)version;
- (void)terminalAbortCommand;

// Flag changes
- (void)terminalWraparoundModeDidChangeTo:(BOOL)newValue;
- (void)terminalTypeDidChange;
- (void)terminalInsertModeDidChangeTo:(BOOL)newValue;

- (NSString *)terminalProfileName;

- (void)terminalSetBackgroundImageFile:(NSString *)filename;
- (void)terminalSetBadgeFormat:(NSString *)badge;
- (void)terminalSetUserVar:(NSString *)kvp;

- (BOOL)terminalFocusReportingEnabled;

- (BOOL)terminalIsTrusted;

@end
