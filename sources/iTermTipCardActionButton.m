//
//  iTermWelcomeCardActionButton.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermTipCardActionButton.h"
#import "iTermTipCardActionButtonCell.h"

static const CGFloat kStandardButtonHeight = 34;

@implementation iTermTipCardActionButton {
    CGFloat _desiredHeight;
    NSSize _inset;
    NSTimeInterval _highlightStartTime;
    BOOL _isHighlighted;
    CALayer *_iconLayer;  // weak
}

+ (NSColor *)blueColor {
    return [NSColor colorWithCalibratedRed:0.25 green:0.25 blue:0.75 alpha:1];
}

- (id)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _desiredHeight = 34;
        _inset = NSMakeSize(10, 5);
        self.wantsLayer = YES;
    }
    return self;
}

- (void)dealloc {
    [_block release];
    [_title release];
    [_icon release];
    [super dealloc];
}

- (void)setTitle:(NSString *)title {
    [_title autorelease];
    _title = [title copy];
    [self setNeedsDisplay:YES];
}

- (void)setIcon:(NSImage *)image {
    if (!_iconLayer) {
        _iconLayer = [[[CALayer alloc] init] autorelease];
        _iconLayer.position = CGPointMake(22, 17);
        [self.layer addSublayer:_iconLayer];
    }

    [_icon autorelease];
    _icon = [image retain];
    _iconLayer.bounds = CGRectMake(0, 0, image.size.width, image.size.height);
    _iconLayer.contents = (id)[image CGImageForProposedRect:NULL
                                                    context:nil
                                                      hints:nil];
    [self setNeedsDisplay:YES];
}

- (void)setIconFlipped:(BOOL)isFlipped {
    _iconLayer.transform = CATransform3DMakeRotation(isFlipped ? M_PI : 0, 0, 0, 1);
}

- (NSSize)sizeThatFits:(NSSize)size {
    return NSMakeSize(size.width, _desiredHeight);
}

- (void)sizeToFit {
    NSRect rect = self.frame;
    rect.size.height = _desiredHeight;
    self.frame = rect;
}

- (void)setCollapsed:(BOOL)collapsed {
    _desiredHeight = collapsed ? 0 : kStandardButtonHeight;
    _collapsed = collapsed;
    if (!collapsed) {
        self.hidden = NO;
    }
}

- (void)mouseDown:(NSEvent *)theEvent {
    _isHighlighted = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)theEvent {
    _isHighlighted = NO;
    [self setNeedsDisplay:YES];
    if (NSPointInRect([self convertPoint:theEvent.locationInWindow fromView:nil], self.bounds)) {
        if (self.target && self.action) {
            [self.target performSelector:self.action withObject:self];
        }
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    static const NSTimeInterval kHoldDuration = 0.25;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (_isHighlighted) {
        _highlightStartTime = now;
        [self performSelector:@selector(setNeedsDisplay:) withObject:@1 afterDelay:kHoldDuration];
    }
    BOOL highlighted = _isHighlighted || (now - _highlightStartTime < kHoldDuration);
    NSColor *foregroundColor = highlighted ? [NSColor whiteColor] : [self.class blueColor];
    NSColor *backgroundColor = highlighted ? [self.class blueColor] : [NSColor whiteColor];
    [backgroundColor set];
    NSRectFill(self.bounds);

    [[NSColor colorWithCalibratedWhite:0.85 alpha:1] set];
    NSRectFill(NSMakeRect(NSMinX(self.bounds), 0, NSWidth(self.bounds), 0.5));

    NSColor *textColor = foregroundColor;
    NSFont *font = [NSFont fontWithName:@"Helvetica Neue" size:14];
    NSRect textRect = self.bounds;
    textRect.origin.x += _inset.width + _icon.size.width + 11;
    textRect.origin.y += _inset.height;
    [self.title drawInRect:textRect withAttributes:@{ NSFontAttributeName: font,
                                                      NSForegroundColorAttributeName: textColor }];
}

- (BOOL)isFlipped {
    return YES;
}

@end
