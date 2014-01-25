// Implements the model class for a terminal session.

#import "DVR.h"
#import "FindViewController.h"
#import "ITAddressBookMgr.h"
#import "LineBuffer.h"
#import "PTYTask.h"
#import "PTYTextView.h"
#import "PasteViewController.h"
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
@class iTermController;
@class iTermGrowlDelegate;

// The time period for just blinking is in -[PreferencePanel timeBetweenBlinks].
// Timer period when receiving lots of data.
static const float kSlowTimerIntervalSec = 1.0 / 10.0;
// Timer period for very small updates
static const float kSuperFastTimerIntervalSec = 0.002;
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
    PasteViewControllerDelegate,
    PopupDelegate,
    PTYTaskDelegate,
    PTYTextViewDelegate,
    TmuxGatewayDelegate,
    VT100ScreenDelegate>

@property(nonatomic, assign) BOOL alertOnNextMark;
@property(nonatomic, readonly) int sessionID;
@property(nonatomic, copy) NSColor *tabColor;

// Return the current pasteboard value as a string.
+ (NSString*)pasteboardString;
+ (BOOL)handleShortcutWithoutTerminal:(NSEvent*)event;
+ (void)selectMenuItem:(NSString*)theName;

- (BOOL)isTmuxClient;
- (BOOL)isTmuxGateway;

// init/dealloc
- (id)init;
- (void)dealloc;

// accessor
- (DVR*)dvr;

// accessor
- (DVRDecoder*)dvrDecoder;

// Jump to a particular point in time.
- (long long)irSeekToAtLeast:(long long)timestamp;

// accessor. nil if this session is live.
- (PTYSession*)liveSession;

// test if we're at the beginning/end of time.
- (BOOL)canInstantReplayPrev;
- (BOOL)canInstantReplayNext;

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

- (void)setNewOutput:(BOOL)value;
- (BOOL)newOutput;

// Preferences
- (void)setPreferencesFromAddressBookEntry: (NSDictionary *)aePrefs;
- (void)loadInitialColorTable;

// Call this after the profile changed. If not divorced, the profile and
// settings are updated. If divorced, changes are found in the session and
// shared profiles and merged, updating this object's addressBookEntry and
// overriddenFields.
- (BOOL)reloadProfile;

// PTYTask
- (void)writeTask:(NSData*)data;
- (void)writeTaskNoBroadcast:(NSData *)data;
- (void)readTask:(NSData*)data;
- (void)brokenPipe;

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
- (void)pasteString:(NSString *)str flags:(int)flags;
- (void)deleteBackward:(id)sender;
- (void)deleteForward:(id)sender;
- (void)textViewDidChangeSelection: (NSNotification *)aNotification;
- (void)textViewResized: (NSNotification *)aNotification;

// Returns the frame size for a scrollview that perfectly contains the contents
// of this session based on rows/cols, and taking into acount the presence of
// a scrollbar.
- (NSSize)idealScrollViewSizeWithStyle:(NSScrollerStyle)scrollerStyle;

// misc
- (void)setWidth:(int)width height:(int)height;

// Do we need to prompt on close for this session?
- (BOOL)promptOnClose;

- (void)setSplitSelectionMode:(SplitSelectionMode)mode;

// Returns the number of pixels over or under the an ideal size.
// Will never exceed +/- cell size/2.
// If vertically is true, proposedSize is a height, else it's a width.
// Example: If the line height is 10 (no margin) and you give a proposed size of 101,
// 1 is returned. If you give a proposed size of 99, -1 is returned.
- (int)overUnder:(int)proposedSize inVerticalDimension:(BOOL)vertically;

// Array of subprocessess names.
- (NSArray *)childJobNames;

// get/set methods
- (PTYTab*)tab;
- (PTYTab*)ptytab;
- (void)setTab:(PTYTab*)tab;
- (struct timeval)lastOutput;
- (void)setGrowlIdle:(BOOL)value;
- (BOOL)growlIdle;
- (void)setGrowlNewOutput:(BOOL)value;
- (BOOL)growlNewOutput;

