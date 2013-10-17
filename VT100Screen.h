#import <Cocoa/Cocoa.h>
#import "DVR.h"
#import "LineBuffer.h"
#import "PTYTextViewDataSource.h"
#import "VT100Terminal.h"

@class iTermGrowlDelegate;
@class PTYTask;
@class VT100Grid;

@protocol VT100ScreenDelegate <NSObject>

// Screen contents have become dirty and should be redrawn right away.
- (void)screenNeedsRedraw;

// Update window title, tab colors, and redraw view.
- (void)screenUpdateDisplay;

// Called when the screen's size changes.
- (void)screenSizeDidChange;

// A change was made to the screen's contents which could cause a trigger to fire.
- (void)screenTriggerableChangeDidOccur;

// Returns if the profile name should be included in the window title.
- (BOOL)screenShouldSyncTitle;

// Called after text was added to the current line. Can be used to check triggers.
- (void)screenDidAppendStringToCurrentLine:(NSString *)string;

// Change the cursor's appearance.
- (void)screenSetCursorBlinking:(BOOL)blink
                     cursorType:(ITermCursorType)type;

// Returns if the screen is permitted to resize the window.
- (BOOL)screenShouldInitiateWindowResize;

// The delegate should resize the screen to the given size.
- (void)screenResizeToWidth:(int)width height:(int)height;

// Returns if terminal-initiated printing is permitted.
- (BOOL)screenShouldBeginPrinting;

// Returns the session's name, excluding the current job.
- (NSString *)screenNameExcludingJob;

// Sets the window title.
- (void)screenSetWindowTitle:(NSString *)title;

// Returns the current window title.
- (NSString *)screenWindowTitle;

// Returns the session's name as it would be displayed in the window.
- (NSString *)screenDefaultName;

// Sets the session's name.
- (void)screenSetName:(NSString *)name;

// Returns the session's current name
- (NSString *)screenName;

// Returns the window's current name
- (NSString *)screenWindowName;

// The delegate should check the current working directory and associate it with |lineNumber|, since
// it may have changed.
- (void)screenLogWorkingDirectoryAtLine:(long long)lineNumber;

// Returns if the window is full-screen.
- (BOOL)screenWindowIsFullscreen;

// Delegate should move the window's top left point to the given screen coordinate.
- (void)screenMoveWindowTopLeftPointTo:(NSPoint)point;

// Returns the NSScreen the window is primarily in.
- (NSScreen *)screenWindowScreen;

// If flag is set, the window should be miniaturized; otherwise, deminiaturize.
- (void)screenMiniaturizeWindow:(BOOL)flag;

// If flag is set, bring the window to front; if not, move to back.
- (void)screenRaise:(BOOL)flag;

// Returns if the window is miniaturized.
- (BOOL)screenWindowIsMiniaturized;

// Send input to the task.
- (void)screenWriteDataToTask:(NSData *)data;

// Returns the frame of the window this screen is.
- (NSRect)screenWindowFrame;

// Returns the rect in the view that is currently visible.
- (NSSize)screenSize;

// If the flag is set, push the current window title onto a stack; otherwise push the icon title.
- (void)screenPushCurrentTitleForWindow:(BOOL)flag;

// If the flag is set, pop the current window title from the stack; otherwise pop the icon title.
- (void)screenPopCurrentTitleForWindow:(BOOL)flag;

// Returns the screen's number (in practice, this is the tab's number that cmd-N switches to).
- (int)screenNumber;

// Returns the window's index.
- (int)screenWindowIndex;

// Returns the tab's index.
- (int)screenTabIndex;

// Returns the pane's index.
- (int)screenViewIndex;

// Requests that tmux integration mode begin.
- (void)screenStartTmuxMode;

// See comment in setSendModifiers:
- (void)screenModifiersDidChangeTo:(NSArray *)modifiers;

// Returns if ambiguous characters are treated as fullwidth.
- (BOOL)screenShouldTreatAmbiguousCharsAsDoubleWidth;

// Returns if scrolling with a full-width scroll region abutting the top of the screen should append
// to the line buffer.
- (BOOL)screenShouldAppendToScrollbackWithStatusBar;

// Requests that the bell indicator be shown, notification be posted, etc.
- (void)screenShowBellIndicator;

