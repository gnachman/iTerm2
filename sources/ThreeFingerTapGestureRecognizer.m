//
//  ThreeFingerTapGestureRecognizer.m
//  iTerm
//
//  Created by George Nachman on 1/9/13.
//
//

#import "ThreeFingerTapGestureRecognizer.h"
#import "FutureMethods.h"
#import "iTermApplicationDelegate.h"

@implementation ThreeFingerTapGestureRecognizer {
    int numTouches_;
    NSTimeInterval firstTouchTime_;  // Time since ref date of transition from 0 to >0 touches
    NSTimeInterval threeTouchTime_;  // Time since ref date of transition from <3 to 3 touches
    __weak NSView *target_;
    SEL selector_;
    BOOL fired_;  // True if we just faked a three-finger click and future mouse clicks should be ignored.
}

- (instancetype)initWithTarget:(NSView *)target selector:(SEL)selector {
    self = [super init];
    if (self) {
        target_ = target;
        selector_ = selector;
    }
    return self;
}

- (void)cancel {
    firstTouchTime_ = 0;
}

- (void)touchesBeganWithEvent:(NSEvent *)ev
{
    fired_ = NO;
    DLog(@"fired->NO");
    int touches = [[ev touchesMatchingPhase:NSTouchPhaseBegan | NSTouchPhaseStationary
                                     inView:target_] count];
    if (numTouches_ == 0 && touches > 0) {
        DLog(@"Set first touch time");
        firstTouchTime_ = [NSDate timeIntervalSinceReferenceDate];
    }
    if (numTouches_ < 3 && touches == 3) {
        DLog(@"Set three touch time");
        threeTouchTime_ = [NSDate timeIntervalSinceReferenceDate];
    }
    if (numTouches_ > 3) {
        DLog(@"Too many touches!");
        // Not possible to be a three finger tap if more than three fingers were down at any point.
        [self cancel];
    }
    if (firstTouchTime_ && threeTouchTime_ && touches < 3) {
        DLog(@"Touch count not concave");
        // Number of touches went down and then up: can't be a three finger tap.
        [self cancel];
    }
   numTouches_ = touches;
}

- (void)touchesEndedWithEvent:(NSEvent *)ev
{
    numTouches_ = [[ev touchesMatchingPhase:NSTouchPhaseStationary
                                           inView:target_] count];
    const NSTimeInterval maxTimeForSimulatedThreeFingerTap = 1;
    if (numTouches_ == 0 &&
        firstTouchTime_ &&
        threeTouchTime_ &&
        [NSDate timeIntervalSinceReferenceDate] - firstTouchTime_ < maxTimeForSimulatedThreeFingerTap) {
        DLog(@"Fake a three finger click");
        [target_ performSelector:selector_ withObject:ev];
        DLog(@"fired->YES");
        fired_ = YES;
    }
    if (numTouches_ == 0) {
        DLog(@"Reset first/three times");
        firstTouchTime_ = 0;
        threeTouchTime_ = 0;
    }
    DLog(@"%@ End touch. numTouches_ -> %d (first=%d, three=%d, dt=%d)", self, numTouches_, (int)firstTouchTime_, (int)threeTouchTime_, (int)([NSDate timeIntervalSinceReferenceDate] - firstTouchTime_));
}

- (void)touchesCancelledWithEvent:(NSEvent *)event {
    DLog(@"%@ canceled", self);
    numTouches_ = 0;
    firstTouchTime_ = 0;
    threeTouchTime_ = 0;
}

- (BOOL)getAndResetFired {
    // This is called for [right]mouseUp events. It returns and resets the value of fired_ so it doesn't get stuck.
    BOOL value = fired_;
    DLog(@"get and reset fired. fired->NO");
    fired_ = NO;
    return value;
}

- (BOOL)rightMouseDown:(NSEvent*)event
{
    DLog(@"Right mouse down");
    [self cancel];
    return fired_;
}

- (BOOL)rightMouseUp:(NSEvent*)event
{
    DLog(@"right mouse up");
    [self cancel];
    return [self getAndResetFired];
}

- (BOOL)mouseDown:(NSEvent*)event
{
    DLog(@"mouse down");
    [self cancel];
    return fired_;
}

- (BOOL)mouseUp:(NSEvent*)event
{
    DLog(@"mouse up");
    [self cancel];
    return [self getAndResetFired];
}

- (void)disconnectTarget
{
    target_ = nil;
}

@end
