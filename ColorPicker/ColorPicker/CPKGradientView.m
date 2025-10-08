#import "CPKGradientView.h"

#import "CPKColor.h"
#import "NSColor+CPK.h"
#import "NSObject+CPK.h"

@interface CPKGradientView()
@property(nonatomic, copy) void (^block)(CPKColor *);
@property(nonatomic) NSImageView *indicatorView;
@property(nonatomic) CGFloat selectedX;
@property(nonatomic) CGFloat selectedY;
@end

@implementation CPKGradientView

- (instancetype)initWithFrame:(NSRect)frameRect
                         type:(CPKGradientViewType)type
                   colorSpace:(NSColorSpace *)colorSpace
                        block:(void (^)(CPKColor *))block {
    self = [super initWithFrame:frameRect];
    if (self) {
        _colorSpace = colorSpace;
        _block = [block copy];
        self.indicatorView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        self.indicatorView.image = [self cpk_imageNamed:@"SelectedColorIndicator"];
        self.indicatorView.frame = self.indicatorFrame;
        self.type = type;
        [self addSubview:self.indicatorView];
    }
    return self;
}

- (void)setColorSpace:(NSColorSpace *)colorSpace {
    if ([_colorSpace isEqual:colorSpace]) {
        return;
    }
    _colorSpace = colorSpace;
    [self setNeedsDisplay:YES];
}

- (void)setType:(CPKGradientViewType)type {
    _type = type;
    [self setNeedsDisplay:YES];
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
        NSMakeRect(self.selectedX * NSWidth(self.bounds) - halfX,
                   MAX(1 - halfY,
                       self.selectedY * NSHeight(self.bounds) - halfY),
                   self.indicatorView.image.size.width,
                   self.indicatorView.image.size.height);
    frame.origin.x = MIN(MAX(frame.origin.x, 0), NSMaxX(self.bounds) - NSWidth(frame));
    frame.origin.y = MIN(MAX(frame.origin.y, 0), NSMaxY(self.bounds) - NSHeight(frame));
    return frame;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    self.indicatorView.frame = [self indicatorFrame];
}

- (NSColor *)startingColorAt:(CGFloat)fraction {
    switch (self.type) {
        case kCPKGradientViewTypeSaturationBrightness:
            return [NSColor colorWithColorSpace:self.colorSpace
                                            hue:self.hue
                                     saturation:0
                                     brightness:fraction
                                          alpha:1];
            break;
        case kCPKGradientViewTypeBrightnessHue:
            return [NSColor colorWithColorSpace:self.colorSpace
                                            hue:fraction
                                     saturation:self.saturation
                                     brightness:0
                                          alpha:1];
            break;
        case kCPKGradientViewTypeHueSaturation:
            return [NSColor colorWithColorSpace:self.colorSpace
                                            hue:fraction
                                     saturation:0
                                     brightness:self.brightness
                                          alpha:1];
            break;
        case kCPKGradientViewTypeRedGreen:
            return [NSColor cpk_colorWithRed:0
                                       green:fraction
                                        blue:self.blue
                                       alpha:1
                                  colorSpace:self.colorSpace];
            break;
        case kCPKGradientViewTypeGreenBlue:
            return [NSColor cpk_colorWithRed:self.red
                                       green:0
                                        blue:fraction
                                       alpha:1
                                  colorSpace:self.colorSpace];
            break;
        case kCPKGradientViewTypeBlueRed:
            return [NSColor cpk_colorWithRed:fraction
                                       green:self.green
                                        blue:0
                                       alpha:1
                                  colorSpace:self.colorSpace];
            break;
    }
    return [NSColor blackColor];
}

- (NSColor *)endingColorAt:(CGFloat)fraction {
    switch (self.type) {
        case kCPKGradientViewTypeSaturationBrightness:
            return [NSColor colorWithColorSpace:self.colorSpace
                                            hue:self.hue
                                     saturation:1
                                     brightness:fraction
                                          alpha:1];
            break;
        case kCPKGradientViewTypeBrightnessHue:
            return [NSColor colorWithColorSpace:self.colorSpace
                                            hue:fraction
                                     saturation:self.saturation
                                     brightness:1
                                          alpha:1];
            break;
        case kCPKGradientViewTypeHueSaturation:
            return [NSColor colorWithColorSpace:self.colorSpace
                                            hue:fraction
                                     saturation:1
                                     brightness:self.brightness
                                          alpha:1];
            break;
        case kCPKGradientViewTypeRedGreen:
            return [NSColor cpk_colorWithRed:1
                                       green:fraction
                                        blue:self.blue
                                       alpha:1
                                  colorSpace:self.colorSpace];
            break;
        case kCPKGradientViewTypeGreenBlue:
            return [NSColor cpk_colorWithRed:self.red
                                       green:1
                                        blue:fraction
                                       alpha:1
                                  colorSpace:self.colorSpace];
            break;
        case kCPKGradientViewTypeBlueRed:
            return [NSColor cpk_colorWithRed:fraction
                                       green:self.green
                                        blue:1
                                       alpha:1
                                  colorSpace:self.colorSpace];
            break;
    }
    return [NSColor blackColor];
}

