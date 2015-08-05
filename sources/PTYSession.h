// Implements the model class for a terminal session.

#import "DVR.h"
#import "FindViewController.h"
#import "iTermFileDescriptorClient.h"
#import "ITAddressBookMgr.h"
#import "LineBuffer.h"
#import "PTYTask.h"
#import "PTYTextView.h"
#import "Popup.h"
#import "ProfileModel.h"
#import "TextViewWrapper.h"
#import "TmuxController.h"
#import "TmuxGateway.h"
#import "VT100Screen.h"
#import "VT100ScreenMark.h"
#import "WindowControllerInterface.h"
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <sys/time.h>

// Posted when the tmux font changes. Window layouts will need to be updated.
extern NSString *const kPTYSessionTmuxFontDidChange;

// Called when captured output for the current session changes.
extern NSString *const kPTYSessionCapturedOutputDidChange;

@class CapturedOutput;
@class FakeWindow;
@class iTermAnnouncementViewController;
@class PTYScrollView;
@class PTYTask;
@class PTYTextView;
@class PasteContext;
@class PreferencePanel;
@class VT100RemoteHost;
@class VT100Screen;
@class VT100Terminal;
@class iTermColorMap;
@class iTermController;
@class iTermGrowlDelegate;

// The time period for just blinking is in -[iTermAdvancedSettingsModel timeBetweenBlinks].
// Timer period when receiving lots of data.
static const float kSlowTimerIntervalSec = 1.0 / 15.0;
// Timer period for interactive use.
static const float kFastTimerIntervalSec = 1.0 / 30.0;
// Timer period for background sessions. This changes the tab item's color
// so it must run often enough for that to be useful.
// TODO(georgen): There's room for improvement here.
static const float kBackgroundSessionIntervalSec = 1;

typedef enum {
    kSplitSelectionModeOn,
    kSplitSelectionModeOff,
    kSplitSelectionModeCancel
} SplitSelectionMode;

typedef enum {
    TMUX_NONE,
    TMUX_GATEWAY,  // Receiving tmux protocol messages
    TMUX_CLIENT  // Session mirrors a tmux virtual window
} PTYSessionTmuxMode;

@class PTYTab;
@class SessionView;
@interface PTYSession : NSResponder <
    FindViewControllerDelegate,
    PopupDelegate,
    PTYTaskDelegate,
    PTYTextViewDelegate,
    TmuxGatewayDelegate,
    VT100ScreenDelegate>

@property(nonatomic, assign) BOOL alertOnNextMark;
@property(nonatomic, copy) NSColor *tabColor;

@property(nonatomic, readonly) DVR *dvr;
@property(nonatomic, readonly) DVRDecoder *dvrDecoder;
// Returns the "real" session while in instant replay, else nil if not in IR.
@property(nonatomic, retain) PTYSession *liveSession;
@property(nonatomic, readonly) BOOL canInstantReplayPrev;
@property(nonatomic, readonly) BOOL canInstantReplayNext;

@property(nonatomic, readonly) BOOL isTmuxClient;
@property(nonatomic, readonly) BOOL isTmuxGateway;

// Does the session have new output? Used by -[PTYTab updateLabelAttributes] to color the tab's title
// appropriately.
@property(nonatomic, assign) BOOL newOutput;

// Do we need to prompt on close for this session?
@property(nonatomic, readonly) BOOL promptOnClose;

// Array of subprocessess names.
@property(nonatomic, readonly) NSArray *childJobNames;

// The owning tab. TODO: Make this into a protocol because it's essentially a delegate.
@property(nonatomic, assign) PTYTab *tab;

// Time since reference date when last output was receivced.
@property(nonatomic, readonly) NSTimeInterval lastOutput;

// Is the session idle? Used by updateLabelAttributes to send a growl message when processing ends.
@property(nonatomic, assign) BOOL havePostedIdleNotification;

// Is there new output for the purposes of growl notifications? They run on a different schedule
// than tab colors.
@property(nonatomic, assign) BOOL havePostedNewOutputNotification;

