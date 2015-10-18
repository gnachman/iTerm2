#import "CPKHSBGradientView.h"
#import "NSColor+CPK.h"
#import "NSObject+CPK.h"

@interface CPKHSBGradientView()
@property(nonatomic, copy) void (^block)(NSColor *);
@property(nonatomic) NSImageView *indicatorView;
@property(nonatomic) CGFloat selectedBrightness;
@property(nonatomic) CGFloat selectedSaturation;
@end

@implementation CPKHSBGradientView

- (instancetype)initWithFrame:(NSRect)frameRect block:(void (^)(NSColor *))block {
    self = [super initWithFrame:frameRect];
    if (self) {
        _block = [block copy];
        self.indicatorView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        self.indicatorView.image = [self cpk_imageNamed:@"SelectedColorIndicator"];
        self.indicatorView.frame = self.indicatorFrame;
        [self addSubview:self.indicatorView];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect rect = NSMakeRect(0.5,
                             0.5,
                             self.bounds.size.width - 1,
                             NSHeight(self.bounds) - 1);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:2 yRadius:2];
    
    [NSGraphicsContext saveGraphicsState];
    [path addClip];

    for (NSInteger i = 0; i < self.bounds.size.height; i++) {
        CGFloat progress = i / self.bounds.size.height;
        NSGradient *gradient =
        [[NSGradient alloc] initWithStartingColor:[self startingColorAt:progress]
                                      endingColor:[self endingColorAt:progress]];
        [gradient drawInRect:NSMakeRect(0, i, self.bounds.size.width, 1) angle:0];
    }
    [NSGraphicsContext restoreGraphicsState];

    [[NSColor lightGrayColor] set];
    [path stroke];
}

- (NSRect)indicatorFrame {
    CGFloat halfX = self.indicatorView.image.size.width / 2;
    CGFloat halfY = self.indicatorView.image.size.height / 2;
    NSRect frame =
        NSMakeRect(self.selectedSaturation * NSWidth(self.bounds) - halfX,
                   MAX(1 - halfY,
                       self.selectedBrightness * NSHeight(self.bounds) - halfY),
                   self.indicatorView.image.size.width,
                   self.indicatorView.image.size.height);
    frame.origin.x = MIN(MAX(frame.origin.x, 0), NSMaxX(self.bounds) - NSWidth(frame));
    frame.origin.y = MIN(MAX(frame.origin.y, 0), NSMaxY(self.bounds) - NSHeight(frame));
    return frame;
}

- (NSColor *)startingColorAt:(CGFloat)fraction {
    return [NSColor cpk_colorWithHue:self.hue
                          saturation:0
                          brightness:fraction
                               alpha:1];
}

- (NSColor *)endingColorAt:(CGFloat)fraction {
    return [NSColor cpk_colorWithHue:self.hue
                          saturation:1
                          brightness:fraction
                               alpha:1];
}

- (CGFloat)saturationAtPoint:(NSPoint)point {
    NSSize size = self.bounds.size;
    return MAX(MIN(1, point.x / size.width), 0);;
}

- (CGFloat)brightnessAtPoint:(NSPoint)point {
    NSSize size = self.bounds.size;
    return MAX(MIN(1, point.y / size.height), 0);
}

- (void)mouseDown:(NSEvent *)theEvent {
    [self setColorFromPointInWindow:theEvent.locationInWindow];
}

- (void)mouseDragged:(NSEvent *)theEvent {
    [self setColorFromPointInWindow:theEvent.locationInWindow];
}

- (void)setColorFromPointInWindow:(NSPoint)point {
    NSPoint pointInView = [self convertPoint:point fromView:nil];
    self.selectedSaturation = [self saturationAtPoint:pointInView];
    self.selectedBrightness = [self brightnessAtPoint:pointInView];
    self.indicatorView.frame = self.indicatorFrame;
    self.block(self.selectedColor);
}

- (void)setSelectedColor:(NSColor *)selectedColor {
    self.selectedSaturation = selectedColor.saturationComponent;
    self.selectedBrightness = selectedColor.brightnessComponent;
    self.hue = selectedColor.hueComponent;
    self.indicatorView.frame = self.indicatorFrame;
}

- (NSColor *)selectedColor {
    return [NSColor cpk_colorWithHue:self.hue
                          saturation:self.selectedSaturation
                          brightness:self.selectedBrightness
                               alpha:1];
}

- (BOOL)isFlipped {
    return YES;
}

@end
