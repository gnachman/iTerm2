//
//  ThreeFingerTapGestureRecognizer.h
//  iTerm
//
//  Created by George Nachman on 1/9/13.
//
//

#import <Cocoa/Cocoa.h>

@interface ThreeFingerTapGestureRecognizer : NSObject

// This is the designated initializer. On a three-finger tap, the selector will be performed on
// target. The target is not retained. The selector will take one argument, an NSEvent corresponding
// to the last touch ending.
- (instancetype)initWithTarget:(NSView *)target selector:(SEL)selector;

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
