//
//  iTermWelcomeCardActionButton.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermTipCardActionButton.h"

#import "NSBezierPath+iTerm.h"
#import "SolidColorView.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kStandardButtonHeight = 34;

@interface iTermTipCardActionButtonTopDividerView : SolidColorView
@end

@implementation iTermTipCardActionButtonTopDividerView

- (void)drawRect:(NSRect)dirtyRect {
    NSRect rect = self.bounds;
    [self.color set];
    NSRectFill(NSMakeRect(rect.origin.x,
                          rect.origin.y,
                          rect.size.width,
                          0.5));
}

@end

// Draws a left-side vertical divider one pixel wide.
@interface iTermTipCardActionButtonLeftDividerView : SolidColorView
@end

@implementation iTermTipCardActionButtonLeftDividerView

- (void)drawRect:(NSRect)dirtyRect {
    NSRect rect = self.bounds;
    [self.color set];
    NSRectFill(NSMakeRect(rect.origin.x,
                          rect.origin.y,
                          0.5,
                          rect.size.height));
}

@end

@interface iTermTipCardActionButton()
@property(nonatomic, copy) NSString *titleValue;
@property(nonatomic, copy) NSString *shortcutValue;
@end

@implementation iTermTipCardActionButton {
    CGFloat _desiredHeight;
    BOOL _isHighlighted;
    iTermTipCardActionButtonLeftDividerView *_leftDivider;  // weak
    CALayer *_iconLayer;  // weak
    CAShapeLayer *_highlightLayer;  // weak
    NSTextField *_textField;  // weak
}

+ (NSColor *)blueColor {
    return [NSColor colorWithCalibratedRed:0.25 green:0.25 blue:0.75 alpha:1];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _desiredHeight = kStandardButtonHeight;
        self.wantsLayer = YES;
        [self makeBackingLayer];
        self.layer.backgroundColor = [[NSColor whiteColor] CGColor];
        iTermTipCardActionButtonTopDividerView *divider =
            [[[iTermTipCardActionButtonTopDividerView alloc] initWithFrame:NSMakeRect(0, 0, frameRect.size.width, 1)] autorelease];
        divider.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
        divider.color = [NSColor colorWithCalibratedWhite:0.85 alpha:1];
        [self addSubview:divider];

        _leftDivider = [[[iTermTipCardActionButtonLeftDividerView alloc] initWithFrame:NSMakeRect(0, 0, 1, frameRect.size.height)] autorelease];
        _leftDivider.autoresizingMask = NSViewHeightSizable | NSViewMaxXMargin;
        _leftDivider.color = [NSColor colorWithCalibratedWhite:0.85 alpha:1];
        _leftDivider.hidden = YES;
        [self addSubview:_leftDivider];

        _highlightLayer = [[[CAShapeLayer alloc] init] autorelease];
        NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0, 0, 1, 1)];
        _highlightLayer.path = path.iterm_CGPath;
        _highlightLayer.anchorPoint = CGPointMake(0.5, 0.5);
        _highlightLayer.fillColor = [[NSColor colorWithCalibratedWhite:0.90 alpha:1] CGColor];
        [self.layer addSublayer:_highlightLayer];

        _textField = [[[NSTextField alloc] initWithFrame:NSMakeRect(42, 5, 200, 17)] autorelease];
        [_textField setBezeled:NO];
        [_textField setDrawsBackground:NO];
        [_textField setEditable:NO];
        [_textField setSelectable:NO];
        _textField.font = [NSFont fontWithName:@"Helvetica Neue" size:14];
        _textField.textColor = [self.class blueColor];
        [self addSubview:_textField];
    }
    return self;
}

- (void)dealloc {
    [_block release];
    [_icon release];
    [_titleValue release];
    [_shortcutValue release];
    [super dealloc];
}

- (void)setImportant:(BOOL)important {
    _important = important;
    if (important) {
        _textField.textColor = [NSColor whiteColor];
        self.layer.backgroundColor = [[NSColor redColor] CGColor];
    } else {
        _textField.textColor = [[self class] blueColor];
        self.layer.backgroundColor = [[NSColor whiteColor] CGColor];
    }
}

- (void)setIndexInRow:(int)indexInRow {
    _indexInRow = indexInRow;
    _leftDivider.hidden = (indexInRow == 0);
}

- (void)setTitle:(NSString *)title {
    self.titleValue = title;
    [self updateTitle];
}

