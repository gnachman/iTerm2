#import <Cocoa/Cocoa.h>
#import "iTermColorMap.h"
#import "PTYTextViewDataSource.h"
#import "VT100TerminalDelegate.h"
#import "VT100Token.h"

@class Trigger;
@class VT100RemoteHost;
@class VT100Screen;
@class iTermBackgroundCommandRunnerPool;
@class iTermColorMap;
@protocol iTermMark;
@class iTermSelection;
@protocol iTermOrderedToken;

@protocol iTermTriggerSideEffectExecutor<NSObject>
- (void)triggerSideEffectRingBell;
- (void)triggerSideEffectShowCapturedOutputToolNotVisibleAnnouncementIfNeeded;
- (void)triggerSideEffectShowShellIntegrationRequiredAnnouncement;
- (void)triggerSideEffectDidCaptureOutput;
- (void)triggerSideEffectLaunchCoprocessWithCommand:(NSString * _Nonnull)command
                                         identifier:(NSString * _Nullable)identifier
                                             silent:(BOOL)silent
                                       triggerTitle:(NSString * _Nonnull)triggerTitle;
- (void)triggerSideEffectMakeFirstResponder;
- (void)triggerSideEffectPostUserNotificationWithMessage:(NSString * _Nonnull)message;
- (void)triggerSideEffectStopScrollingAtLine:(long long)absLine;
- (void)triggerSideEffectOpenPasswordManagerToAccountName:(NSString * _Nullable)accountName;
- (void)triggerSideEffectRunBackgroundCommand:(NSString * _Nonnull)command
                                         pool:(iTermBackgroundCommandRunnerPool * _Nonnull)pool;
- (void)triggerWriteTextWithoutBroadcasting:(NSString * _Nonnull)text;
- (void)triggerSideEffectShowAlertWithMessage:(NSString * _Nonnull)message
                                      disable:(void (^ _Nonnull)(void))disable;
- (iTermVariableScope * _Nonnull)triggerSideEffectVariableScope;
- (void)triggerSideEffectSetTitle:(NSString * _Nonnull)newName;
- (void)triggerSideEffectInvokeFunctionCall:(NSString * _Nonnull)invocation
                              withVariables:(NSDictionary * _Nonnull)temporaryVariables
                                   captures:(NSArray<NSString *> * _Nonnull)captureStringArray
                                    trigger:(Trigger * _Nonnull)trigger;
- (void)triggerSideEffectSetValue:(id _Nullable)value
                 forVariableNamed:(NSString * _Nonnull)name;
@end

@protocol VT100ScreenDelegate <NSObject, iTermColorMapDelegate, iTermTriggerSideEffectExecutor>

// Screen contents have become dirty and should be redrawn right away.
- (void)screenNeedsRedraw;

// Schedule a refresh soon but not immediately.
- (void)screenScheduleRedrawSoon;

// Update window title, tab colors, and redraw view.
- (void)screenUpdateDisplay:(BOOL)redraw;

// Redraw the find on page view because search results may have been lost.
- (void)screenRefreshFindOnPageView;

// Called when the screen's size changes.
- (void)screenSizeDidChangeWithNewTopLineAt:(int)newTop;

// A change was made to the screen's contents which could cause a trigger to fire.
- (void)screenTriggerableChangeDidOccur;

// Called when the screen and terminal's attributes are reset
- (void)screenDidResetAllowingContentModification:(BOOL)modifyContent;

// Terminal can change title
- (BOOL)screenAllowTitleSetting;

// Called after text was added to the current line. Can be used to check triggers.
- (void)screenDidAppendStringToCurrentLine:(NSString * _Nonnull)string
                               isPlainText:(BOOL)plainText;
- (void)screenDidAppendAsciiDataToCurrentLine:(AsciiData * _Nonnull)asciiData;

// Change the cursor's appearance.
- (void)screenSetCursorBlinking:(BOOL)blink;
- (BOOL)screenCursorIsBlinking;
- (void)screenSetCursorType:(ITermCursorType)type;

