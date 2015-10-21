#import "CPKColorComponentSliderView.h"
#import "NSColor+CPK.h"
#import "NSObject+CPK.h"

@interface CPKColorComponentSliderView ()
@property(nonatomic) NSGradient *gradient;
@end

@implementation CPKColorComponentSliderView

+ (CGFloat)valueForColor:(NSColor *)color type:(CPKColorComponentSliderType)type {
    switch (type) {
        case kCPKColorComponentSliderTypeHue:
            return color.hueComponent;
        case kCPKColorComponentSliderTypeSaturation:
            return color.saturationComponent;
        case kCPKColorComponentSliderTypeBrightness:
            return color.brightnessComponent;
        case kCPKColorComponentSliderTypeRed:
            return color.redComponent;
        case kCPKColorComponentSliderTypeGreen:
            return color.greenComponent;
        case kCPKColorComponentSliderTypeBlue:
            return color.blueComponent;
    }
    return 0;
}

- (instancetype)initWithFrame:(NSRect)frame
                        color:(NSColor *)color
                         type:(CPKColorComponentSliderType)type
                        block:(void (^)(CGFloat))block {
    self = [super initWithFrame:frame
                          value:[CPKColorComponentSliderView valueForColor:color
                                                                      type:type]
                          block:block];
    if (self) {
        self.type = type;
        [self updateGradient];
    }
    return self;
}

- (void)setColor:(NSColor *)color {
    self.selectedValue = [CPKColorComponentSliderView valueForColor:color type:self.type];
    [self setGradientColor:color];
}

- (void)setGradientColor:(NSColor *)color {
    _color = color;
    [self updateGradient];
    [self setNeedsDisplay:YES];
}

- (void)setType:(CPKColorComponentSliderType)type {
    _type = type;
    [self updateGradient];
    [self setNeedsDisplay:YES];
}

- (void)updateGradient {
    NSMutableArray *colors = [NSMutableArray array];
    int parts = 20;
    for (int i = 0; i <= parts; i++) {
        switch (self.type) {
            case kCPKColorComponentSliderTypeHue:
                [colors addObject:[NSColor cpk_colorWithHue:(double)i / (double)parts
                                                 saturation:self.color.saturationComponent
                                                 brightness:self.color.brightnessComponent
                                                      alpha:1]];
                break;
            case kCPKColorComponentSliderTypeSaturation:
                [colors addObject:[NSColor cpk_colorWithHue:self.color.hueComponent
                                                 saturation:(double)i / (double)parts
                                                 brightness:self.color.brightnessComponent
                                                      alpha:1]];
                break;
            case kCPKColorComponentSliderTypeBrightness:
                [colors addObject:[NSColor cpk_colorWithHue:self.color.hueComponent
                                                 saturation:self.color.saturationComponent
                                                 brightness:(double)i / (double)parts
                                                      alpha:1]];
                break;
            case kCPKColorComponentSliderTypeRed:
                [colors addObject:[NSColor cpk_colorWithRed:(double)i / (double)parts
                                                      green:self.color.greenComponent
                                                       blue:self.color.blueComponent
                                                      alpha:1]];
                break;
            case kCPKColorComponentSliderTypeGreen:
                [colors addObject:[NSColor cpk_colorWithRed:self.color.redComponent
                                                      green:(double)i / (double)parts
                                                       blue:self.color.blueComponent
                                                      alpha:1]];
                break;
            case kCPKColorComponentSliderTypeBlue:
                [colors addObject:[NSColor cpk_colorWithRed:self.color.redComponent
                                                      green:self.color.greenComponent
                                                       blue:(double)i / (double)parts
                                                      alpha:1]];
                break;
        }
    }
    self.gradient = [[NSGradient alloc] initWithColors:colors];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSBezierPath *path = [self boundingPath];
    [self.gradient drawInBezierPath:path angle:0];

    [[NSColor lightGrayColor] set];
    [path stroke];
}

@end
