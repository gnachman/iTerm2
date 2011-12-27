//
//  TmuxController.h
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import <Cocoa/Cocoa.h>
#import "TmuxGateway.h"

@class PTYSession;
@class PTYTab;
@class PseudoTerminal;

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

@interface TmuxController : NSObject {
    TmuxGateway *gateway_;
    NSMutableDictionary *windowPanes_;  // [window, pane] -> PTYSession *
    NSMutableDictionary *windows_;      // window -> [PTYTab *, refcount]
    NSArray *sessions_;
    int numOutstandingWindowResizes_;
    NSMutableDictionary *windowPositions_;
    NSSize lastSize_;  // last size for windowDidChange:
    BOOL detached_;
    NSString *sessionName_;
    NSMutableSet *pendingWindowOpens_;
}

@property (nonatomic, readonly) TmuxGateway *gateway;
@property (nonatomic, retain) NSMutableDictionary *windowPositions;
@property (nonatomic, copy) NSString *sessionName;
@property (nonatomic, retain) NSArray *sessions;

- (id)initWithGateway:(TmuxGateway *)gateway;
- (void)openWindowsInitial;
- (void)openWindowWithId:(int)windowId;
- (void)openWindowWithId:(int)windowId affinities:(NSArray *)affinities;
- (PTYSession *)sessionWithAffinityForTmuxWindowId:(int)windowId;

- (void)setLayoutInTab:(PTYTab *)tab
                toLayout:(NSString *)layout;
- (void)sessionChangedTo:(NSString *)newSessionName;
- (void)sessionsChanged;
- (void)sessionRenamedTo:(NSString *)newName;
- (void)windowsChanged;
- (void)windowWasRenamedWithId:(int)id to:(NSString *)newName;

- (PTYSession *)sessionForWindowPane:(int)windowPane;
- (PTYTab *)window:(int)window;
- (void)registerSession:(PTYSession *)aSession
               withPane:(int)windowPane
               inWindow:(int)window;
- (void)deregisterWindow:(int)window windowPane:(int)windowPane;
- (NSValue *)positionForWindowWithPanes:(NSArray *)panes;

// This should be called after the host sends an %exit command.
- (void)detach;
- (void)windowDidResize:(PseudoTerminal *)term;
- (BOOL)hasOutstandingWindowResize;
- (void)windowPane:(int)wp
         resizedBy:(int)amount
      horizontally:(BOOL)wasHorizontal;
- (void)splitWindowPane:(int)wp vertically:(BOOL)splitVertically;
- (void)newWindowInSession:(NSString *)targetSession afterWindowWithName:(NSString *)predecessorWindow;

- (void)newWindowWithAffinity:(int)paneNumber;
- (void)movePane:(int)srcPane
        intoPane:(int)destPane
      isVertical:(BOOL)splitVertical
          before:(BOOL)addBefore;
- (void)breakOutWindowPane:(int)windowPane toPoint:(NSPoint)screenPoint;
- (void)killWindowPane:(int)windowPane;
- (void)killWindow:(int)window;
- (void)unlinkWindowWithId:(int)windowId inSession:(NSString *)sessionName;
- (BOOL)isAttached;
- (void)requestDetach;
- (void)renameWindowWithId:(int)windowId toName:(NSString *)newName;

- (void)renameSession:(NSString *)oldName to:(NSString *)newName;
- (void)killSession:(NSString *)sessionName;
- (void)attachToSession:(NSString *)sessionName;
- (void)addSessionWithName:(NSString *)sessionName;
- (void)listWindowsInSession:(NSString *)sessionName
                      target:(id)target
                    selector:(SEL)selector
                      object:(id)object;

@end
