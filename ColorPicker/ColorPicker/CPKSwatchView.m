#import "CPKSwatchView.h"
#import "NSObject+CPK.h"

@implementation CPKSwatchView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.cornerRadius = 2;
        self.borderColor = [NSColor grayColor];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect rect = self.bounds;
    rect.origin.x += 0.5;
    rect.origin.y += 0.5;
    rect.size.width -= 1;
    rect.size.height -= 1;

    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect
                                                         xRadius:self.cornerRadius
                                                         yRadius:self.cornerRadius];
    [NSGraphicsContext saveGraphicsState];
    [path addClip];

    if (self.color) {
        [[NSColor colorWithPatternImage:[self cpk_imageNamed:@"SwatchCheckerboard"]] set];
        NSRect offset = [self convertRect:self.bounds toView:nil];
        [[NSGraphicsContext currentContext] setPatternPhase:offset.origin];
        NSRectFill(rect);

        [self.color set];
        NSRectFillUsingOperation(self.bounds, NSCompositeSourceOver);
    }

    [NSGraphicsContext restoreGraphicsState];

    [self.borderColor set];
    [path stroke];

    if (!self.color) {
        path = [NSBezierPath bezierPath];
        [path moveToPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect))];
        [path lineToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
        [path stroke];
    }
}

- (void)setColor:(NSColor *)color {
    _color = color;
    [self setNeedsDisplay:YES];
}

@end
