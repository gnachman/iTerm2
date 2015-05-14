//
//  TmuxController.h
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import <Cocoa/Cocoa.h>
#import "TmuxGateway.h"
#import "WindowControllerInterface.h"

@class PTYSession;
@class PTYTab;
@class PseudoTerminal;
@class EquivalenceClassSet;

// Posted when sessions change (names, addition, deletion)
extern NSString *kTmuxControllerSessionsDidChange;
// Posted after detaching
extern NSString *kTmuxControllerDetachedNotification;
// Posted when a window changes.
extern NSString *kTmuxControllerWindowsChangeNotification;
// Posted when a window changes name
extern NSString *kTmuxControllerWindowWasRenamed;
// Posted when a window opens
extern NSString *kTmuxControllerWindowDidOpen;
// Posted when a window closes
extern NSString *kTmuxControllerWindowDidClose;
// Posted when the attached session changes
extern NSString *kTmuxControllerAttachedSessionDidChange;
// Posted when a session changes name
extern NSString *kTmuxControllerSessionWasRenamed;

@interface TmuxController : NSObject {
    TmuxGateway *gateway_;
    NSMutableDictionary *windowPanes_;  // paneId -> PTYSession *
    NSMutableDictionary *windows_;      // window -> [PTYTab *, refcount]
    NSArray *sessions_;
    int numOutstandingWindowResizes_;
    NSMutableDictionary *windowPositions_;
    NSSize lastSize_;  // last size for windowDidChange:
    NSString *lastOrigins_;
    BOOL detached_;
    NSString *sessionName_;
    int sessionId_;
    NSMutableSet *pendingWindowOpens_;
    NSString *lastSaveAffinityCommand_;
    // tmux windows that want to open as tabs in the same physical window
    // belong to the same equivalence class.
    EquivalenceClassSet *affinities_;
    BOOL windowOriginsDirty_;
    BOOL haveOutstandingSaveWindowOrigins_;
    NSMutableDictionary *origins_;  // window id -> NSValue(Point) window origin
    NSMutableSet *hiddenWindows_;
    NSTimer *listSessionsTimer_;  // Used to do a cancelable delayed perform of listSessions.
    NSTimer *listWindowsTimer_;  // Used to do a cancelable delayed perform of listWindows.
    BOOL ambiguousIsDoubleWidth_;
}

@property (nonatomic, readonly) TmuxGateway *gateway;
@property (nonatomic, retain) NSMutableDictionary *windowPositions;
@property (nonatomic, copy) NSString *sessionName;
@property (nonatomic, retain) NSArray *sessions;
@property (nonatomic, assign) BOOL ambiguousIsDoubleWidth;
@property (nonatomic, readonly) NSString *clientName;

- (id)initWithGateway:(TmuxGateway *)gateway clientName:(NSString *)clientName;
- (void)openWindowsInitial;
- (void)openWindowWithId:(int)windowId
			 intentional:(BOOL)intentional;
- (void)openWindowWithId:(int)windowId
			  affinities:(NSArray *)affinities
			 intentional:(BOOL)intentional;
- (void)hideWindow:(int)windowId;

- (void)setLayoutInTab:(PTYTab *)tab
                toLayout:(NSString *)layout;
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
- (void)setClientSize:(NSSize)size;
- (BOOL)hasOutstandingWindowResize;
- (void)windowPane:(int)wp
         resizedBy:(int)amount
      horizontally:(BOOL)wasHorizontal;
- (void)splitWindowPane:(int)wp vertically:(BOOL)splitVertically;
- (void)newWindowInSession:(NSString *)targetSession afterWindowWithName:(NSString *)predecessorWindow;

- (PseudoTerminal *)windowWithAffinityForWindowId:(int)wid;
// nil: Open in a new window
// A string of a non-negative integer (e.g., @"2") means to open alongside a tmux window with that ID
// A string of a negative integer (e.g., @"-2") means to open in an iTerm2 window with abs(windowId)==window number.
- (void)newWindowWithAffinity:(NSString *)windowId;
- (void)movePane:(int)srcPane
        intoPane:(int)destPane
      isVertical:(BOOL)splitVertical
          before:(BOOL)addBefore;
- (void)breakOutWindowPane:(int)windowPane toPoint:(NSPoint)screenPoint;
- (void)breakOutWindowPane:(int)windowPane toTabAside:(NSString *)sibling;

- (void)killWindowPane:(int)windowPane;
- (void)killWindow:(int)window;
- (void)unlinkWindowWithId:(int)windowId inSession:(NSString *)sessionName;
- (BOOL)isAttached;
- (void)requestDetach;
- (void)renameWindowWithId:(int)windowId inSession:(NSString *)sessionName toName:(NSString *)newName;
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
@end
