//
//  TmuxController.h
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import <Cocoa/Cocoa.h>
#import "ProfileModel.h"
#import "iTermInitialDirectory.h"
#import "iTermTmuxSessionObject.h"
#import "TmuxGateway.h"
#import "WindowControllerInterface.h"

@class iTermVariableScope;
@class PTYSession;
@class PTYTab;
@class PseudoTerminal;
@class EquivalenceClassSet;

// Posted when sessions change (names, addition, deletion)
extern NSString *const kTmuxControllerSessionsDidChange;
// Posted after detaching
extern NSString *const kTmuxControllerDetachedNotification;
// Posted when a window changes.
extern NSString *const kTmuxControllerWindowsChangeNotification;
// Posted when a window changes name
extern NSString *const kTmuxControllerWindowWasRenamed;
// Posted when a window opens
extern NSString *const kTmuxControllerWindowDidOpen;
// Posted when a window closes
extern NSString *const kTmuxControllerWindowDidClose;
// Posted when the attached session changes
extern NSString *const kTmuxControllerAttachedSessionDidChange;
// Posted when a session changes name
extern NSString *const kTmuxControllerSessionWasRenamed;
// Posted when set-titles option changes. Object is tmux controller.
extern NSString *const kTmuxControllerDidFetchSetTitlesStringOption;

@interface TmuxController : NSObject

@property(nonatomic, readonly) TmuxGateway *gateway;
@property(nonatomic, retain) NSMutableDictionary *windowPositions;
@property(nonatomic, copy) NSString *sessionName;
@property(nonatomic, copy) NSArray<iTermTmuxSessionObject *> *sessionObjects;
@property(nonatomic, assign) BOOL ambiguousIsDoubleWidth;
@property(nonatomic, assign) NSInteger unicodeVersion;
@property(nonatomic, readonly) NSString *clientName;
@property(nonatomic, readonly) int sessionId;
@property(nonatomic, readonly) BOOL hasOutstandingWindowResize;
@property(nonatomic, readonly, getter=isAttached) BOOL attached;
@property(nonatomic, readonly) BOOL detaching;
@property(nonatomic, copy) Profile *sharedProfile;
@property(nonatomic, readonly) NSDictionary *sharedFontOverrides;
@property(nonatomic, readonly) NSString *sessionGuid;
@property(nonatomic, readonly) BOOL variableWindowSize;
@property(nonatomic, readonly) BOOL shouldSetTitles;
@property(nonatomic, readonly) BOOL serverIsLocal;

- (instancetype)initWithGateway:(TmuxGateway *)gateway
                     clientName:(NSString *)clientName
                        profile:(Profile *)profile
                   profileModel:(ProfileModel *)profileModel NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (Profile *)profileForWindow:(int)window;
- (NSDictionary *)fontOverridesForWindow:(int)window;

- (void)openWindowsInitial;

- (void)openWindowWithId:(int)windowId
			 intentional:(BOOL)intentional
                 profile:(Profile *)profile;

- (void)openWindowWithId:(int)windowId
			  affinities:(NSArray *)affinities
			 intentional:(BOOL)intentional
                 profile:(Profile *)profile;

- (void)hideWindow:(int)windowId;

// Modifies a native tab to match the given server layout.
- (void)setLayoutInTab:(PTYTab *)tab
              toLayout:(NSString *)layout
                zoomed:(NSNumber *)zoomed;
- (void)sessionChangedTo:(NSString *)newSessionName sessionId:(int)sessionid;
- (void)sessionsChanged;
- (void)session:(int)sessionId renamedTo:(NSString *)newName;
- (void)windowsChanged;
- (void)windowWasRenamedWithId:(int)id to:(NSString *)newName;

- (PTYSession *)sessionForWindowPane:(int)windowPane;
- (PTYTab *)window:(int)window;
- (NSArray<PTYSession *> *)sessionsInWindow:(int)window;
- (void)registerSession:(PTYSession *)aSession
               withPane:(int)windowPane
               inWindow:(int)window;
- (void)deregisterWindow:(int)window windowPane:(int)windowPane session:(id)session;
- (void)changeWindow:(int)window tabTo:(PTYTab *)tab;
- (NSValue *)positionForWindowWithPanes:(NSArray *)panes;

// This should be called after the host sends an %exit command.
- (void)detach;
- (void)windowDidResize:(NSWindowController<iTermWindowController> *)term;
- (void)fitLayoutToWindows;
- (void)validateOptions;
- (void)ping;

// Issue tmux commands to infer bounds on the version.
- (void)guessVersion;
- (void)loadTitleFormat;