- (CGFloat)xValueAtPoint:(NSPoint)point {
    NSSize size = self.bounds.size;
    return MAX(MIN(1, point.x / size.width), 0);;
}

- (CGFloat)yValueAtPoint:(NSPoint)point {
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
    self.selectedX = [self xValueAtPoint:pointInView];
    self.selectedY = [self yValueAtPoint:pointInView];

    self.hue = self.selectedColor.hueComponent;
    self.saturation = self.selectedColor.saturationComponent;
    self.brightness = self.selectedColor.brightnessComponent;
    self.red = self.selectedColor.redComponent;
    self.green = self.selectedColor.greenComponent;
    self.blue = self.selectedColor.blueComponent;

    self.indicatorView.frame = self.indicatorFrame;
    self.block(self.selectedColor);
}

- (void)setSelectedColor:(CPKColor *)selectedColor {
    switch (self.type) {
        case kCPKGradientViewTypeSaturationBrightness:
            self.selectedX = selectedColor.saturationComponent;
            self.selectedY = selectedColor.brightnessComponent;
            break;
        case kCPKGradientViewTypeBrightnessHue:
            self.selectedX = selectedColor.brightnessComponent;
            self.selectedY = selectedColor.hueComponent;
            break;
        case kCPKGradientViewTypeHueSaturation:
            self.selectedX = selectedColor.saturationComponent;
            self.selectedY = selectedColor.hueComponent;
            break;
        case kCPKGradientViewTypeRedGreen:
            self.selectedX = selectedColor.redComponent;
            self.selectedY = selectedColor.greenComponent;
            break;
        case kCPKGradientViewTypeGreenBlue:
            self.selectedX = selectedColor.greenComponent;
            self.selectedY = selectedColor.blueComponent;
            break;
        case kCPKGradientViewTypeBlueRed:
            self.selectedX = selectedColor.blueComponent;
            self.selectedY = selectedColor.redComponent;
            break;
    }

    self.hue = selectedColor.hueComponent;
    self.brightness = selectedColor.brightnessComponent;
    self.saturation = selectedColor.saturationComponent;
    self.red = selectedColor.redComponent;
    self.green = selectedColor.greenComponent;
    self.blue = selectedColor.blueComponent;

    self.indicatorView.frame = self.indicatorFrame;
}

- (CPKColor *)selectedColor {
    switch (self.type) {
        case kCPKGradientViewTypeSaturationBrightness:
            return [[CPKColor alloc] initWithHue:self.hue
                                      saturation:self.selectedX
                                      brightness:self.selectedY
                                           alpha:1
                                      colorSpace:self.colorSpace];
            break;
        case kCPKGradientViewTypeBrightnessHue:
            return [[CPKColor alloc] initWithHue:self.selectedY
                                      saturation:self.saturation
                                      brightness:self.selectedX
                                           alpha:1
                                      colorSpace:self.colorSpace];
            break;
        case kCPKGradientViewTypeHueSaturation:
            return [[CPKColor alloc] initWithHue:self.selectedY
                                      saturation:self.selectedX
                                      brightness:self.brightness
                                           alpha:1
                                      colorSpace:self.colorSpace];
            break;
        case kCPKGradientViewTypeRedGreen:
            return [[CPKColor alloc] initWithColor:[NSColor cpk_colorWithRed:self.selectedX
                                                                       green:self.selectedY
                                                                        blue:self.blue
                                                                       alpha:1
                                                                  colorSpace:self.colorSpace]];
            break;
        case kCPKGradientViewTypeGreenBlue:
            return [[CPKColor alloc] initWithColor:[NSColor cpk_colorWithRed:self.red
                                                                       green:self.selectedX
                                                                        blue:self.selectedY
                                                                       alpha:1
                                                                  colorSpace:self.colorSpace]];
            break;
        case kCPKGradientViewTypeBlueRed:
            return [[CPKColor alloc] initWithColor:[NSColor cpk_colorWithRed:self.selectedY
                                                                       green:self.green
                                                                        blue:self.selectedX
                                                                       alpha:1
                                                                  colorSpace:self.colorSpace]];
            break;
    }
}

- (BOOL)isFlipped {
    return YES;
}

@end