- (NSString *)windowName;
- (NSString *)name;
- (NSString*)rawName;
- (void)setBookmarkName:(NSString*)theName;
- (void)setName: (NSString *)theName;
- (NSString *)defaultName;
- (NSString*)joblessDefaultName;
- (void)setDefaultName: (NSString *)theName;
- (NSString *)uniqueID;
- (void)setUniqueID: (NSString *)uniqueID;
- (NSString*)formattedName:(NSString*)base;
- (NSString *)windowTitle;
- (void)setWindowTitle: (NSString *)theTitle;
- (void)pushWindowTitle;
- (void)popWindowTitle;
- (void)pushIconTitle;
- (void)popIconTitle;
- (PTYTask *)SHELL;
- (void)setSHELL: (PTYTask *)theSHELL;
- (VT100Terminal *)TERMINAL;
- (NSString *)TERM_VALUE;
- (void)setTERM_VALUE: (NSString *)theTERM_VALUE;
- (NSString *)COLORFGBG_VALUE;
- (void)setCOLORFGBG_VALUE: (NSString *)theCOLORFGBG_VALUE;
- (VT100Screen *)SCREEN;
- (void)setSCREEN: (VT100Screen *)theSCREEN;
- (SessionView *)view;
- (void)setView:(SessionView*)newView;
- (PTYTextView *)TEXTVIEW;
- (void)setTEXTVIEW: (PTYTextView *)theTEXTVIEW;
- (void)setSCROLLVIEW: (PTYScrollView *)theSCROLLVIEW;
- (NSStringEncoding)encoding;
- (void)setEncoding:(NSStringEncoding)encoding;
- (BOOL)antiIdle;
- (int)antiCode;
- (void)setAntiIdle:(BOOL)set;
- (void)setAntiCode:(int)code;
- (BOOL)autoClose;
- (void)setAutoClose:(BOOL)set;
- (BOOL)doubleWidth;
- (void)setDoubleWidth:(BOOL)set;
- (void)setXtermMouseReporting:(BOOL)set;
- (NSDictionary *)addressBookEntry;
- (void)setSendModifiers:(NSArray *)sendModifiers;

// Return the address book that the session was originally created with.
- (Profile *)originalAddressBookEntry;
- (void)setAddressBookEntry:(NSDictionary*)entry;
- (NSString *)tty;
- (NSString *)contents;
- (iTermGrowlDelegate*)growlDelegate;


- (void)clearBuffer;
- (void)clearScrollbackBuffer;
- (BOOL)logging;
- (void)logStart;
- (void)logStop;
- (BOOL)backgroundImageTiled;
- (void)setBackgroundImageTiled:(BOOL)set;
- (NSString *)backgroundImagePath;
- (void)setBackgroundImagePath: (NSString *)imageFilePath;
- (NSColor *)foregroundColor;
- (void)setForegroundColor:(NSColor*)color;
- (NSColor *)backgroundColor;
- (void)setBackgroundColor:(NSColor*)color;
- (NSColor *)selectionColor;
- (void)setSelectionColor: (NSColor *)color;
- (NSColor *)boldColor;
- (void)setBoldColor:(NSColor*)color;
- (NSColor *)cursorColor;
- (void)setCursorColor:(NSColor*)color;
- (void)setSmartCursorColor:(BOOL)value;
- (void)setMinimumContrast:(float)value;
- (NSColor *)selectedTextColor;
- (void)setSelectedTextColor: (NSColor *)aColor;
- (NSColor *)cursorTextColor;
- (void)setCursorTextColor: (NSColor *)aColor;
- (float)transparency;
- (void)setTransparency:(float)transparency;
- (float)blend;
- (void)setBlend:(float)blend;
- (BOOL)useBoldFont;
- (void)setUseBoldFont:(BOOL)boldFlag;
- (BOOL)useItalicFont;
- (void)setUseItalicFont:(BOOL)boldFlag;
- (void)setColorTable:(int)index color:(NSColor *)c;
- (BOOL)shouldSendEscPrefixForModifier:(unsigned int)modmask;

