#import <Cocoa/Cocoa.h>
#import "iTermColorMap.h"
#import "PTYTextViewDataSource.h"
#import "VT100TerminalDelegate.h"
#import "VT100Token.h"

@class ParsedSSHOutput;
@protocol Porthole;
@class Trigger;
@protocol VT100RemoteHostReading;
@protocol VT100ScreenMarkReading;
@class VT100Screen;
@class VT100ScreenMutableState;
@class iTermBackgroundCommandRunnerPool;
@class iTermColorMap;
@class iTermConductorRecovery;
@protocol iTermMark;
@class iTermSelection;
@protocol iTermObject;
@protocol iTermOrderedToken;
@class VT100ScreenState;
@class VT100ScreenConfiguration;
@class VT100MutableScreenConfiguration;

@interface VT100ScreenTokenExecutorUpdate: NSObject

@property (nonatomic, readonly) NSInteger estimatedThroughput;
@property (nonatomic, readonly) NSInteger numberOfBytesExecuted;
@property (nonatomic, readonly) BOOL inputHandled;

@end

@protocol iTermTriggerSideEffectExecutor<NSObject>
- (void)triggerSideEffectShowCapturedOutputToolNotVisibleAnnouncementIfNeeded;
- (void)triggerSideEffectShowShellIntegrationRequiredAnnouncement;
- (void)triggerSideEffectDidCaptureOutput;
- (void)triggerSideEffectLaunchCoprocessWithCommand:(NSString * _Nonnull)command
                                         identifier:(NSString * _Nullable)identifier
                                             silent:(BOOL)silent
                                       triggerTitle:(NSString * _Nonnull)triggerTitle;
- (void)triggerSideEffectPostUserNotificationWithMessage:(NSString * _Nonnull)message;
- (void)triggerSideEffectStopScrollingAtLine:(long long)absLine;
- (void)triggerSideEffectOpenPasswordManagerToAccountName:(NSString * _Nullable)accountName;
- (void)triggerSideEffectRunBackgroundCommand:(NSString * _Nonnull)command
                                         pool:(iTermBackgroundCommandRunnerPool * _Nonnull)pool;
- (void)triggerWriteTextWithoutBroadcasting:(NSString * _Nonnull)text;
- (void)triggerSideEffectShowAlertWithMessage:(NSString * _Nonnull)message
                                    rateLimit:(iTermRateLimitedUpdate * _Nonnull)rateLimit
                                      disable:(void (^ _Nonnull)(void))disable;
- (iTermVariableScope * _Nonnull)triggerSideEffectVariableScope;
- (void)triggerSideEffectSetTitle:(NSString * _Nonnull)newName;
- (void)triggerSideEffectInvokeFunctionCall:(NSString * _Nonnull)invocation
                              withVariables:(NSDictionary * _Nonnull)temporaryVariables
                                   captures:(NSArray<NSString *> * _Nonnull)captureStringArray
                                    trigger:(Trigger * _Nonnull)trigger;
- (void)triggerSideEffectSetValue:(id _Nullable)value
                 forVariableNamed:(NSString * _Nonnull)name;
- (void)triggerSideEffectCurrentDirectoryDidChange:(NSString * _Nonnull)newPath;
- (void)triggerSideEffectShowCapturedOutputTool;

@end

@protocol VT100ScreenDelegate <NSObject, iTermImmutableColorMapDelegate, iTermObject, iTermTriggerSideEffectExecutor>

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

// Called when the screen and terminal's attributes are reset
- (void)screenDidReset;

// Terminal can change title
- (BOOL)screenAllowTitleSetting;

// Called after text was added to the current line. Can be used to check triggers.
- (void)screenDidAppendStringToCurrentLine:(NSString * _Nonnull)string
                               isPlainText:(BOOL)plainText
                                foreground:(screen_char_t)fg
                                background:(screen_char_t)bg
                                  atPrompt:(BOOL)atPrompt;

- (void)screenDidAppendAsciiDataToCurrentLine:(NSData * _Nonnull)asciiData
                                   foreground:(screen_char_t)fg
                                   background:(screen_char_t)bg
                                     atPrompt:(BOOL)atPrompt;

