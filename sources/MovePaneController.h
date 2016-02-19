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

@class PTYTab;
@class PTYSession;
@class SessionView;
@interface MovePaneController : NSObject <SplitSelectionViewDelegate>

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

// Move the window by |distance|.
- (void)moveWindowBy:(NSPoint)distance;

@end