- (void)setClientSize:(NSSize)size;
- (void)windowPane:(int)wp
         resizedBy:(int)amount
      horizontally:(BOOL)wasHorizontal;

- (void)splitWindowPane:(int)wp
             vertically:(BOOL)splitVertically
                  scope:(iTermVariableScope *)scope
       initialDirectory:(iTermInitialDirectory *)initialDirectory;

- (void)newWindowInSessionNumber:(NSNumber *)sessionNumber
                           scope:(iTermVariableScope *)scope
                initialDirectory:(iTermInitialDirectory *)initialDirectory;

- (void)selectPane:(int)windowPane;

- (PseudoTerminal *)windowWithAffinityForWindowId:(int)wid;
- (NSSet<NSObject<NSCopying> *> *)savedAffinitiesForWindow:(NSString *)value;
- (NSSize)sizeOfSmallestWindowAmong:(NSSet<NSString *> *)siblings;

// nil: Open in a new window
// A string of a non-negative integer (e.g., @"2") means to open alongside a tmux window with that ID
// A string of a negative integer (e.g., @"-2") means to open in an iTerm2 window with abs(windowId)==window number.
// If affinity is given then the newly created tab will be considered "manually opened" which is
// used to determine the tab's eventual location in the tabbar.
- (void)newWindowWithAffinity:(NSString *)windowIdString
                         size:(NSSize)size
             initialDirectory:(iTermInitialDirectory *)initialDirectory
                        scope:(iTermVariableScope *)scope
                   completion:(void (^)(int))completion;

- (void)movePane:(int)srcPane
        intoPane:(int)destPane
      isVertical:(BOOL)splitVertical
          before:(BOOL)addBefore;
- (void)breakOutWindowPane:(int)windowPane toPoint:(NSPoint)screenPoint;
- (void)breakOutWindowPane:(int)windowPane toTabAside:(NSString *)sibling;

- (void)killWindowPane:(int)windowPane;
- (void)killWindow:(int)window;
- (void)unlinkWindowWithId:(int)windowId;
- (void)requestDetach;
- (void)renameWindowWithId:(int)windowId
           inSessionNumber:(NSNumber *)sessionNumber
                    toName:(NSString *)newName;
- (BOOL)canRenamePane;
- (void)renamePane:(int)windowPane toTitle:(NSString *)newTitle;
- (void)setHotkeyForWindowPane:(int)windowPane to:(NSDictionary *)hotkey;
- (NSDictionary *)hotkeyForWindowPane:(int)windowPane;

- (void)setTabColorString:(NSString *)colorString forWindowPane:(int)windowPane;
- (NSString *)tabColorStringForWindowPane:(int)windowPane;

- (void)linkWindowId:(int)windowId
     inSessionNumber:(int)sessionNumber
     toSessionNumber:(int)targetSession;

- (void)moveWindowId:(int)windowId
     inSessionNumber:(int)sessionNumber
     toSessionNumber:(int)targetSessionNumber;

- (void)renameSessionNumber:(int)sessionNumber
                         to:(NSString *)newName;

- (void)killSessionNumber:(int)sessionNumber;
- (void)attachToSessionWithNumber:(int)sessionNumber;
- (void)addSessionWithName:(NSString *)sessionName;
// NOTE: If anything goes wrong the selector will not be called.
- (void)listWindowsInSessionNumber:(int)sessionNumber
                            target:(id)target
                          selector:(SEL)selector
                            object:(id)object;

- (void)listSessions;
- (void)saveAffinities;
- (void)saveWindowOrigins;
- (void)saveHiddenWindows;

- (void)swapPane:(int)pane1 withPane:(int)pane2;
- (void)toggleZoomForPane:(int)pane;
- (void)setPartialWindowIdOrder:(NSArray *)partialOrder;
- (void)setCurrentWindow:(int)windowId;
- (void)checkForUTF8;

- (void)clearHistoryForWindowPane:(int)windowPane;

- (void)setTmuxFont:(NSFont *)font
       nonAsciiFont:(NSFont *)nonAsciiFont
           hSpacing:(double)hs
           vSpacing:(double)vs
             window:(int)window;
- (BOOL)windowIsHidden:(int)windowId;
- (void)setLayoutInWindowPane:(int)windowPane toLayoutNamed:(NSString *)name;
- (void)setLayoutInWindow:(int)window toLayout:(NSString *)layout;
- (NSArray<PTYSession *> *)clientSessions;

- (void)setSize:(NSSize)size window:(int)window;

@end