- (void)screenRevealComposerWithPrompt:(NSArray<ScreenCharArray *> * _Nonnull)prompt;
- (void)screenDismissComposer;
- (void)screenAppendStringToComposer:(NSString * _Nonnull)string;

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
- (void)screenResizeToWidth:(int)width height:(int)height;
- (void)screenSetSize:(VT100GridSize)proposedSize;
- (void)screenSetPointSize:(NSSize)proposedSize;

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
- (void)screenSendReportData:(NSData * _Nonnull)data;
- (void)screenDidSendAllPendingReports;

// Returns the visible frame of the display the screen's window is in.
- (NSRect)screenWindowScreenFrame;

// Returns the frame of the window this screen is.
- (NSRect)screenWindowFrame;

// Returns the rect in the view that is currently visible.
- (NSSize)screenSize;

// If the flag is set, push the current window title onto a stack; otherwise push the icon title.
- (void)screenPushCurrentTitleForWindow:(BOOL)flag;

// If the flag is set, pop the current window title from the stack; otherwise pop the icon title.
- (void)screenPopCurrentTitleForWindow:(BOOL)flag completion:(void (^ _Nonnull)(void))completion;

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

- (void)screenActivateBellAudibly:(BOOL)audibleBell
                          visibly:(BOOL)flashBell
                    showIndicator:(BOOL)showBellIndicator
                            quell:(BOOL)quell;

// Request that a string be sent for printing.
- (void)screenPrintStringIfAllowed:(NSString * _Nonnull)printBuffer
                        completion:(void (^ _Nonnull)(void))completion;

// Request that the currently visible area of the screen be sent for printing.
- (void)screenPrintVisibleAreaIfAllowed;

// Returns if iTermTabContentsChanged notifications should be published when the view is updated.
- (BOOL)screenShouldSendContentsChangedNotification;

// PTYTextView deselect
- (void)screenRemoveSelection;

- (void)screenResetTailFind;

// Selection range
- (iTermSelection * _Nonnull)screenSelection;

// Returns the size in pixels of a single cell.
- (NSSize)screenCellSize;

// Remove highlights of search results.
- (void)screenClearHighlights;

// Scrollback buffer deleted
- (void)screenDidClearScrollbackBuffer;

// Called when the mouse reporting mode changes.
- (void)screenMouseModeDidChange;

// An image should be flashed over the view.
- (void)screenFlashImage:(NSString * _Nonnull)identifier;

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
- (void)screenDidAddMark:(id<iTermMark> _Nonnull)mark
                   alert:(BOOL)alert
              completion:(void (^ _Nonnull)(void))completion;
- (void)screenPromptDidStartAtLine:(int)line;
- (void)screenPromptDidEndWithMark:(id<VT100ScreenMarkReading> _Nonnull)mark;

- (void)screenStealFocus;

- (void)screenSetProfileToProfileNamed:(NSString * _Nonnull)value;
- (void)screenSetPasteboard:(NSString * _Nonnull)value;
- (void)screenDidAddNote:(id<PTYAnnotationReading> _Nonnull)note focus:(BOOL)focus visible:(BOOL)visible;
- (void)screenDidAddPorthole:(id<Porthole> _Nonnull)porthole;

- (void)screenCopyBufferToPasteboard;
- (void)screenAppendDataToPasteboard:(NSData * _Nonnull)data;

- (void)screenWillReceiveFileNamed:(NSString * _Nonnull)name
                            ofSize:(NSInteger)size
                      preconfirmed:(BOOL)preconfirmed;
- (void)screenDidFinishReceivingFile;
- (void)screenDidFinishReceivingInlineFile;
// Call confirm if you want to give the user the chance to cancel the download.
- (void)screenDidReceiveBase64FileData:(NSString * _Nonnull)data
                               confirm:(void (^ _Nonnull NS_NOESCAPE)(NSString * _Nonnull name,
                                                                      NSInteger lengthBefore,
                                                                      NSInteger lengthAfter))confirm;
- (void)screenFileReceiptEndedUnexpectedly;

- (void)screenRequestUpload:(NSString * _Nonnull)args
                 completion:(void (^ _Nonnull)(void))completion;

- (void)screenSetCurrentTabColor:(NSColor * _Nullable)color;
- (void)screenSetTabColorRedComponentTo:(CGFloat)color;
- (void)screenSetTabColorGreenComponentTo:(CGFloat)color;
- (void)screenSetTabColorBlueComponentTo:(CGFloat)color;
- (BOOL)screenSetColor:(NSColor * _Nullable)color
            profileKey:(NSString * _Nullable)profileKey;
