#import <Cocoa/Cocoa.h>
#import "PTYTextViewDataSource.h"

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
