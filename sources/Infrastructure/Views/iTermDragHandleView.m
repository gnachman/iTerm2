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
                 cursor:self.isVertical ? [NSCursor resizeUpDownCursor] : [NSCursor resizeLeftRightCursor]];
}

- (void)mouseDown:(NSEvent *)theEvent {
    const NSUInteger mask = (NSEventMaskLeftMouseDown |
                             NSEventMaskLeftMouseUp |
                             NSEventMaskLeftMouseDragged |
                             NSEventMaskMouseMoved);
    BOOL done = NO;
    _origin = self.isVertical ? theEvent.locationInWindow.y : theEvent.locationInWindow.x;
    while (!done) {
        NSEvent *event = [NSApp nextEventMatchingMask:mask
                                            untilDate:[NSDate distantFuture]
                                               inMode:NSEventTrackingRunLoopMode
                                              dequeue:YES];

        switch ([event type]) {
            case NSEventTypeLeftMouseDragged:
                [self mouseDragged:event];
                break;

            case NSEventTypeLeftMouseUp:
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
    CGFloat diff = (self.isVertical ? locationInWindow.y : locationInWindow.x) - _origin;
    CGFloat actualDiff = [_delegate dragHandleView:self didMoveBy:diff];
    _origin += actualDiff;
}

@end