- (NSDictionary<NSNumber *, id> * _Nonnull)screenResetColorWithColorMapKey:(int)key
                                                                profileKey:(NSString * _Nonnull)profileKey
                                                                      dark:(BOOL)dark;

- (void)screenSelectColorPresetNamed:(NSString * _Nonnull)name;

- (void)screenCurrentHostDidChange:(id<VT100RemoteHostReading> _Nonnull)host
                               pwd:(NSString * _Nullable)workingDirectory
                               ssh:(BOOL)ssh;  // Due to ssh integration?
- (void)screenCurrentDirectoryDidChangeTo:(NSString * _Nullable)newPath
                               remoteHost:(id<VT100RemoteHostReading> _Nullable)remoteHost;

- (void)screenDidReceiveCustomEscapeSequenceWithParameters:(NSDictionary<NSString *, NSString *> * _Nonnull)parameters
                                                   payload:(NSString * _Nonnull)payload;
- (void)screenReportVariableNamed:(NSString * _Nonnull)name;
- (void)screenReportCapabilities;

// FinalTerm stuff
- (void)screenCommandDidChangeTo:(NSString * _Nonnull)command
                        atPrompt:(BOOL)atPrompt
                      hadCommand:(BOOL)hadCommand
                     haveCommand:(BOOL)haveCommand;

- (void)screenDidExecuteCommand:(NSString * _Nullable)command
                          range:(VT100GridCoordRange)range
                         onHost:(id<VT100RemoteHostReading> _Nullable)host
                    inDirectory:(NSString * _Nullable)directory
                           mark:(id<VT100ScreenMarkReading> _Nullable)mark;
- (void)screenCommandDidExitWithCode:(int)code mark:(id<VT100ScreenMarkReading> _Nullable)maybeMark;
// Failed to run the command (e.g., syntax error)
- (void)screenCommandDidAbortOnLine:(int)line
                        outputRange:(VT100GridCoordRange)outputRange
                            command:(NSString *_Nonnull)command;

typedef NS_ENUM(NSUInteger, VT100ScreenWorkingDirectoryPushType) {
    // We polled for the working directory for a really sketchy reason, such as the user pressing enter.
    VT100ScreenWorkingDirectoryPushTypePull,
    // We received an unreliable signal that we should poll, such as an OSC title change.
    VT100ScreenWorkingDirectoryPushTypeWeakPush,
    // Got a control sequence giving the current directory. Completely trustworthy.
    VT100ScreenWorkingDirectoryPushTypeStrongPush
};

- (void)screenLogWorkingDirectoryOnAbsoluteLine:(long long)absLine
                                     remoteHost:(id<VT100RemoteHostReading> _Nullable)remoteHost
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
- (void)screenReportFocusWillChangeTo:(BOOL)reportFocus;
- (void)screenReportPasteBracketingWillChangeTo:(BOOL)bracket;
- (void)screenDidReceiveLineFeedAtLineBufferGeneration:(long long)lineBufferGeneration;
- (void)screenSoftAlternateScreenModeDidChangeTo:(BOOL)enabled
                                showingAltScreen:(BOOL)showing;
- (void)screenReportKeyUpDidChange:(BOOL)reportKeyUp;
- (BOOL)screenConfirmDownloadNamed:(NSString * _Nonnull)name canExceedSize:(NSInteger)limit;
- (BOOL)screenConfirmDownloadAllowed:(NSString * _Nonnull)name
                                size:(NSInteger)size
                       displayInline:(BOOL)displayInline
                         promptIfBig:(BOOL * _Nonnull)promptIfBig;
- (void)screenAskAboutClearingScrollback;
- (VT100GridRange)screenRangeOfVisibleLines;
- (void)screenDidResize;
- (NSString * _Nullable)screenStringForKeypressWithCode:(unsigned short)keycode
                                                  flags:(NSEventModifierFlags)flags
                                             characters:(NSString * _Nonnull)characters
                            charactersIgnoringModifiers:(NSString * _Nonnull)charactersIgnoringModifiers;
- (void)screenDidAppendImageData:(NSData * _Nonnull)data;
- (void)screenAppendScreenCharArray:(ScreenCharArray * _Nonnull)array
                           metadata:(iTermImmutableMetadata)metadata
               lineBufferGeneration:(long long)lineBufferGeneration;
