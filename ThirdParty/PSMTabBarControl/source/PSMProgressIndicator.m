//
//  PSMProgressIndicator.m
//  PSMTabBarControl
//
//  Created by John Pannell on 2/23/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import "PSMProgressIndicator.h"
#import <QuartzCore/QuartzCore.h>

@protocol PSMMinimalProgressIndicatorInterface <NSObject>

- (void)startAnimation:(id)sender;
- (void)stopAnimation:(id)sender;
- (void)setHidden:(BOOL)hide;
- (BOOL)isHidden;

@end

@interface PSMDeterminateIndicatorLayer: CALayer
- (void)setFraction:(CGFloat)fraction color:(NSColor *)color animated:(BOOL)animated;
@end

@implementation PSMDeterminateIndicatorLayer {
    CAShapeLayer *_track;
    CAShapeLayer *_progress;
    CGFloat _fraction;
    NSColor *_color;
}

- (instancetype)initWithDiameter:(CGFloat)diameter {
    self = [super init];
    if (self) {
        self.frame = NSMakeRect(0, 0, diameter, diameter);

        const CGFloat lineWidth = MAX(2.0, round(diameter * 0.08));

        _track = [CAShapeLayer layer];
        _track.fillColor = nil;
        _track.lineCap = kCALineCapRound;
        _track.lineWidth = lineWidth;

        _progress = [CAShapeLayer layer];
        _progress.lineWidth = lineWidth;
        _progress.fillColor = nil;
        _progress.lineCap = kCALineCapRound;
        _progress.strokeStart = 0.0;

        CGPathRef path = [self pathWithDiameter:diameter
                                      lineWidth:lineWidth];
        _track.path = path;
        _progress.path = path;
        CGPathRelease(path);

        [self addSublayer:_track];
        [self addSublayer:_progress];
    }
    return self;
}

- (void)updateAnimated:(BOOL)animated {
    const CGFloat fraction = MAX(MIN(1.0, _fraction), 0.0);

    NSColor *baseColor = [_color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    if (baseColor == nil) {
        baseColor = [NSColor controlAccentColor];
    }

    [CATransaction begin];
    if (!animated) {
        [CATransaction setDisableActions:YES];
    }
    _track.strokeColor = [[baseColor colorWithAlphaComponent:0.20] CGColor];
    _progress.strokeColor = [baseColor CGColor];
    _progress.strokeEnd = fraction;
    [CATransaction commit];
}

- (CGPathRef)pathWithDiameter:(CGFloat)diameter
                    lineWidth:(CGFloat)lineWidth {
    CGPoint center = CGPointMake(diameter / 2.0, diameter / 2.0);
    CGFloat radius = (diameter - lineWidth) / 2.0;

    CGMutablePathRef path = CGPathCreateMutable();
    // Start at 12 o'clock (M_PI_2 in flipped coordinates) and go clockwise to match macOS
    CGPathAddArc(path, NULL, center.x, center.y, radius, (CGFloat)(M_PI_2), (CGFloat)(M_PI_2 - 2.0 * M_PI), true);
    return path;
}

- (void)setFraction:(CGFloat)fraction color:(NSColor *)color animated:(BOOL)animated {
    _fraction = fraction;
    _color = color;
    [self updateAnimated:animated];
}

@end

@interface PSMDeterminateIndicator: NSView
@property (nonatomic) double fraction;
@property (nonatomic, strong) NSColor *color;
@end

@implementation PSMDeterminateIndicator {
    PSMDeterminateIndicatorLayer *_layer;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        _layer = [[PSMDeterminateIndicatorLayer alloc] initWithDiameter:frameRect.size.width];
        self.layer = _layer;
    }
    return self;
}

- (void)setFraction:(CGFloat)fraction color:(NSColor *)color animated:(BOOL)animated {
    _fraction = fraction;
    _color = color;
    [_layer setFraction:_fraction color:_color animated:animated];
}

@end

@implementation PSMProgressIndicator  {
    NSProgressIndicator *_indeterminateIndicator;
    PSMDeterminateIndicator *_determinateIndicator;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _indeterminate = YES;
        _indeterminateIndicator = [[NSProgressIndicator alloc] initWithFrame:self.bounds];
        _indeterminateIndicator.style = NSProgressIndicatorStyleSpinning;
        _indeterminateIndicator.hidden = YES;

        _determinateIndicator = [[PSMDeterminateIndicator alloc] initWithFrame:self.bounds];
        _determinateIndicator.hidden = YES;

        [self addSubview:_indeterminateIndicator];
        [self addSubview:_determinateIndicator];
    }
    return self;
}

- (void)setAnimate:(BOOL)animate {
    if (animate == _animate) {
        return;
    }
    _animate = animate;
    if (animate) {
        [_indeterminateIndicator startAnimation:nil];
    } else {
        [_indeterminateIndicator stopAnimation:nil];
    }
}

- (void)setLight:(BOOL)light {
    _light = light;
    [self updateAnimated:NO];
}

- (void)becomeIndeterminate {
    _indeterminate = YES;
    [self updateAnimated:NO];
}

- (void)becomeDeterminateWithFraction:(CGFloat)fraction
                               status:(PSMStatus)status
                             animated:(BOOL)animated {
    self.animate = NO;
    _indeterminate = NO;
    _status = status;
    _fraction = fraction;
    [self updateAnimated:animated];
}

- (void)updateAnimated:(BOOL)animated {
    _indeterminateIndicator.appearance = _light ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] : [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    _indeterminateIndicator.hidden = !_indeterminate;
    _determinateIndicator.hidden = _indeterminate;
    if (!_indeterminate) {
        [_determinateIndicator setFraction:_fraction
                                     color:self.effectiveColor
                                  animated:animated];
    }
}

- (NSColor *)effectiveColor {
    switch (_status) {
        case PSMStatusError:
            return [NSColor redColor];
        case PSMStatusSuccess:
            if (self.inDarkMode) {
                return [NSColor colorWithSRGBRed:00.0 green:1.0 blue:0.0 alpha:1.0];
            } else {
                return [NSColor blueColor];
            }
        case PSMStatusWarning:
            return [NSColor orangeColor];
    }
}

- (void)viewDidChangeEffectiveAppearance {
    [self updateAnimated:YES];
}

- (BOOL)inDarkMode {
    NSAppearanceName bestMatch = [self.effectiveAppearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameDarkAqua,
                                                                                                NSAppearanceNameVibrantDark,
                                                                                                NSAppearanceNameAqua,
                                                                                                NSAppearanceNameVibrantLight ]];
    if ([bestMatch isEqualToString:NSAppearanceNameDarkAqua] ||
        [bestMatch isEqualToString:NSAppearanceNameVibrantDark]) {
        return YES;
    }
    return NO;
}

@end