// Request that a string be sent for printing.
- (void)screenPrintString:(NSString *)string;

// Request that the currently visible area of the screen be sent for printing.
- (void)screenPrintVisibleArea;

// Returns if iTermTabContentsChanged notifications should be published when the view is updated.
- (BOOL)screenShouldSendContentsChangedNotification;

// PTYTextView deselect
- (void)screenRemoveSelection;

// Returns inclusive bounds of selection range, or -1 if no selection present.
- (int)screenSelectionStartX;
- (int)screenSelectionEndX;
- (int)screenSelectionStartY;
- (int)screenSelectionEndY;

// Sets inclusive bounds of selection range.
- (void)screenSetSelectionFromX:(int)startX
                          fromY:(int)startY
                            toX:(int)endX
                            toY:(int)endY;

// Returns the size in pixels of a single cell.
- (NSSize)screenCellSize;

// Remove highlights of search results.
- (void)screenClearHighlights;

// Called when the mouse reporting mode changes.
- (void)screenMouseModeDidChange;

// An image should be flashed over the view.
- (void)screenFlashImage:(FlashImage)image;

// Show/hide the cursor.
- (void)screenSetCursorVisible:(BOOL)visible;

// Returns if there is a view.
- (BOOL)screenHasView;

@end

// Dictionary keys for -highlightTextMatchingRegex:
extern NSString * const kHighlightForegroundColor;
extern NSString * const kHighlightBackgroundColor;

@interface VT100Screen : NSObject <PTYTextViewDataSource>
{
    NSMutableSet* tabStops;
    VT100Terminal *terminal_;
    PTYTask *shell_;
    id<VT100ScreenDelegate> delegate_;  // PTYSession implements this

    // BOOLs indicating, for each of the characters sets, which ones are in line-drawing mode.
    BOOL charsetUsesLineDrawingMode_[NUM_CHARSETS];
    BOOL savedCharsetUsesLineDrawingMode_[NUM_CHARSETS];
    BOOL audibleBell_;
    BOOL showBellIndicator_;
    BOOL flashBell_;
    BOOL postGrowlNotifications_;
    BOOL cursorBlinks_;
    VT100Grid *primaryGrid_;
    VT100Grid *altGrid_;  // may be nil
    VT100Grid *currentGrid_;  // Weak reference. Points to either primaryGrid or altGrid.
    
    // Max size of scrollback buffer
    unsigned int maxScrollbackLines_;
    // This flag overrides maxScrollbackLines_:
    BOOL unlimitedScrollback_;

    // How many scrollback lines have been lost due to overflow. Periodically reset with
    // -resetScrollbackOverflow.
    int scrollbackOverflow_;

    // A rarely reset count of the number of lines lost to scrollback overflow. Adding this to a
    // line number gives a unique line number that won't be reused when the linebuffer overflows.
    long long cumulativeScrollbackOverflow_;

    // When set, strings, newlines, and linefeeds are appened to printBuffer_. When ANSICSI_PRINT
    // with code 4 is received, it's sent for printing.
    BOOL collectInputForPrinting_;
    NSMutableString *printBuffer_;

    // Scrollback buffer
    LineBuffer* linebuffer_;

    // Current find context.
    FindContext findContext_;

    // Where we left off searching.
    long long savedFindContextAbsPos_;

    // Used for recording instant replay.
    DVR* dvr;
    BOOL saveToScrollbackInAlternateScreen_;

    // OK to report window title?
    BOOL allowTitleReporting_;
}

@property(nonatomic, retain) VT100Terminal *terminal;
@property(nonatomic, retain) PTYTask *shell;
@property(nonatomic, assign) BOOL audibleBell;
@property(nonatomic, assign) BOOL showBellIndicator;
@property(nonatomic, assign) BOOL flashBell;
@property(nonatomic, assign) id<VT100ScreenDelegate> delegate;
@property(nonatomic, assign) BOOL postGrowlNotifications;
@property(nonatomic, assign) BOOL cursorBlinks;
@property(nonatomic, assign) BOOL allowTitleReporting;
@property(nonatomic, assign) unsigned int maxScrollbackLines;
@property(nonatomic, assign) BOOL unlimitedScrollback;
@property(nonatomic, assign) BOOL useColumnScrollRegion;
@property(nonatomic, assign) BOOL saveToScrollbackInAlternateScreen;
@property(nonatomic, readonly) DVR *dvr;