- (void)screenApplicationKeypadModeDidChange:(BOOL)mode;
- (void)screenRestoreColorsFromSlot:(VT100SavedColorsSlot * _Nonnull)slot;
- (void)screenOfferToDisableTriggersInInteractiveApps;
- (void)screenDidUpdateReturnCodeForMark:(id<VT100ScreenMarkReading> _Nonnull)mark
                              remoteHost:(id<VT100RemoteHostReading> _Nullable)remoteHost;
- (void)screenCopyStringToPasteboard:(NSString * _Nonnull)string;
- (void)screenReportPasteboard:(NSString * _Nonnull)pasteboard completion:(void (^ _Nonnull)(void))completion;
- (void)screenPostUserNotification:(NSString * _Nonnull)string rich:(BOOL)rich;
// Called while joined. Don't let `mutableState` escape.
- (void)screenSync:(VT100ScreenMutableState * _Nonnull)mutableState;
- (void)screenUpdateCommandUseWithGuid:(NSString * _Nonnull)screenmarkGuid
                                onHost:(id<VT100RemoteHostReading> _Nullable)lastRemoteHost
                         toReferToMark:(id<VT100ScreenMarkReading> _Nonnull)screenMark;

- (void)screenExecutorDidUpdate:(VT100ScreenTokenExecutorUpdate * _Nonnull)update;
- (VT100ScreenState * _Nonnull)screenSwitchToSharedState;
- (void)screenRestoreState:(VT100ScreenState * _Nonnull)state;
- (VT100MutableScreenConfiguration * _Nonnull)screenConfiguration;
- (void)screenSyncExpect:(VT100ScreenMutableState * _Nonnull)mutableState;
- (void)screenConvertAbsoluteRange:(VT100GridAbsCoordRange)range
              toTextDocumentOfType:(NSString * _Nullable)type
                          filename:(NSString * _Nullable)filename
                         forceWide:(BOOL)forceWide;
- (void)screenDidHookSSHConductorWithToken:(NSString * _Nonnull)token
                                  uniqueID:(NSString * _Nonnull)uniqueID
                                  boolArgs:(NSString * _Nonnull)boolArgs
                                   sshargs:(NSString * _Nonnull)sshargs
                                     dcsID:(NSString * _Nonnull)dcsID
                                savedState:(NSDictionary * _Nonnull)savedState;
- (void)screenDidReadSSHConductorLine:(NSString * _Nonnull)string depth:(int)depth;
- (void)screenDidUnhookSSHConductor;
- (void)screenDidBeginSSHConductorCommandWithIdentifier:(NSString * _Nonnull)identifier
                                                  depth:(int)depth;

- (void)screenDidEndSSHConductorCommandWithIdentifier:(NSString * _Nonnull)identifier
                                                 type:(NSString * _Nonnull)type
                                               status:(uint8_t)status
                                                depth:(int)depth;
- (void)screenHandleSSHSideChannelOutput:(NSString * _Nonnull)string
                                     pid:(int32_t)pid
                                 channel:(uint8_t)channel
                                   depth:(int)depth;

- (void)screenDidTerminateSSHProcess:(int)pid code:(int)code depth:(int)depth;
- (void)screenWillBeginSSHIntegration;
- (void)screenBeginSSHIntegrationWithToken:(NSString * _Nonnull)token
                                  uniqueID:(NSString * _Nonnull)uniqueID
                                 encodedBA:(NSString * _Nonnull)encodedBA
                                   sshArgs:(NSString * _Nonnull)sshArgs;
- (NSInteger)screenEndSSH:(NSString * _Nonnull)uniqueID;
- (NSString * _Nonnull)screenSSHLocation;
- (void)screenBeginFramerRecovery:(int)parentDepth;
// Returns true when recovery completes
- (iTermConductorRecovery * _Nullable)screenHandleFramerRecoveryString:(NSString * _Nonnull)string;
- (void)screenFramerRecoveryDidFinish;
- (void)screenDidResynchronizeSSH;
- (void)screenEnsureDefaultMode;
- (void)screenWillSynchronize;
- (void)screenDidSynchronize;
- (void)screenOpenURL:(NSURL * _Nullable)url completion:(void (^ _Nonnull)(void))completion;
- (void)screenReportIconTitle;
- (void)screenReportWindowTitle;
- (void)screenSetPointerShape:(NSString * _Nonnull)pointerShape;
@end