// Session name; can be changed via escape code. The getter will add formatting to it; to retrieve
// the value that was set, use -rawName.
@property(nonatomic, copy) NSString *name;

// Unformatted version of -name.
@property(nonatomic, readonly) NSString *rawName;

// The original bookmark name.
@property(nonatomic, copy) NSString *bookmarkName;

// defaultName cannot be changed by the host. The getter returns a formatted name. Use
// joblessDefaultName to get the value that was set.
@property(nonatomic, copy) NSString *defaultName;

// The value to which defaultName was last set, unadorned with additional formatting.
@property(nonatomic, readonly) NSString *joblessDefaultName;

// The window title that should be used when this session is current. Otherwise defaultName
// should be used.
@property(nonatomic, copy) NSString *windowTitle;

// Shell wraps the underlying file descriptor pair.
@property(nonatomic, retain) PTYTask *shell;

@property(nonatomic, readonly) VT100Terminal *terminal;

// The value of the $TERM environment var.
@property(nonatomic, copy) NSString *termVariable;

// The value of the $COLORFGBG environment var.
@property(nonatomic, copy) NSString *colorFgBgVariable;

// Screen contents, plus scrollback buffer.
@property(nonatomic, retain) VT100Screen *screen;

// The view in which this session's objects live.
// NOTE! This is a weak reference.
// TODO: SessionView should hold a weak reference to PTYSession, which should be an NSViewController.
@property(nonatomic, assign) SessionView *view;

// The view that contains all the visible text in this session and that does most input handling.
// This is the one and only subview of the document view of -scrollview.
@property(nonatomic, retain) PTYTextView *textview;

// The scrollview. It is a subview of SessionView and contains -textview.
@property(nonatomic, retain) PTYScrollView *scrollview;

@property(nonatomic, assign) NSStringEncoding encoding;

// Send a character periodically.
@property(nonatomic, assign) BOOL antiIdle;

// The code to send in the anti idle timer.
@property(nonatomic, assign) char antiIdleCode;

// If true, close the tab when the session ends.
@property(nonatomic, assign) BOOL autoClose;

// Should ambiguous-width characters (e.g., Greek) be treated as double-width? Usually a bad idea.
@property(nonatomic, assign) BOOL treatAmbiguousWidthAsDoubleWidth;

// True if mouse movements are sent to the host.
@property(nonatomic, assign) BOOL xtermMouseReporting;

// Profile for this session
@property(nonatomic, copy) Profile *profile;

// Return the address book that the session was originally created with.
@property(nonatomic, readonly) Profile *originalProfile;

// tty device
@property(nonatomic, readonly) NSString *tty;

// True if background image should be tiled
@property(nonatomic, assign) BOOL backgroundImageTiled;

// Filename of background image.
@property(nonatomic, copy) NSString *backgroundImagePath;  // Used by scripting
@property(nonatomic, retain) NSImage *backgroundImage;

@property(nonatomic, retain) iTermColorMap *colorMap;
@property(nonatomic, assign) float transparency;
@property(nonatomic, assign) float blend;
@property(nonatomic, assign) BOOL useBoldFont;
@property(nonatomic, assign) BOOL useItalicFont;

@property(nonatomic, readonly) BOOL logging;
@property(nonatomic, readonly) BOOL exited;

// Is bell currently in ringing state?
@property(nonatomic, assign) BOOL bell;

@property(nonatomic, readonly) NSDictionary *arrangement;

@property(nonatomic, readonly) int columns;
@property(nonatomic, readonly) int rows;

// Has this session's bookmark been divorced from the profile in the ProfileModel? Changes
// in this bookmark may happen indepentendly of the persistent bookmark.
@property(nonatomic, readonly) BOOL isDivorced;

@property(nonatomic, readonly) NSString *jobName;

// Ignore resize notifications. This would be set because the session's size musn't be changed
// due to temporary changes in the window size, as code later on may need to know the session's
// size to set the window size properly.
@property(nonatomic, assign) BOOL ignoreResizeNotifications;

// This number (int) imposes an ordering on session activity time.
@property(nonatomic, retain) NSNumber *activityCounter;