// Designated initializer.
- (id)initWithTerminal:(VT100Terminal *)terminal;

// Destructively sets the screen size.
- (void)setUpScreenWithWidth:(int)width height:(int)height;

// Resize the screen, preserving its contents, alt-grid's contents, and selection.
- (void)resizeWidth:(int)new_width height:(int)height;

// Clear the screen, leaving the last line.
- (void)resetPreservingPrompt:(BOOL)preservePrompt;

// Reset the line-drawing flags for all character sets.
- (void)resetCharset;

// Indicates if line drawing mode is enabled for any character set, or if the current character set
// is not G0.
- (BOOL)usingDefaultCharset;

- (void)showCursor:(BOOL)show;

// Takes a parsed token from the terminal and modifies the screen accordingly.
- (void)putToken:(VT100TCC)token;

// Clears the screen and scrollback buffer.
- (void)clearBuffer;

// Clears the scrollback buffer, leaving screen contents alone.
- (void)clearScrollbackBuffer;

// Select which buffer is visible.
- (void)showPrimaryBuffer;
- (void)showAltBuffer;

// This is currently a no-op. See the comment in -[PTYSession setSendModifiers] for details.
- (void)setSendModifiers:(int *)modifiers
               numValues:(int)numValues;

// This should be called when the terminal's mouse mode changes.
- (void)setMouseMode:(MouseMode)mouseMode;

// Append a string to the screen at the current cursor position. The terminal's insert and wrap-
// around modes are respected, the cursor is advanced, the screen may be scrolled, and the line
// buffer may change.
- (void)appendStringAtCursor:(NSString *)s ascii:(BOOL)ascii;

// This is a hacky thing that moves the cursor to the next line, not respecting scroll regions.
// It's used for the tmux status screen.
- (void)crlf;

// Move the cursor down one position, scrolling if needed. Scroll regions are respected.
- (void)linefeed;

// Delete characters in the current line at the cursor's position.
- (void)deleteCharacters:(int)n;

// Move the cursor back. It may wrap around to the previous line.
- (void)backSpace;

// Move the cursor to the next tab stop, replacing chars along the way with tab/tab-fillers.
- (void)appendTabAtCursor;

// Move the line the cursor is on to the top of the screen and clear everything below.
- (void)clearScreen;

// Set the cursor position. Respects the terminal's originmode.
- (void)cursorToX:(int)x Y:(int)y;

// Moves the cursor to the left margin.
- (void)carriageReturn;

// Saves/Restores the cursor position.
- (void)saveCursorPosition;
- (void)restoreCursorPosition;

// Causes the bell to ring, flash, notify, etc., as configured.
- (void)activateBell;

// Sets the primary grid's contents and scrollback history. |history| is an array of NSData
// containing screen_char_t's. It contains a bizarre workaround for tmux bugs.
- (void)setHistory:(NSArray *)history;

// Sets the alt grid's contents. |lines| is NSData with screen_char_t's.
- (void)setAltScreen:(NSArray *)lines;

// Load state from tmux. The |state| dictionary has keys from the kStateDictXxx values.
- (void)setTmuxState:(NSDictionary *)state;

// Mark all cells dirty, causing them all to be redrawn when the next redraw timer fires.
- (void)markAsNeedingCompleteRedraw;

// Set the colors in the prototype char to all text on screen that matches the regex.
// See kHighlightXxxColor constants at the top of this file for dict keys, values are NSColor*s.
- (void)highlightTextMatchingRegex:(NSString *)regex
                            colors:(NSDictionary *)colors;

// Turn off DVR for this screen.
- (void)disableDvr;

// Load a frame from a dvr decoder.
- (void)setFromFrame:(screen_char_t*)s len:(int)len info:(DVRFrameInfo)info;

// Save the position of the end of the scrollback buffer without the screen appeneded.
- (void)saveTerminalAbsPos;

// Restore the saved position into a passed-in find context (see saveFindContextAbsPos and saveTerminalAbsPos).
- (void)restoreSavedPositionToFindContext:(FindContext *)context;

@end