- (void)screenGetCursorType:(ITermCursorType * _Nonnull)cursorTypeOut
                   blinking:(BOOL * _Nonnull)blinking;

- (void)screenResetCursorTypeAndBlink;


// Returns if the screen is permitted to resize the window.
- (BOOL)screenShouldInitiateWindowResize;

// The delegate should resize the screen to the given size.
- (void)screenResizeToPixelWidth:(int)width height:(int)height;
- (void)screenResizeToWidth:(int)width height:(int)height;

// Returns if terminal-initiated printing is permitted.
- (BOOL)screenShouldBeginPrinting;

// Sets the window title.
- (void)screenSetWindowTitle:(NSString * _Nonnull)title;

// Returns the current window title.
- (NSString * _Nullable)screenWindowTitle;

// Returns the session's "icon title", which is just its name.
- (NSString * _Nonnull)screenIconTitle;

// Sets the session's name.
- (void)screenSetIconName:(NSString * _Nonnull)name;
- (void)screenSetSubtitle:(NSString * _Nonnull)subtitle;

// Returns the session's current name
- (NSString * _Nonnull)screenName;

// Returns if the window is full-screen.
- (BOOL)screenWindowIsFullscreen;

// Returns the top left pixel coordinate of the window.
- (NSPoint)screenWindowTopLeftPixelCoordinate;

// Delegate should move the window's top left point to the given screen coordinate.
- (void)screenMoveWindowTopLeftPointTo:(NSPoint)point;

// If flag is set, the window should be miniaturized; otherwise, deminiaturize.
- (void)screenMiniaturizeWindow:(BOOL)flag;

// If flag is set, bring the window to front; if not, move to back.
- (void)screenRaise:(BOOL)flag;

// Set the proxy icon of current session window.
- (void)screenSetPreferredProxyIcon:(NSString * _Nullable)value;

// Returns if the window is miniaturized.
- (BOOL)screenWindowIsMiniaturized;

// Send input to the task.
- (void)screenWriteDataToTask:(NSData * _Nonnull)data;

// Returns the visible frame of the display the screen's window is in.
- (NSRect)screenWindowScreenFrame;

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
- (void)screenStartTmuxModeWithDCSIdentifier:(NSString * _Nonnull)dcsID;

// Handle a line of input in tmux mode in the token's string.
- (void)screenHandleTmuxInput:(VT100Token * _Nonnull)token;

// Returns if ambiguous characters are treated as fullwidth.
- (BOOL)screenShouldTreatAmbiguousCharsAsDoubleWidth;

// Number of scrollback lines changed.
- (void)screenDidChangeNumberOfScrollbackLines;

// Requests that the bell indicator be shown, notification be posted, etc.
- (void)screenShowBellIndicator;

// Request that a string be sent for printing.
- (void)screenPrintString:(NSString * _Nonnull)string;

// Request that the currently visible area of the screen be sent for printing.
- (void)screenPrintVisibleArea;

// Returns if iTermTabContentsChanged notifications should be published when the view is updated.
- (BOOL)screenShouldSendContentsChangedNotification;

// Returns whether terminal-generated notifications are allowed.
- (BOOL)screenShouldPostTerminalGeneratedAlert;

// Should this bell be ignored?
- (BOOL)screenShouldIgnoreBellWhichIsAudible:(BOOL)audible visible:(BOOL)visible;

// PTYTextView deselect
- (void)screenRemoveSelection;

// Selection range
- (iTermSelection * _Nonnull)screenSelection;

// Returns the size in pixels of a single cell.
- (NSSize)screenCellSize;

// Remove highlights of search results.
- (void)screenClearHighlights;

// Scrollback buffer deleted
- (void)screenDidClearScrollbackBuffer:(VT100Screen * _Nonnull)screen;

// Called when the mouse reporting mode changes.
- (void)screenMouseModeDidChange;

// An image should be flashed over the view.
- (void)screenFlashImage:(NSString * _Nonnull)identifier;

- (void)screenIncrementBadge;

