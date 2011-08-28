//
//  MovePaneController.h
//  iTerm2
//
//  Runs the show for moving a session into a split pane.
//
//  Created by George Nachman on 8/26/11.

#import <Foundation/Foundation.h>
#import "SplitSelectionView.h"

@class PTYSession;

@interface MovePaneController : NSObject <SplitSelectionViewDelegate> {
    PTYSession *session_;  // weak
}

+ (MovePaneController *)sharedInstance;
// Iniate click-to-move mode.
- (void)movePane:(PTYSession *)session;
- (void)exitMovePaneMode;
// Initiate dragging.
- (void)beginDrag:(PTYSession *)session;
- (BOOL)isMovingSession:(PTYSession *)s;
- (BOOL)dropInSession:(PTYSession *)dest
                 half:(SplitSessionHalf)half;
@end