// Is there a saved scroll position?
@property(nonatomic, readonly) BOOL hasSavedScrollPosition;

// Image for dragging one session.
@property(nonatomic, readonly) NSImage *dragImage;

@property(nonatomic, readonly) BOOL hasCoprocess;

@property(nonatomic, retain) TmuxController *tmuxController;

@property(nonatomic, readonly) VT100RemoteHost *currentHost;

@property(nonatomic, readonly) int tmuxPane;

// FinalTerm
@property(nonatomic, readonly) NSArray *autocompleteSuggestionsForCurrentCommand;
@property(nonatomic, readonly) NSString *currentCommand;

// Session is not in foreground and notifications are enabled on the screen.
@property(nonatomic, readonly) BOOL shouldPostGrowlNotification;

@property(nonatomic, readonly) BOOL hasSelection;

@property(nonatomic, assign) BOOL highlightCursorLine;

// Used to help remember total ordering on views while one is maximzied
@property(nonatomic, assign) NSPoint savedRootRelativeOrigin;

// The computed label
@property(nonatomic, readonly) NSString *badgeLabel;

// Commands issued, directories entered, and hosts connected to during this session.
// Requires shell integration.
@property(nonatomic, readonly) NSMutableArray *commands;  // of NSString
@property(nonatomic, readonly) NSMutableArray *directories;  // of NSString
@property(nonatomic, readonly) NSMutableArray *hosts;  // of VT100RemoteHost

// Session-defined and user-defined variables. Session-defined vars start with "session." and
// user-defined variables start with "user.".
@property(nonatomic, readonly) NSMutableDictionary *variables;

@property(atomic, readonly) PTYSessionTmuxMode tmuxMode;

// Has output been received recently?
@property(nonatomic, readonly) BOOL isProcessing;

// Indicates if you're at the shell prompt and not running a command. Returns
// NO if shell integration is not in use.
@property(nonatomic, readonly) BOOL isAtShellPrompt;

// Has it been at least a second since isProcessing became false?
@property(nonatomic, readonly) BOOL isIdle;

// Tries to return the current local working directory without resolving symlinks (possible if
// shell integration is on). If that can't be done then the current local working directory with
// symlinks resolved is returned.
@property(nonatomic, readonly) NSString *currentLocalWorkingDirectory;

// A UUID that uniquely identifies this session.
// Used to link serialized data back to a restored session (e.g., which session
// a command in command history belongs to). Also to link content from an
// arrangement provided to us by the OS during system window restoration with a
// session in a saved arrangement when we're opening a saved arrangement at
// startup instead of respecting the wishes of system window restoration.
@property(nonatomic, readonly) NSString *guid;

// Indicates if this session predates a tmux split pane. Used to figure out which pane is new when
// layout changes due to a user-initiated pane split.
@property(nonatomic, assign) BOOL sessionIsSeniorToTmuxSplitPane;

@property(nonatomic, readonly) NSArray *commandUses;

#pragma mark - methods

+ (BOOL)handleShortcutWithoutTerminal:(NSEvent*)event;
+ (void)selectMenuItem:(NSString*)theName;

// Register the contents in the arrangement so that if the session is later
// restored from an arrangement with the same guid as |arrangement|, the
// contents will be copied over.
+ (void)registerSessionInArrangement:(NSDictionary *)arrangement;

// Forget all sessions registered with registerSessionInArrangement. Normally
// called after startup activities are done.
+ (void)removeAllRegisteredSessions;

// Jump to a particular point in time.
- (long long)irSeekToAtLeast:(long long)timestamp;

// Disable all timers.
- (void)cancelTimers;

// Begin showing DVR frames from some live session.
- (void)setDvr:(DVR*)dvr liveSession:(PTYSession*)liveSession;

// Append a bunch of lines from this (presumably synthetic) session from another (presumably live)
// session.
- (void)appendLinesInRange:(NSRange)rangeOfLines fromSession:(PTYSession *)source;

// Go forward/back in time. Must call setDvr:liveSession: first.
- (void)irAdvance:(int)dir;

