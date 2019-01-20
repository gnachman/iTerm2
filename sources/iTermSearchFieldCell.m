//
//  iTermSearchFieldCell.m
//  iTerm2SharedARC
//
//  Created by GEORGE NACHMAN on 7/4/18.
//

#import "iTermSearchFieldCell.h"

#import "NSColor+iTerm.h"

static NSSize kFocusRingInset = { 2, 3 };
const CGFloat kEdgeWidth = 3;

@implementation iTermSearchFieldCell {
    CGFloat _alphaMultiplier;
    NSTimer *_timer;
    BOOL _needsAnimation;
}

- (instancetype)initTextCell:(NSString *)aString  {
    self = [super initTextCell:aString];
    if (self) {
        _alphaMultiplier = 1;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        _alphaMultiplier = 1;
    }
    return self;
}

- (void)setFraction:(CGFloat)fraction {
    if (fraction == 1.0 && _fraction < 1.0) {
        _needsAnimation = YES;
    } else if (fraction < 1.0) {
        _needsAnimation = NO;
    }
    _fraction = fraction;
    _alphaMultiplier = 1;
}

- (void)willAnimate {
    _alphaMultiplier -= 0.05;
    if (_alphaMultiplier <= 0) {
        _needsAnimation = NO;
        _alphaMultiplier = 0;
    }
}

- (void)drawFocusRingMaskWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if (controlView.frame.origin.y >= 0) {
        [super drawFocusRingMaskWithFrame:NSInsetRect(cellFrame, kFocusRingInset.width, kFocusRingInset.height)
                                   inView:controlView];
    }
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    NSRect originalFrame = cellFrame;
    BOOL focused = ([controlView respondsToSelector:@selector(currentEditor)] &&
                    [(NSControl *)controlView currentEditor]);
    [self.backgroundColor set];

    CGFloat xInset, yInset;
    if (focused) {
        xInset = 2.5;
        yInset = 1.5;
    } else {
        xInset = 0.5;
        yInset = 0.5;
    }
    cellFrame = NSInsetRect(cellFrame, xInset, yInset);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:cellFrame
                                                         xRadius:4
                                                         yRadius:4];
    [path fill];

    [self drawProgressBarInFrame:originalFrame path:path];

    if (!focused) {
        [[NSColor colorWithCalibratedWhite:0.5 alpha:1] set];
        [path setLineWidth:0.25];
        [path stroke];

        cellFrame = NSInsetRect(cellFrame, 0.25, 0.25);
        path = [NSBezierPath bezierPathWithRoundedRect:cellFrame
                                               xRadius:4
                                               yRadius:4];
        [path setLineWidth:0.25];
        [[NSColor colorWithCalibratedWhite:0.7 alpha:1] set];
        [path stroke];
    }

    [self drawInteriorWithFrame:originalFrame inView:controlView];
}

- (void)drawProgressBarInFrame:(NSRect)cellFrame path:(NSBezierPath *)fieldPath {
    if (self.fraction < 0.01) {
        return;
    }
    [[NSGraphicsContext currentContext] saveGraphicsState];
    [fieldPath addClip];

    const CGFloat maximumWidth = cellFrame.size.width - 1.0;
    NSRect blueRect = NSMakeRect(0, 0, maximumWidth * [self fraction] + kEdgeWidth, cellFrame.size.height);

    const CGFloat alpha = 0.3 * _alphaMultiplier;
    [[NSColor colorWithCalibratedRed:0.6
                               green:0.6
                               blue:1.0
                               alpha:alpha] set];
    NSRectFillUsingOperation(blueRect, NSCompositingOperationSourceOver);

    [[NSGraphicsContext currentContext] restoreGraphicsState];
}

@end
