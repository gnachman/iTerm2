//
//  MovePaneController.h
//  iTerm2
//
//  Runs the show for moving a session into a split pane.
//
//  Created by George Nachman on 8/26/11.

#import <Foundation/Foundation.h>
#import "SplitSelectionView.h"

extern NSString *const iTermMovePaneDragType;
extern NSString *const iTermSessionDidChangeTabNotification;

@class PseudoTerminal;
@class PTYTab;
@class PTYSession;
@class SessionView;
@interface MovePaneController : NSObject <SplitSelectionViewDelegate>

@property (nonatomic, readonly) BOOL isDragInProgress;
@property (nonatomic, readonly) BOOL dropping;
@property (nonatomic, assign) BOOL dragFailed;
@property (nonatomic, assign) PTYSession *session;

+ (instancetype)sharedInstance;
// Initiate click-to-move mode.
- (void)movePane:(PTYSession *)session;

// Initiate click-to-swap mode.
- (void)swapPane:(PTYSession *)session;

- (void)exitMovePaneMode;
// Initiate dragging.
- (void)beginDrag:(PTYSession *)session;

// Initiate dragging a session whose view was grabbed at grabPoint (window coordinates), which may
// differ from where the pointer is now. The drag image keeps that grip.
- (void)beginDrag:(PTYSession *)session grabPointInWindow:(NSPoint)grabPoint;

// Whether dropping the dragged session on this view should place it as a floating pane rather than
// split the view. A float being dragged is placed where it is dropped unless Control is held, which
// docks it instead. A drop on a float always places, since a float is never split.
- (BOOL)dropPlacesFloatingPaneOverFloat:(BOOL)overFloat;

// Places the dragged session as a floating pane in the tab, its title bar where the pointer holds
// it. Returns whether it was placed. Either way the drag will not also make a new window.
- (BOOL)dropFloatingPaneInTab:(PTYTab *)tab atWindowPoint:(NSPoint)point;

// The drag moved. While Control is held, floats are hidden so they do not cover the panes the
// dragged session could dock into.
- (void)dragDidMove;
- (BOOL)isMovingSession:(PTYSession *)s;
- (BOOL)dropInSession:(PTYSession *)dest
                 half:(SplitSessionHalf)half
              atPoint:(NSPoint)point;
- (BOOL)dropTab:(PTYTab *)tab
      inSession:(PTYSession *)dest
           half:(SplitSessionHalf)half
        atPoint:(NSPoint)point;

// Clears the session so that the normal drop handler (e.g., -[SessionView draggedImage:endedAt:operation:])
// doesn't do anything.
- (void)clearSession;

// Returns an autoreleased session view. Add the session view to something useful and release it.
- (SessionView *)removeAndClearSession;
- (void)moveSessionToNewWindow:(PTYSession *)movingSession
                       atPoint:(NSPoint)point;
- (void)moveSessionToTab:(PTYSession *)movingSession;

// Move the window by |distance|.
- (void)moveWindowBy:(NSPoint)distance;

+ (void)moveTab:(PTYTab *)tab toWindow:(PseudoTerminal *)window atIndex:(NSInteger)index;

@end
