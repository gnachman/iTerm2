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

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _vertical = YES;
    }
    return self;
}

- (void)dealloc {
    [_color release];
    [super dealloc];
}

- (void)drawRect:(NSRect)dirtyRect {
    [_color set];
    NSRectFill(self.bounds);
}

- (NSCursor *)resizeCursor {
    if (_vertical) {
        return [NSCursor resizeLeftRightCursor];
    } else {
        return [NSCursor resizeUpDownCursor];
    }
}

- (void)resetCursorRects {
    NSRect bounds = self.bounds;
    [self addCursorRect:NSMakeRect(0, 0, bounds.size.width, bounds.size.height)
                 cursor:[self resizeCursor]];
}

- (void)mouseDown:(NSEvent *)theEvent {
    const NSUInteger mask = (NSLeftMouseDownMask |
                             NSLeftMouseUpMask |
                             NSLeftMouseDraggedMask |
                             NSMouseMovedMask);
    BOOL done = NO;
    if (_vertical) {
        _origin = [theEvent locationInWindow].x;
    } else {
        _origin = [theEvent locationInWindow].y;
    }
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
}

- (void)mouseDragged:(NSEvent *)theEvent {
    NSPoint locationInWindow = [theEvent locationInWindow];
    CGFloat diff;
    if (_vertical) {
        diff = locationInWindow.x - _origin;
    } else {
        diff = locationInWindow.y - _origin;
    }
    CGFloat actualDiff = [_delegate dragHandleView:self didMoveBy:diff];
    _origin += actualDiff;
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

@end
