#import "CPKSwatchView.h"
#import "NSObject+CPK.h"

@interface NSImage(CPK)
- (NSImage *)cpk_imageWithTintColor:(NSColor *)tintColor;
@end

@implementation CPKSwatchView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.cpk_cornerRadius = 2;
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
                                                         xRadius:self.cpk_cornerRadius
                                                         yRadius:self.cpk_cornerRadius];
    [NSGraphicsContext saveGraphicsState];
    [path addClip];

    if (self.color) {
        [[NSColor colorWithPatternImage:[self cpk_imageNamed:@"SwatchCheckerboard"]] set];
        NSRect offset = [self convertRect:self.bounds toView:nil];
        [[NSGraphicsContext currentContext] setPatternPhase:offset.origin];
        NSRectFill(rect);

        [self.color set];
        NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);
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

    if (self.showWarningIcon) {
        if (@available(macOS 11.0, *)) {
            const CGFloat diameter = 12;
            const CGFloat inset = 1;
            const NSRect imageRect = NSMakeRect(NSMaxX(self.bounds) - diameter - inset,
                                                inset,
                                                diameter,
                                                diameter);

            static NSImage *warningImage;
            static NSImage *filledImage;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                warningImage = [NSImage imageWithSystemSymbolName:@"exclamationmark.triangle"
                                         accessibilityDescription:@"Color is out-of-gamut for this color space"];

                filledImage = [[NSImage imageWithSystemSymbolName:@"exclamationmark.triangle.fill"
                                         accessibilityDescription:@"Color is out-of-gamut for this color space"] cpk_imageWithTintColor:[NSColor whiteColor]];
            });
            [filledImage drawInRect:imageRect
                           fromRect:NSZeroRect
                          operation:NSCompositingOperationSourceOver
                           fraction:1];

            [warningImage drawInRect:imageRect
                            fromRect:NSZeroRect
                           operation:NSCompositingOperationSourceOver
                            fraction:1];

        }
    }
}

- (void)setShowWarningIcon:(BOOL)showWarningIcon {
    _showWarningIcon = showWarningIcon;
    self.toolTip = showWarningIcon ? @"Color is out-of-gamut for this color space" : nil;
}

- (void)setColor:(NSColor *)color {
    _color = color;
    [self setNeedsDisplay:YES];
}

@end

@implementation NSImage(CPK)

- (NSImage *)cpk_imageWithTintColor:(NSColor *)tintColor {
    if (!tintColor) {
        return self;
    }
    NSSize size = self.size;
    NSImage *image = [self copy];
    image.template = NO;

    [image lockFocus];

    [tintColor set];
    NSRectFillUsingOperation(NSMakeRect(0, 0, size.width, size.height),
                             NSCompositingOperationSourceAtop);
    [image unlockFocus];

    return image;

}

@end