- (void)updateTitle {
    CGFloat width = NSWidth(self.bounds) - NSMinX(_textField.frame);
    NSMutableParagraphStyle *paragraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
    paragraphStyle.alignment = NSLeftTextAlignment;

    // For inscrutable reasons, putting the tab stop all the way at the right edge of the field
    // doesn't work--the tab seems to be ignored.
    NSTextTab *tab = [[[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentRight
                                                      location:width - 8
                                                       options:@{ }] autorelease];
    paragraphStyle.tabStops = @[ tab ];
    NSString *string = [NSString stringWithFormat:@"%@\t%@",
                                                  self.titleValue ?: @"",
                                                  self.shortcutValue ?: @""];
    NSDictionary *attributes = @{ NSParagraphStyleAttributeName: paragraphStyle };
    NSAttributedString *attributedString =
        [[[NSAttributedString alloc] initWithString:string attributes:attributes] autorelease];
    _textField.attributedStringValue = attributedString;
    [_textField sizeToFit];
    NSRect rect = _textField.frame;
    rect.size.width = width;
    _textField.frame = rect;
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self updateTitle];
}

- (void)setShortcut:(NSString *)shortcut {
    self.shortcutValue = shortcut;
    [self updateTitle];
}

- (NSString *)title {
    return self.titleValue;
}

- (NSString *)shortcut {
    return self.shortcutValue;
}

// This assumes the icon is 22x22
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

// Keep the highlight circle centered on the cursor during a drag, up to our bounds.
- (void)mouseDragged:(NSEvent *)theEvent {
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    CGPoint position = (CGPoint)[self convertPoint:theEvent.locationInWindow fromView:nil];
    NSRect bounds = self.bounds;
    position.x = MAX(MIN(NSMaxX(bounds), position.x), 0);
    position.y = MAX(MIN(NSMaxY(bounds), position.y), 0);
    _highlightLayer.position = position;
    [CATransaction commit];
}

- (void)mouseDown:(NSEvent *)theEvent {
    if (!self.enabled) {
        return;
    }
    _isHighlighted = YES;

    // Reset to a known state.
    [_highlightLayer removeAllAnimations];
    [CATransaction begin];
    // This magic causes layer changes to happen immediately & synchronously.
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    _highlightLayer.position = (CGPoint)[self convertPoint:theEvent.locationInWindow fromView:nil];
    _highlightLayer.opacity = 1.0;
    _highlightLayer.transform = CATransform3DIdentity;
    [CATransaction commit];

    // Scale up the highlight circle until it fills the button.
    [CATransaction begin];
    [CATransaction setAnimationDuration:1];

    CGFloat scale = [self desiredHighlightScale];
    CATransform3D transform = CATransform3DConcat(CATransform3DMakeTranslation(-0.5, -0.5, 0),
                                                  CATransform3DMakeScale(scale, scale, 1));

    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"transform"];
    animation.fromValue = (id)[NSValue valueWithCATransform3D:CATransform3DIdentity];
    animation.toValue = (id)[NSValue valueWithCATransform3D:transform];
    animation.duration = 0.3;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    animation.removedOnCompletion = NO;
    animation.fillMode = kCAFillModeForwards;
    [_highlightLayer addAnimation:animation forKey:@"transform"];
    [CATransaction commit];
}

// Radius for highlight circle.
- (CGFloat)desiredHighlightScale {
    return sqrt(self.bounds.size.width * self.bounds.size.width +
                self.bounds.size.height + self.bounds.size.height) * 3;
}

- (void)mouseUp:(NSEvent *)theEvent {
    _isHighlighted = NO;

    // Scale up highlight while fading it out.
    [CATransaction begin];
    [CATransaction setAnimationDuration:1];
    _highlightLayer.opacity = 0;
    CGFloat scale = [self desiredHighlightScale];
    CATransform3D transform = CATransform3DConcat(CATransform3DMakeTranslation(-0.5, -0.5, 0),
                                                  CATransform3DMakeScale(scale, scale, 1));
    _highlightLayer.transform = transform;
    [CATransaction commit];

    [self setNeedsDisplay:YES];

    // Report a click if appropriate.
    if (self.enabled &&
        NSPointInRect([self convertPoint:theEvent.locationInWindow fromView:nil], self.bounds)) {
        if (self.target && self.action) {
            [self.target performSelector:self.action withObject:self];
        }
    }
}

- (BOOL)isFlipped {
    return YES;
}

@end
