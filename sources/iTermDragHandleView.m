//
//  iTermDragHandleView.m
//  iTerm
//
//  Created by George Nachman on 7/20/14.
//
//

#import "iTermDragHandleView.h"

@implementation iTermDragHandleView {
    CGFloat _origin;
}

- (void)resetCursorRects {
    NSRect bounds = self.bounds;
    [self addCursorRect:NSMakeRect(0, 0, bounds.size.width, bounds.size.height)
                 cursor:[NSCursor resizeLeftRightCursor]];
}

- (void)mouseDown:(NSEvent *)theEvent {
    const NSUInteger mask = (NSLeftMouseDownMask |
                             NSLeftMouseUpMask |
                             NSLeftMouseDraggedMask |
                             NSMouseMovedMask);
    BOOL done = NO;
    _origin = [theEvent locationInWindow].x;
    while (!done) {
        NSEvent *event = [NSApp nextEventMatchingMask:mask
                                            untilDate:[NSDate distantFuture]
                                               inMode:NSEventTrackingRunLoopMode
                                              dequeue:YES];

        switch ([event type]) {
            case NSLeftMouseDragged:
                [self mouseDragged:event];
                break;

            case NSLeftMouseUp:
                done = YES;
                break;

            default:
                break;
        }
    }
    
    if ([_delegate respondsToSelector:@selector(dragHandleViewDidFinishMoving:)]) {
        [_delegate dragHandleViewDidFinishMoving:self];
    }
}

- (void)mouseDragged:(NSEvent *)theEvent {
    NSPoint locationInWindow = [theEvent locationInWindow];
    CGFloat diff = locationInWindow.x - _origin;
    CGFloat actualDiff = [_delegate dragHandleView:self didMoveBy:diff];
    _origin += actualDiff;
}

@end
