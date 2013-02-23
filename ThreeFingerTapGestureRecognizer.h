//
//  ThreeFingerTapGestureRecognizer.h
//  iTerm
//
//  Created by George Nachman on 1/9/13.
//
//

#import <Cocoa/Cocoa.h>

@interface ThreeFingerTapGestureRecognizer : NSObject {
    int numTouches_;
    NSTimeInterval firstTouchTime_;  // Time since ref date of transition from 0 to >0 touches
    NSTimeInterval threeTouchTime_;  // Time since ref date of transition from <3 to 3 touches
    __weak NSView *target_;
    SEL selector_;
    BOOL fired_;  // True if we just faked a three-finger click and future mouse clicks should be ignored.
}

// This is the designated initializer. On a three-finger tap, the selector will be performed on
// target. The target is not retained. The selector will take one argument, an NSEvent corresponding
// to the last touch ending.
- (id)initWithTarget:(NSView *)target selector:(SEL)selector;

// Target must call this in its dealloc method.
- (void)disconnectTarget;

// When these methods are called on the target view, it should immediately call the corresponding
// method on the recognizer.
- (void)touchesBeganWithEvent:(NSEvent *)event;
- (void)touchesEndedWithEvent:(NSEvent *)event;
- (void)touchesCancelledWithEvent:(NSEvent *)event;

// If these return YES then do not continue processing them or run [super ...].
- (BOOL)rightMouseDown:(NSEvent*)event;
- (BOOL)rightMouseUp:(NSEvent*)event;
- (BOOL)mouseDown:(NSEvent*)event;
- (BOOL)mouseUp:(NSEvent*)event;

@end