// Bounce the dock. Set request to false to cancel.
- (void)screenRequestAttention:(VT100AttentionRequestType)request;
- (void)screenDidTryToUseDECRQCRA;

- (void)screenDisinterSession;

- (void)screenGetWorkingDirectoryWithCompletion:(void (^ _Nonnull)(NSString * _Nullable workingDirectory))completion;

// Show/hide the cursor.
- (void)screenSetCursorVisible:(BOOL)visible;

- (void)screenSetHighlightCursorLine:(BOOL)highlight;
- (void)screenClearCapturedOutput;

// Only called if the trackCursorLineMovement property is set.
- (void)screenCursorDidMoveToLine:(int)line;

// Returns if there is a view.
- (BOOL)screenHasView;

// Save the current scroll position
- (void)screenSaveScrollPosition;
- (void)screenDidAddMark:(id<iTermMark> _Nonnull)mark;
- (void)screenPromptDidStartAtLine:(int)line;
- (void)screenPromptDidEndWithMark:(VT100ScreenMark * _Nonnull)mark;

- (void)screenStealFocus;

- (void)screenSetProfileToProfileNamed:(NSString * _Nonnull)value;
- (void)screenSetPasteboard:(NSString * _Nonnull)value;
- (void)screenDidAddNote:(PTYAnnotation * _Nonnull)note focus:(BOOL)focus;
- (void)screenCopyBufferToPasteboard;
- (BOOL)screenIsAppendingToPasteboard;
- (void)screenAppendDataToPasteboard:(NSData * _Nonnull)data;

- (void)screenWillReceiveFileNamed:(NSString * _Nonnull)name
                            ofSize:(NSInteger)size
                      preconfirmed:(BOOL)preconfirmed;
- (void)screenDidFinishReceivingFile;
- (void)screenDidFinishReceivingInlineFile;
- (void)screenDidReceiveBase64FileData:(NSString * _Nonnull)data;
- (void)screenFileReceiptEndedUnexpectedly;

- (void)screenRequestUpload:(NSString * _Nonnull)args;

- (void)screenSetCurrentTabColor:(NSColor * _Nullable)color;
- (void)screenSetTabColorRedComponentTo:(CGFloat)color;
- (void)screenSetTabColorGreenComponentTo:(CGFloat)color;
- (void)screenSetTabColorBlueComponentTo:(CGFloat)color;
- (void)screenSetColor:(NSColor * _Nullable)color forKey:(int)key;
- (void)screenResetColorsWithColorMapKey:(int)key;
- (void)screenSelectColorPresetNamed:(NSString * _Nonnull)name;

- (void)screenCurrentHostDidChange:(VT100RemoteHost * _Nonnull)host
                               pwd:(NSString * _Nullable)workingDirectory;
- (void)screenCurrentDirectoryDidChangeTo:(NSString * _Nullable)newPath;
- (void)screenDidReceiveCustomEscapeSequenceWithParameters:(NSDictionary<NSString *, NSString *> * _Nonnull)parameters
                                                   payload:(NSString * _Nonnull)payload;
- (CGFloat)screenBackingScaleFactor;

// Ok to write to shell?
- (BOOL)screenShouldSendReport;
- (BOOL)screenShouldSendReportForVariable:(NSString * _Nullable)name;

// FinalTerm stuff
- (void)screenCommandDidChangeTo:(NSString * _Nonnull)command
                        atPrompt:(BOOL)atPrompt
                      hadCommand:(BOOL)hadCommand
                     haveCommand:(BOOL)haveCommand;

- (void)screenDidExecuteCommand:(NSString * _Nullable)command
                          range:(VT100GridCoordRange)range
                         onHost:(VT100RemoteHost * _Nullable)host
                    inDirectory:(NSString * _Nullable)directory
                           mark:(VT100ScreenMark * _Nullable)mark;
- (void)screenCommandDidExitWithCode:(int)code mark:(VT100ScreenMark * _Nullable)maybeMark;

- (NSString * _Nullable)screenProfileName;

