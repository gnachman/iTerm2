//
//  iTermStoplightHotbox.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/7/18.
//

#import "iTermStoplightHotbox.h"

@implementation iTermStoplightHotbox {
    NSTrackingArea *_trackingArea;
    NSBezierPath *_fillPath;
    NSBezierPath *_strokePath;
    BOOL _inside;
}

- (void)drawRect:(NSRect)dirtyRect {
    dirtyRect = NSIntersectionRect(dirtyRect, self.bounds);
    if (!_fillPath) {
        _fillPath = [[NSBezierPath alloc] init];
        [_fillPath moveToPoint:NSMakePoint(0, 0)];
        const CGFloat maxY = self.frame.size.height;
        const CGFloat maxX = self.frame.size.width - 0.5;
        const CGFloat minY = 0.5;
        [_fillPath lineToPoint:NSMakePoint(0, maxY)];
        [_fillPath lineToPoint:NSMakePoint(maxX, maxY)];
        CGFloat radius = 4;
        [_fillPath lineToPoint:NSMakePoint(maxX, minY + radius)];
        [_fillPath curveToPoint:NSMakePoint(maxX - radius, minY)
                    controlPoint1:NSMakePoint(maxX, minY + radius / 2)
                    controlPoint2:NSMakePoint(maxX - radius / 2, minY)];
        [_fillPath lineToPoint:NSMakePoint(0, minY)];

        const CGFloat inset = 0;
        _strokePath = [[NSBezierPath alloc] init];
        [_strokePath moveToPoint:NSMakePoint(maxX - inset, maxY)];
        [_strokePath lineToPoint:NSMakePoint(maxX - inset, minY + inset + radius)];
        [_strokePath curveToPoint:NSMakePoint(maxX - inset - radius, minY + inset)
                  controlPoint1:NSMakePoint(maxX - inset, minY + inset + radius / 2)
                  controlPoint2:NSMakePoint(maxX - inset - radius / 2, minY + inset)];
        [_strokePath lineToPoint:NSMakePoint(0, minY + inset)];
    }
    [[self.delegate stoplightHotboxColor] set];
    [_fillPath fill];
    
    [[self.delegate stoplightHotboxOutlineColor] set];
    [_strokePath stroke];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingCursorUpdate)
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)cursorUpdate:(NSEvent *)event {
    if (_inside) {
        [[NSCursor arrowCursor] set];
    }
}

- (void)mouseEntered:(NSEvent *)event {
    [super mouseEntered:event];
    if ([NSEvent pressedMouseButtons]) {
        return;
    }
    _inside = [self.delegate stoplightHotboxMouseEnter];
}

- (void)mouseExited:(NSEvent *)event {
    [super mouseExited:event];
    if (_inside) {
        [self.delegate stoplightHotboxMouseExit];
        _inside = NO;
    }
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (NSRect)_opaqueRectForWindowMoveWhenInTitlebar {
    return self.bounds;
}

- (NSView *)hitTest:(NSPoint)point {
    if (_inside) {
        return [super hitTest:point];
    } else {
        return nil;
    }
}
- (void)mouseDown:(NSEvent *)event {
    NSView *superview = [self superview];
    NSPoint hitLocation = [[superview superview] convertPoint:[event locationInWindow]
                                                     fromView:nil];
    NSView *hitView = [superview hitTest:hitLocation];
    

    const BOOL handleDrag = ([self.delegate stoplightHotboxCanDrag] &&
                             hitView == self);
    if (handleDrag) {
        [self trackClickForWindowMove:event];
        return;
    }
    
    [super mouseDown:event];
}

- (void)trackClickForWindowMove:(NSEvent*)event {
    NSWindow *window = self.window;
    NSPoint origin = [window frame].origin;
    NSPoint lastPointInScreenCoords = [NSEvent mouseLocation];
    const NSEventMask eventMask = (NSEventMaskLeftMouseDown |
                                   NSEventMaskLeftMouseDragged |
                                   NSEventMaskLeftMouseUp);
    event = [NSApp nextEventMatchingMask:eventMask
                               untilDate:[NSDate distantFuture]
                                  inMode:NSEventTrackingRunLoopMode
                                 dequeue:YES];
    while (event && event.type != NSEventTypeLeftMouseUp) {
        @autoreleasepool {
            NSPoint currentPointInScreenCoords = [NSEvent mouseLocation];
            
            origin.x += currentPointInScreenCoords.x - lastPointInScreenCoords.x;
            origin.y += currentPointInScreenCoords.y - lastPointInScreenCoords.y;
            lastPointInScreenCoords = currentPointInScreenCoords;
            
            [window setFrameOrigin:origin];
            
            event = [NSApp nextEventMatchingMask:eventMask
                                       untilDate:[NSDate distantFuture]
                                          inMode:NSEventTrackingRunLoopMode
                                         dequeue:YES];
        }
    }
}

@end
