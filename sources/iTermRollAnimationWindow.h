//
//  iTermRollAnimationWindow.h
//  iTerm2
//
//  Created by George Nachman on 6/25/16.
//
//

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSUInteger, iTermAnimationDirection) {
    kAnimationDirectionDown,
    kAnimationDirectionRight,
    kAnimationDirectionLeft,
    kAnimationDirectionUp
};

iTermAnimationDirection iTermAnimationDirectionOpposite(iTermAnimationDirection direction);

// Takes a snapshot of a window. Typically the window would be on an edge of
// the display. Uses core animation to animate the snapshot sliding in. Gets a
// much better frame rate than using NSWindow animations.
@interface iTermRollAnimationWindow : NSPanel

+ (instancetype)rollAnimationWindowForWindow:(NSWindow *)window;

- (void)animateInWithDirection:(iTermAnimationDirection)direction
                      duration:(NSTimeInterval)duration
                    completion:(void(^)())completion;

- (void)animateOutWithDirection:(iTermAnimationDirection)direction
                       duration:(NSTimeInterval)duration
                     completion:(void(^)())completion;

@end
