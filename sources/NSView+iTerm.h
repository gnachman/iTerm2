//
//  NSView+iTerm.h
//  iTerm
//
//  Created by George Nachman on 3/15/14.
//
//

#import <Cocoa/Cocoa.h>
#import "NSObject+iTerm.h"

@interface NSView (iTerm)

// Returns an image representation of the view's current appearance.
- (NSImage *)snapshot;
- (void)insertSubview:(NSView *)subview atIndex:(NSInteger)index;
- (void)swapSubview:(NSView *)subview1 withSubview:(NSView *)subview2;

// Schedules a cancelable animation. It is only cancelable during |delay|.
// See NSObject+iTerm.h for how cancellation of delayed performs works. The
// completion block is always run; the finished argument is set to NO if it was
// canceled and the animations block was not run. Unlike iOS, there is no magic
// in the animations block; you're expected to do "view.animator.foo = whatever".
//
// Remember to retain self until completion finishes if your animations or completions block
// use self.
+ (iTermDelayedPerform *)animateWithDuration:(NSTimeInterval)duration
                                       delay:(NSTimeInterval)delay
                                  animations:(void (^)(void))animations
                                  completion:(void (^)(BOOL finished))completion;

// A non-cancelable version of animateWithDuration:delay:animations:completion:.
// Remember to retain self until completion runs if you use it.
+ (void)animateWithDuration:(NSTimeInterval)duration
                 animations:(void (^)(void))animations
                 completion:(void (^)(BOOL finished))completion;

@end


//
//  UIView+Genie.h
//  BCGenieEffect
//
//  Created by Bartosz Ciechanowski on 23.12.2012.
//  Copyright (c) 2012 Bartosz Ciechanowski. All rights reserved.
//

typedef NS_ENUM(NSUInteger, BCRectEdge) {
    BCRectEdgeTop    = 0,
    BCRectEdgeLeft   = 1,
    BCRectEdgeBottom = 2,
    BCRectEdgeRight  = 3
};

@interface NSView (Genie)

/*
 * After the animation has completed the view's transform will be changed to match the destination's rect, i.e.
 * view's transform (and thus the frame) will change, however the bounds and center will *not* change.
 */

- (void)genieInTransitionWithDuration:(NSTimeInterval)duration
                      destinationRect:(CGRect)destRect
                      destinationEdge:(BCRectEdge)destEdge
                           completion:(void (^)())completion;



/*
 * After the animation has completed the view's transform will be changed to CGAffineTransformIdentity.
 */

- (void)genieOutTransitionWithDuration:(NSTimeInterval)duration
                             startRect:(CGRect)startRect
                             startEdge:(BCRectEdge)startEdge
                            completion:(void (^)())completion;

@end
