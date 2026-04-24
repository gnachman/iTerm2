//
//  iTermColorSuggester.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/30/20.
//

#import "iTermColorSuggester.h"
#import "NSColor+iTerm.h"

typedef struct {
    CGFloat l;
    CGFloat theta;
} LightnessAndAngle;

static LightnessAndAngle RandomLightnessAndAngle(void) {
    LightnessAndAngle laa;
    laa.l = drand48() * 100.0;
    if (laa.l < 50) {
        laa.l /= 2.0;
    } else {
        laa.l = 100 - (laa.l - 50) / 2.0;
    }
    laa.theta = drand48() * M_PI * 2;
    return laa;
}

static iTermLABColor ClampedLAB(iTermLABColor lab) {
    // Round trip through rgb to keep it in gamut.
    return iTermLABFromSRGB(iTermSRGBFromLAB(lab));
}

static iTermLABColor TextLAB(LightnessAndAngle laa) {
    iTermLABColor lab;
    lab.l = laa.l;
    lab.a = sin(laa.theta) * 100.0;
    lab.b = cos(laa.theta) * 100.0;
    return ClampedLAB(lab);
}

static iTermLABColor BackgroundLAB(LightnessAndAngle laa) {
    const iTermLABColor lab = {
        .l = 100.0 - laa.l,
        .a = sin(laa.theta + M_PI_2) * 100.0,
        .b = cos(laa.theta + M_PI_2) * 100.0
    };
    return ClampedLAB(lab);
}

@implementation iTermColorSuggester

- (instancetype)initWithDefaultTextColor:(NSColor *)defaultTextColor
                  defaultBackgroundColor:(NSColor *)defaultBackgroundColor
                       minimumDifference:(CGFloat)minimumDifference
                                    seed:(long)seed {
    self = [super init];
    if (self) {
        const iTermLABColor defaultBackgroundLAB = [defaultBackgroundColor labColor];

        srand48(seed);
        iTermLABColor textLAB;
        iTermLABColor backgroundLAB;
        do {
            const LightnessAndAngle laa = RandomLightnessAndAngle();
            textLAB = TextLAB(laa);
            backgroundLAB = BackgroundLAB(laa);
        } while (fabs(backgroundLAB.l / 100.0 - defaultBackgroundLAB.l / 100.0) < minimumDifference);
        _suggestedTextColor = [NSColor withLABColor:textLAB];
        _suggestedBackgroundColor = [NSColor withLABColor:backgroundLAB];
    }
    return self;
}

@end