// Session status

- (BOOL)exited;
- (BOOL)bell;
- (void)setBell:(BOOL)flag;

- (void)sendCommand:(NSString *)command;

- (NSDictionary*)arrangement;

// Display timer stuff
- (void)updateDisplay;
- (void)doAntiIdle;
- (NSString*)ansiColorsMatchingForeground:(NSDictionary*)fg andBackground:(NSDictionary*)bg inBookmark:(Profile*)aDict;
- (void)updateScroll;

- (int)columns;
- (int)rows;
- (void)changeFontSizeDirection:(int)dir;
- (void)setFont:(NSFont*)font nafont:(NSFont*)nafont horizontalSpacing:(float)horizontalSpacing verticalSpacing:(float)verticalSpacing;

// Assigns a new GUID to the session so that changes to the bookmark will not
// affect it. Returns the GUID of a divorced bookmark. Does nothing if already
// divorced, but still returns the divorced GUID.
- (NSString*)divorceAddressBookEntryFromPreferences;
- (BOOL)isDivorced;
- (void)remarry;

// Schedule the screen update timer to run in a specified number of seconds.
- (void)scheduleUpdateIn:(NSTimeInterval)timeout;

// Call refresh on the textview and schedule a timer if anything is blinking.
- (void)refreshAndStartTimerIfNeeded;

- (NSString*)jobName;
- (NSString*)uncachedJobName;

- (void)setIgnoreResizeNotifications:(BOOL)ignore;
- (BOOL)ignoreResizeNotifications;

- (void)setLastActiveAt:(NSDate*)date;
- (NSDate*)lastActiveAt;

// Jump to the saved scroll position
- (void)jumpToSavedScrollPosition;

// Is there a saved scroll position?
- (BOOL)hasSavedScrollPosition;

// Prepare to use the given string for the next search.
- (void)useStringForFind:(NSString*)string;

// Search for the selected text.
- (void)findWithSelection;

// Show/hide the find view
- (void)toggleFind;

// Find next/previous occurrence of find string.
- (void)searchNext;
- (void)searchPrevious;

// Bitmap of how the session looks.
- (NSImage *)imageOfSession:(BOOL)flip;

// Image for dragging one session.
- (NSImage *)dragImage;

- (void)setPasteboard:(NSString *)pbName;
- (BOOL)hasCoprocess;
- (void)stopCoprocess;
- (void)launchSilentCoprocessWithCommand:(NSString *)command;

- (void)setFocused:(BOOL)focused;
- (BOOL)wantsContentChangedNotification;

- (void)startTmuxMode;
- (void)tmuxDetach;
- (int)tmuxPane;
// Two sessions are compatible if they may share the same tab. Tmux clients
// impose this restriction because they must belong to the same controller.
- (BOOL)isCompatibleWith:(PTYSession *)otherSession;
- (void)setTmuxPane:(int)windowPane;
- (void)setTmuxController:(TmuxController *)tmuxController;

- (TmuxController *)tmuxController;

- (void)toggleShowTimestamps;
- (void)addNoteAtCursor;
- (void)showHideNotes;
- (void)previousMarkOrNote;
- (void)nextMarkOrNote;
- (void)scrollToMark:(VT100ScreenMark *)mark;

- (VT100RemoteHost *)currentHost;

// Select this session and tab and bring window to foreground.
- (void)reveal;

// FinalTerm
- (NSArray *)autocompleteSuggestionsForCurrentCommand;
- (NSString *)currentCommand;

@end

@interface PTYSession (ScriptingSupport)

// Object specifier
- (NSScriptObjectSpecifier *)objectSpecifier;
-(void)handleExecScriptCommand: (NSScriptCommand *)aCommand;
-(void)handleTerminateScriptCommand: (NSScriptCommand *)command;
-(void)handleSelectScriptCommand: (NSScriptCommand *)command;
-(void)handleWriteScriptCommand: (NSScriptCommand *)command;
-(void)handleClearScriptCommand: (NSScriptCommand *)command;

@end

