//
//  iTermStatusBarAutoRainbowController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/2/20.
//

#import "iTermStatusBarAutoRainbowController.h"

@implementation iTermStatusBarAutoRainbowController

typedef struct {
    CGFloat saturation;
    CGFloat brightness;
} iTermStatusBarAutoRainbowParameters;

- (instancetype)initWithStyle:(iTermStatusBarAutoRainbowStyle)style {
    self = [super init];
    if (self) {
        _style = style;
    }
    return self;
}

- (void)setStyle:(iTermStatusBarAutoRainbowStyle)style {
    _style = style;
    [self.delegate autoRainbowControllerDidInvalidateColors:self];
}

- (void)setDarkBackground:(BOOL)darkBackground {
    _darkBackground = darkBackground;
    [self.delegate autoRainbowControllerDidInvalidateColors:self];
}

- (iTermStatusBarAutoRainbowParameters)lightParameters {
    iTermStatusBarAutoRainbowParameters params = {
        .saturation = 0.3,
        .brightness = 0.9
    };
    return params;
}

- (iTermStatusBarAutoRainbowParameters)darkParameters {
    iTermStatusBarAutoRainbowParameters params = {
        .saturation = 0.5,
        .brightness = 0.5
    };
    return params;
}

- (iTermStatusBarAutoRainbowParameters)automaticParameters {
    if (self.darkBackground) {
        return [self lightParameters];
    }
    return [self darkParameters];
}

- (void)enumerateColorsWithCount:(NSInteger)count
                           block:(void (^ NS_NOESCAPE)(NSInteger i, NSColor *color))block {
    iTermStatusBarAutoRainbowParameters params;

    switch (self.style) {
        case iTermStatusBarAutoRainbowStyleDisabled:
            return;

        case iTermStatusBarAutoRainbowStyleDark:
            params = [self darkParameters];
            break;

        case iTermStatusBarAutoRainbowStyleLight:
            params = [self lightParameters];
            break;

        case iTermStatusBarAutoRainbowStyleAutomatic:
            params = [self automaticParameters];
            break;
    }
    CGFloat h = 0;
    const CGFloat stride = 0.91 / (count - 1);
    for (NSInteger i = 0; i < count; i++) {
        block(i, [NSColor colorWithHue:h
                            saturation:params.saturation
                            brightness:params.brightness
                                 alpha:1]);
        h += stride;
    }
}

@end