// Session specific methods
- (BOOL)setScreenSize:(NSRect)aRect parent:(id<WindowControllerInterface>)parent;

// triggers
- (void)clearTriggerLine;
- (void)appendStringToTriggerLine:(NSString *)s;

+ (void)drawArrangementPreview:(NSDictionary *)arrangement frame:(NSRect)frame;
- (void)setSizeFromArrangement:(NSDictionary*)arrangement;
+ (PTYSession*)sessionFromArrangement:(NSDictionary*)arrangement
                               inView:(SessionView*)sessionView
                                inTab:(PTYTab*)theTab
                        forObjectType:(iTermObjectType)objectType;
+ (NSDictionary *)arrangementFromTmuxParsedLayout:(NSDictionary *)parseNode
                                         bookmark:(Profile *)bookmark;
+ (NSString *)guidInArrangement:(NSDictionary *)arrangement;

- (void)textViewFontDidChange;

// Set rows, columns from arrangement.
- (void)resizeFromArrangement:(NSDictionary *)arrangement;

- (void)runCommandWithOldCwd:(NSString*)oldCWD
               forObjectType:(iTermObjectType)objectType
              forceUseOldCWD:(BOOL)forceUseOldCWD
               substitutions:(NSDictionary *)substituions;

- (void)startProgram:(NSString *)program
         environment:(NSDictionary *)prog_env
              isUTF8:(BOOL)isUTF8
       substitutions:(NSDictionary *)substitutions;

// This is an alternative to runCommandWithOldCwd and startProgram. It attaches
// to an existing server. Use only if [iTermAdvancedSettingsModel runJobsInServers]
// is YES.
- (void)attachToServer:(iTermFileDescriptorServerConnection)serverConnection;

- (void)softTerminate;
- (void)terminate;

// Tries to revive a terminated session. Returns YES on success. It should be re-added to a tab if
// after reviving.
- (BOOL)revive;

// Preferences
- (void)setPreferencesFromAddressBookEntry: (NSDictionary *)aePrefs;
- (void)loadInitialColorTable;

// Call this after the profile changed. If not divorced, the profile and
// settings are updated. If divorced, changes are found in the session and
// shared profiles and merged, updating this object's addressBookEntry and
// overriddenFields.
- (BOOL)reloadProfile;

- (BOOL)shouldSendEscPrefixForModifier:(unsigned int)modmask;

// Writing output.
- (void)writeTask:(NSData*)data;
- (void)writeTaskNoBroadcast:(NSData *)data;

// PTYTextView
- (BOOL)hasTextSendingKeyMappingForEvent:(NSEvent*)event;
- (BOOL)willHandleEvent: (NSEvent *)theEvent;
- (void)handleEvent: (NSEvent *)theEvent;
- (void)insertNewline:(id)sender;
- (void)insertTab:(id)sender;
- (void)moveUp:(id)sender;
- (void)moveDown:(id)sender;
- (void)moveLeft:(id)sender;
- (void)moveRight:(id)sender;
- (void)pageUp:(id)sender;
- (void)pageDown:(id)sender;
- (void)paste:(id)sender;
- (void)pasteString:(NSString *)str flags:(PTYSessionPasteFlags)flags;
- (void)deleteBackward:(id)sender;
- (void)deleteForward:(id)sender;
- (void)setSplitSelectionMode:(SplitSelectionMode)mode move:(BOOL)move;
- (void)setSmartCursorColor:(BOOL)value;
- (void)setMinimumContrast:(float)value;

// Returns the frame size for a scrollview that perfectly contains the contents
// of this session based on rows/cols, and taking into acount the presence of
// a scrollbar.
- (NSSize)idealScrollViewSizeWithStyle:(NSScrollerStyle)scrollerStyle;

// misc
- (void)setWidth:(int)width height:(int)height;

// Returns the number of pixels over or under the an ideal size.
// Will never exceed +/- cell size/2.
// If vertically is true, proposedSize is a height, else it's a width.
// Example: If the line height is 10 (no margin) and you give a proposed size of 101,
// 1 is returned. If you give a proposed size of 99, -1 is returned.
- (int)overUnder:(int)proposedSize inVerticalDimension:(BOOL)vertically;

