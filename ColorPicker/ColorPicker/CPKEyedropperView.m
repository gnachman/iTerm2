#import "CPKEyedropperView.h"
#import "NSColor+CPK.h"

@implementation CPKEyedropperView

- (void)drawRect:(NSRect)dirtyRect {
    if (!_colors) {
        return;
    }

    NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:self.bounds];
    [NSGraphicsContext saveGraphicsState];
    [path addClip];

    NSColor *dividerColor = [NSColor grayColor];
    CGFloat x = 0;
    CGFloat xStep = self.bounds.size.width / _colors.count;
    CGFloat yStep = 1;
    for (NSArray *column in _colors) {
        CGFloat y = 0;
        yStep = self.bounds.size.height / column.count;
        for (NSColor *color in column) {
            [color set];
            NSRectFill(NSMakeRect(x, y, xStep, yStep));
            y += yStep;
        }
        [dividerColor set];
        NSRectFill(NSMakeRect(x, 0, 1, self.bounds.size.height));
        x += xStep;
    }
    [dividerColor set];
    NSRectFill(NSMakeRect(self.bounds.size.width - 1, 0, 1, self.bounds.size.height));
    for (CGFloat y = 0; y < self.bounds.size.height; y += yStep) {
        NSRectFill(NSMakeRect(0, y, self.bounds.size.width, 1));
    }
    NSRectFill(NSMakeRect(0, self.bounds.size.height - 1, self.bounds.size.width, 1));
    [NSGraphicsContext restoreGraphicsState];

    [dividerColor set];
    [path stroke];

    NSArray *centerColumn = _colors[_colors.count / 2];
    NSColor *centerColor = centerColumn[centerColumn.count / 2];
    centerColor = [centerColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    NSString *description = [NSString stringWithFormat:@"#%02x%02x%02x R:%d G:%d B:%d",
                                (int)(centerColor.redComponent * 255),
                                (int)(centerColor.greenComponent * 255),
                                (int)(centerColor.blueComponent * 255),
                                (int)(centerColor.redComponent * 255),
                                (int)(centerColor.greenComponent * 255),
                                (int)(centerColor.blueComponent * 255)];

    NSDictionary *attributes =
        @{ NSForegroundColorAttributeName: [NSColor whiteColor],
           NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]] };

    NSSize size = [description sizeWithAttributes:attributes];
    NSRect frame = NSMakeRect(floor((NSWidth(self.bounds) - size.width) / 2),
                              NSMidY(self.bounds) + 20,
                              size.width,
                              size.height);

    NSRect expandedFrame = frame;

    const CGFloat xMargin = 4;
    const CGFloat yMargin = 2;
    expandedFrame.origin.x -= xMargin;
    expandedFrame.size.width += xMargin * 2;
    expandedFrame.origin.y -= yMargin;
    expandedFrame.size.height += yMargin * 2;

    path = [NSBezierPath bezierPathWithRoundedRect:expandedFrame xRadius:3 yRadius:3];
    [[NSColor cpk_colorWithWhite:0 alpha:0.8] set];
    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositeSourceOver];
    [path fill];

    [description drawInRect:frame withAttributes:attributes];
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setColors:(NSArray *)colors {
    _colors = colors;
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)theEvent {
    if (theEvent.clickCount == 1) {
        self.click();
    }
}

@end
