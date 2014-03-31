// Implements the model class for a terminal session.

#import "DVR.h"
#import "FindViewController.h"
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

@class FakeWindow;
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

// The time period for just blinking is in -[PreferencePanel timeBetweenBlinks].
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
@property(nonatomic, readonly) int sessionID;
@property(nonatomic, copy) NSColor *tabColor;

@property(nonatomic, readonly) DVR *dvr;
@property(nonatomic, readonly) DVRDecoder *dvrDecoder;
// Returns the "real" session while in instant replay, else nil if not in IR.
@property(nonatomic, readonly) PTYSession *liveSession;
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

@property(nonatomic, readonly) struct timeval lastOutput;

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

// A temporary unique name (actually the tty) for this session.
@property(nonatomic, readonly) NSString *uniqueID;

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

// TODO(georgen): Actually use this. It's not well documented and the xterm code is a crazy mess :(.
// For future reference, in tmux commit 8df3ec612a8c496fc2c975b8241f4e95faef5715 the list of xterm
// keys gives a hint about how this is supposed to work (e.g., control-! sends a long CSI code). See also
// the xterm manual (look for modifyOtherKeys, etc.) for valid values, and ctlseqs.html on invisible-island
// for the meaning of the indices (under CSI > Ps; Pm m).
@property(nonatomic, retain) NSArray *sendModifiers;

// Return the address book that the session was originally created with.
@property(nonatomic, readonly) Profile *originalProfile;

// tty device
@property(nonatomic, readonly) NSString *tty;

// True if background image should be tiled
@property(nonatomic, assign) BOOL backgroundImageTiled;

// Filename of background image.
@property(nonatomic, copy) NSString *backgroundImagePath;
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

// Last time this session became active
@property(nonatomic, retain) NSDate *lastActiveAt;

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

// Key-value coding compliance for Applescript. It's generally better to go through the |colorMap|.
@property(nonatomic, retain) NSColor *backgroundColor;
@property(nonatomic, retain) NSColor *boldColor;
@property(nonatomic, retain) NSColor *cursorColor;
@property(nonatomic, retain) NSColor *cursorTextColor;
@property(nonatomic, retain) NSColor *foregroundColor;
@property(nonatomic, retain) NSColor *selectedTextColor;
@property(nonatomic, retain) NSColor *selectionColor;

// Session is not in foreground and notifications are enabled on the screen.
@property(nonatomic, readonly) BOOL shouldPostGrowlNotification;

#pragma mark - methods

+ (BOOL)handleShortcutWithoutTerminal:(NSEvent*)event;
+ (void)selectMenuItem:(NSString*)theName;

// Jump to a particular point in time.
- (long long)irSeekToAtLeast:(long long)timestamp;

// Disable all timers.
- (void)cancelTimers;

// Begin showing DVR frames from some live session.
- (void)setDvr:(DVR*)dvr liveSession:(PTYSession*)liveSession;

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
- (void)textViewFontDidChange;

// Set rows, columns from arrangement.
- (void)resizeFromArrangement:(NSDictionary *)arrangement;

- (void)runCommandWithOldCwd:(NSString*)oldCWD
               forObjectType:(iTermObjectType)objectType;

- (void)startProgram:(NSString *)program
           arguments:(NSArray *)prog_argv
         environment:(NSDictionary *)prog_env
              isUTF8:(BOOL)isUTF8;

- (void)softTerminate;
- (void)terminate;


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
- (void)setSplitSelectionMode:(SplitSelectionMode)mode;
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


// Jump to the saved scroll position
- (void)jumpToSavedScrollPosition;

// Prepare to use the given string for the next search.
- (void)useStringForFind:(NSString*)string;

// Search for the selected text.
- (void)findWithSelection;

// Show/hide the find view
- (void)toggleFind;

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
- (void)scrollToMark:(VT100ScreenMark *)mark;

// Select this session and tab and bring window to foreground.
- (void)reveal;

// Refreshes the textview and takes a snapshot of the SessionView.
- (NSImage *)snapshot;

#pragma mark - Scripting Support

// Object specifier
- (NSScriptObjectSpecifier *)objectSpecifier;
- (void)handleExecScriptCommand:(NSScriptCommand *)aCommand;
- (void)handleTerminateScriptCommand:(NSScriptCommand *)command;
- (void)handleSelectScriptCommand:(NSScriptCommand *)command;
- (void)handleWriteScriptCommand:(NSScriptCommand *)command;
- (void)handleClearScriptCommand:(NSScriptCommand *)command;

@end

