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
    BOOL _mouseInside;
}

- (void)setSlideOffset:(CGFloat)slideOffset {
    _slideOffset = slideOffset;
    [self setBoundsOrigin:NSMakePoint(slideOffset, 0)];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
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
    // Created only once. It tracks the visible rect, so it follows changes to
    // the frame without being replaced and ignores the bounds origin, which
    // slideOffset changes. Replacing it while the mouse is inside (as happens
    // on every frame of a slide) would send a spurious mouseEntered:.
    if (_trackingArea != nil) {
        return;
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                 options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingCursorUpdate | NSTrackingInVisibleRect)
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

// AppKit doesn't send mouseExited: when the view is hidden or leaves the window
// with the mouse inside it, so forget the mouse then. Otherwise the next
// mouseEntered: would be ignored as a duplicate.
- (void)viewDidHide {
    [super viewDidHide];
    [self forgetMouse];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
    [super viewWillMoveToWindow:newWindow];
    [self forgetMouse];
}

- (void)forgetMouse {
    _mouseInside = NO;
    _revealed = NO;
}

- (void)cursorUpdate:(NSEvent *)event {
    if (_revealed) {
        [[NSCursor arrowCursor] set];
    }
}

- (void)mouseEntered:(NSEvent *)event {
    [super mouseEntered:event];
    if (_mouseInside) {
        return;
    }
    _mouseInside = YES;
    if ([NSEvent pressedMouseButtons]) {
        return;
    }
    _revealed = [self.delegate stoplightHotboxMouseEnter];
}

- (void)mouseExited:(NSEvent *)event {
    [super mouseExited:event];
    if (!_mouseInside) {
        return;
    }
    _mouseInside = NO;
    _revealed = NO;
    [self.delegate stoplightHotboxMouseExit];
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (NSRect)_opaqueRectForWindowMoveWhenInTitlebar {
    return self.bounds;
}

- (NSView *)hitTest:(NSPoint)point {
    if (_revealed) {
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
    [self.window performWindowDragWithEvent:event];
}

@end
