//
//  TmuxController.h
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import <Cocoa/Cocoa.h>
#import "iTermInitialDirectory.h"
#import "TmuxGateway.h"
#import "WindowControllerInterface.h"

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

@interface TmuxController : NSObject

@property(nonatomic, readonly) TmuxGateway *gateway;
@property(nonatomic, retain) NSMutableDictionary *windowPositions;
@property(nonatomic, copy) NSString *sessionName;
@property(nonatomic, retain) NSArray *sessions;
@property(nonatomic, assign) BOOL ambiguousIsDoubleWidth;
@property(nonatomic, assign) NSInteger unicodeVersion;
@property(nonatomic, readonly) NSString *clientName;
@property(nonatomic, readonly) int sessionId;
@property(nonatomic, readonly) BOOL hasOutstandingWindowResize;
@property(nonatomic, readonly, getter=isAttached) BOOL attached;

- (instancetype)initWithGateway:(TmuxGateway *)gateway clientName:(NSString *)clientName;
- (void)openWindowsInitial;
- (void)openWindowWithId:(int)windowId
			 intentional:(BOOL)intentional;
- (void)openWindowWithId:(int)windowId
			  affinities:(NSArray *)affinities
			 intentional:(BOOL)intentional;
- (void)hideWindow:(int)windowId;

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
- (void)registerSession:(PTYSession *)aSession
               withPane:(int)windowPane
               inWindow:(int)window;
- (void)deregisterWindow:(int)window windowPane:(int)windowPane session:(id)session;
- (void)changeWindow:(int)window tabTo:(PTYTab *)tab;
- (NSValue *)positionForWindowWithPanes:(NSArray *)panes;

// This should be called after the host sends an %exit command.
- (void)detach;
- (BOOL)windowDidResize:(NSWindowController<iTermWindowController> *)term;
- (void)fitLayoutToWindows;
- (void)validateOptions;

// Issue tmux commands to infer bounds on the version.
- (void)guessVersion;

- (void)setClientSize:(NSSize)size;
- (void)windowPane:(int)wp
         resizedBy:(int)amount
      horizontally:(BOOL)wasHorizontal;
- (void)splitWindowPane:(int)wp
             vertically:(BOOL)splitVertically
       initialDirectory:(iTermInitialDirectory *)initialDirectory;
- (void)newWindowInSession:(NSString *)targetSession
          initialDirectory:(iTermInitialDirectory *)initialDirectory;

- (void)selectPane:(int)windowPane;

- (PseudoTerminal *)windowWithAffinityForWindowId:(int)wid;

// nil: Open in a new window
// A string of a non-negative integer (e.g., @"2") means to open alongside a tmux window with that ID
// A string of a negative integer (e.g., @"-2") means to open in an iTerm2 window with abs(windowId)==window number.
// If affinity is given then the newly created tab will be considered "manually opened" which is
// used to determine the tab's eventual location in the tabbar.
- (void)newWindowWithAffinity:(NSString *)windowId
             initialDirectory:(iTermInitialDirectory *)initialDirectory;

- (void)movePane:(int)srcPane
        intoPane:(int)destPane
      isVertical:(BOOL)splitVertical
          before:(BOOL)addBefore;
- (void)breakOutWindowPane:(int)windowPane toPoint:(NSPoint)screenPoint;
- (void)breakOutWindowPane:(int)windowPane toTabAside:(NSString *)sibling;

- (void)killWindowPane:(int)windowPane;
- (void)killWindow:(int)window;
- (void)unlinkWindowWithId:(int)windowId inSession:(NSString *)sessionName;
- (void)requestDetach;
- (void)renameWindowWithId:(int)windowId inSession:(NSString *)sessionName toName:(NSString *)newName;
- (void)setHotkeyForWindowPane:(int)windowPane to:(NSDictionary *)hotkey;
- (NSDictionary *)hotkeyForWindowPane:(int)windowPane;

- (void)setTabColorString:(NSString *)colorString forWindowPane:(int)windowPane;
- (NSString *)tabColorStringForWindowPane:(int)windowPane;

- (void)linkWindowId:(int)windowId
           inSession:(NSString *)sessionName
           toSession:(NSString *)targetSession;

- (void)renameSession:(NSString *)oldName to:(NSString *)newName;
- (void)killSession:(NSString *)sessionName;
- (void)attachToSession:(NSString *)sessionName;
- (void)addSessionWithName:(NSString *)sessionName;
// NOTE: If the session name is bogus (or any other error occurs) the selector will not be called.
- (void)listWindowsInSession:(NSString *)sessionName
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

@end