typedef NS_ENUM(NSUInteger, VT100ScreenWorkingDirectoryPushType) {
    // We polled for the working directory for a really sketchy reason, such as the user pressing enter.
    VT100ScreenWorkingDirectoryPushTypePull,
    // We received an unreliable signal that we should poll, such as an OSC title change.
    VT100ScreenWorkingDirectoryPushTypeWeakPush,
    // Got a control sequence giving the current directory. Completely trustworthy.
    VT100ScreenWorkingDirectoryPushTypeStrongPush
};

- (void)screenLogWorkingDirectoryOnAbsoluteLine:(long long)absLine
                                     remoteHost:(VT100RemoteHost * _Nullable)remoteHost
                                  withDirectory:(NSString * _Nullable)directory
                                       pushType:(VT100ScreenWorkingDirectoryPushType)pushType
                                       accepted:(BOOL)accepted;

- (void)screenSuggestShellIntegrationUpgrade;
- (void)screenDidDetectShell:(NSString * _Nonnull)shell;

- (void)screenSetBackgroundImageFile:(NSString * _Nonnull)filename;
- (void)screenSetBadgeFormat:(NSString * _Nonnull)theFormat;
- (void)screenSetUserVar:(NSString * _Nonnull)kvp;

- (BOOL)screenShouldReduceFlicker;
- (NSInteger)screenUnicodeVersion;
- (void)screenSetUnicodeVersion:(NSInteger)unicodeVersion;
- (void)screenSetLabel:(NSString * _Nonnull)label forKey:(NSString * _Nonnull)keyName;
- (void)screenPushKeyLabels:(NSString * _Nonnull)value;
- (void)screenPopKeyLabels:(NSString * _Nonnull)value;
- (void)screenSendModifiersDidChange;
- (void)screenKeyReportingFlagsDidChange;

- (void)screenTerminalAttemptedPasteboardAccess;
- (NSString * _Nullable)screenValueOfVariableNamed:(NSString * _Nonnull)name;
- (void)screenReportFocusWillChangeTo:(BOOL)reportFocus;
- (void)screenReportPasteBracketingWillChangeTo:(BOOL)bracket;
- (void)screenDidReceiveLineFeed;
- (void)screenSoftAlternateScreenModeDidChangeTo:(BOOL)enabled
                                showingAltScreen:(BOOL)showing;
- (void)screenReportKeyUpDidChange:(BOOL)reportKeyUp;
- (BOOL)screenConfirmDownloadNamed:(NSString * _Nonnull)name canExceedSize:(NSInteger)limit;
- (BOOL)screenConfirmDownloadAllowed:(NSString * _Nonnull)name
                                size:(NSInteger)size
                       displayInline:(BOOL)displayInline
                         promptIfBig:(BOOL * _Nonnull)promptIfBig;
- (BOOL)screenShouldClearScrollbackBuffer;
- (VT100GridRange)screenRangeOfVisibleLines;
- (void)screenDidResize;
- (NSString * _Nullable)screenStringForKeypressWithCode:(unsigned short)keycode
                                                  flags:(NSEventModifierFlags)flags
                                             characters:(NSString * _Nonnull)characters
                            charactersIgnoringModifiers:(NSString * _Nonnull)charactersIgnoringModifiers;
- (void)screenDidAppendImageData:(NSData * _Nonnull)data;
- (void)screenAppendScreenCharArray:(const screen_char_t *_Nonnull)line
                           metadata:(iTermImmutableMetadata)metadata
                             length:(int)length;
- (void)screenApplicationKeypadModeDidChange:(BOOL)mode;
- (void)screenRestoreColorsFromSlot:(VT100SavedColorsSlot * _Nonnull)slot;
- (int)screenMaximumTheoreticalImageDimension;
- (void)screenOfferToDisableTriggersInInteractiveApps;
- (void)screenDidUpdateReturnCodeForMark:(VT100ScreenMark * _Nonnull)mark
                              remoteHost:(VT100RemoteHost * _Nullable)remoteHost;

@end
