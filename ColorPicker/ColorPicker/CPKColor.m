//
//  CPKColor.m
//  ColorPicker
//
//  Created by George Nachman on 10/3/19.
//  Copyright © 2019 Google. All rights reserved.
//

#import "CPKColor.h"
#import "NSColor+CPK.h"

@implementation CPKColor

- (instancetype)initWithColor:(NSColor *)color {
    self = [super init];
    if (self) {
        _color = color;
        _hueComponent = color.hueComponent;
        _saturationComponent = color.saturationComponent;
    }
    return self;
}

- (instancetype)initWithHue:(CGFloat)hue
                 saturation:(CGFloat)saturation
                 brightness:(CGFloat)brightness
                      alpha:(CGFloat)alpha {
    self = [self initWithColor:[NSColor cpk_colorWithHue:hue
                                              saturation:saturation
                                              brightness:brightness
                                                   alpha:alpha]];
    if (self) {
        _hueComponent = hue;
        _saturationComponent = saturation;
    }
    return self;
}

- (instancetype)initWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha colorSpace:(NSColorSpace *)colorSpace {
    return [self initWithColor:[NSColor cpk_colorWithRed:red green:green blue:blue alpha:alpha colorSpace:colorSpace]];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p color=%@ hue=%@ sat=%@>",
            NSStringFromClass([self class]),
            self,
            _color, @(_hueComponent), @(_saturationComponent)];
}

- (CGFloat)brightnessComponent {
    return _color.brightnessComponent;
}

- (CGFloat)redComponent {
    return _color.redComponent;
}

- (CGFloat)greenComponent {
    return _color.greenComponent;
}

- (CGFloat)blueComponent {
    return _color.blueComponent;
}

- (CGFloat)alphaComponent {
    return _color.alphaComponent;
}

- (CPKColor *)colorWithAlphaComponent:(CGFloat)alpha {
    CPKColor *other = [[CPKColor alloc] initWithColor:[self.color colorWithAlphaComponent:alpha]];
    other->_hueComponent = _hueComponent;
    other->_saturationComponent = _saturationComponent;
    return other;
}

@end
