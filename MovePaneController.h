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
- (void)movePane:(PTYSession *)session;
- (void)exitMovePaneMode;
- (void)didSelectDestinationSession:(PTYSession *)dest
                               half:(SplitSessionHalf)half;

@end
