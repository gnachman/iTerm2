//
//  iTermFocusFollowsMouseController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/24/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermFocusFollowsMouseFocusReceiver<NSObject>
// Allows a new split pane to become focused even though the mouse pointer is elsewhere.
// Records the mouse position. Refuses first responder as long as the mouse doesn't move.
- (void)refuseFirstResponderAtCurrentMouseLocation;
@end

@interface iTermFocusFollowsMouseController : NSObject

@end

NS_ASSUME_NONNULL_END