- (void)pushWindowTitle;
- (void)popWindowTitle;
- (void)pushIconTitle;
- (void)popIconTitle;


- (void)clearBuffer;
- (void)clearScrollbackBuffer;
- (void)logStart;
- (void)logStop;

- (void)sendCommand:(NSString *)command;

// Display timer stuff
- (void)updateDisplay;
- (void)doAntiIdle;
- (NSString*)ansiColorsMatchingForeground:(NSDictionary*)fg andBackground:(NSDictionary*)bg inBookmark:(Profile*)aDict;
- (void)updateScroll;

- (void)changeFontSizeDirection:(int)dir;
- (void)setFont:(NSFont*)font
    nonAsciiFont:(NSFont*)nonAsciiFont
    horizontalSpacing:(float)horizontalSpacing
    verticalSpacing:(float)verticalSpacing;

// Assigns a new GUID to the session so that changes to the bookmark will not
// affect it. Returns the GUID of a divorced bookmark. Does nothing if already
// divorced, but still returns the divorced GUID.
- (NSString*)divorceAddressBookEntryFromPreferences;
- (void)remarry;

// Schedule the screen update timer to run in a specified number of seconds.
- (void)scheduleUpdateIn:(NSTimeInterval)timeout;

// Call refresh on the textview and schedule a timer if anything is blinking.
- (void)refreshAndStartTimerIfNeeded;

// Open the current selection with semantic history.
- (void)openSelection;

// Jump to the saved scroll position
- (void)jumpToSavedScrollPosition;

// Prepare to use the given string for the next search.
- (void)useStringForFind:(NSString*)string;

// Search for the selected text.
- (void)findWithSelection;

// Show the find view
- (void)showFindPanel;

// Find next/previous occurrence of find string.
- (void)searchNext;
- (void)searchPrevious;

- (void)setPasteboard:(NSString *)pbName;
- (void)stopCoprocess;
- (void)launchSilentCoprocessWithCommand:(NSString *)command;

- (void)setFocused:(BOOL)focused;
- (BOOL)wantsContentChangedNotification;

- (void)startTmuxMode;
- (void)tmuxDetach;
// Two sessions are compatible if they may share the same tab. Tmux clients
// impose this restriction because they must belong to the same controller.
- (BOOL)isCompatibleWith:(PTYSession *)otherSession;
- (void)setTmuxPane:(int)windowPane;

- (void)toggleShowTimestamps;
- (void)addNoteAtCursor;
- (void)showHideNotes;
- (void)previousMarkOrNote;
- (void)nextMarkOrNote;
- (void)scrollToMark:(id<iTermMark>)mark;
- (id<iTermMark>)markAddedAtCursorOfClass:(Class)theClass;

// Select this session and tab and bring window to foreground.
- (void)reveal;

// Refreshes the textview and takes a snapshot of the SessionView.
- (NSImage *)snapshot;

- (void)enterPassword:(NSString *)password;

- (void)addCapturedOutput:(CapturedOutput *)capturedOutput;

- (void)dismissAnnouncementWithIdentifier:(NSString *)identifier;
- (void)queueAnnouncement:(iTermAnnouncementViewController *)announcement
               identifier:(NSString *)identifier;

- (void)tryToRunShellIntegrationInstaller;

- (NSDictionary *)arrangementWithContents:(BOOL)includeContents;

- (void)toggleTmuxZoom;

// Kill the running command (if possible), print a banner, and rerun the profile's command.
- (void)restartSession;

// Make this session's textview the first responder.
- (void)takeFocus;

// Show an announcement explaining why a restored session is an orphan.
- (void)showOrphanAnnouncement;

#pragma mark - Testing utilities

- (void)synchronousReadTask:(NSString *)string;

#pragma mark - Private for use by Scripting category

- (void)setSessionSpecificProfileValues:(NSDictionary *)newValues;

@end

