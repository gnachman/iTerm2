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

// Paused with no fraction to show: the determinate indicator's faint track
// with a pause glyph inside it, standing still so it does not read as work in
// progress.
@interface PSMPausedIndicator: NSView
@property (nonatomic, strong) NSColor *color;
@end

@implementation PSMPausedIndicator {
    CAShapeLayer *_track;
    CAShapeLayer *_glyph;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        const CGFloat diameter = frameRect.size.width;
        const CGFloat lineWidth = MAX(2.0, round(diameter * 0.08));

        _track = [CAShapeLayer layer];
        _track.fillColor = nil;
        _track.lineWidth = lineWidth;
        const CGFloat inset = lineWidth / 2.0;
        CGPathRef ring = CGPathCreateWithEllipseInRect(CGRectMake(inset,
                                                                  inset,
                                                                  diameter - lineWidth,
                                                                  diameter - lineWidth),
                                                       NULL);
        _track.path = ring;
        CGPathRelease(ring);

        // Two bars, centered, each a fifth of the diameter apart.
        _glyph = [CAShapeLayer layer];
        const CGFloat barWidth = MAX(1.5, round(diameter * 0.14));
        const CGFloat barHeight = round(diameter * 0.42);
        const CGFloat gap = MAX(1.5, round(diameter * 0.12));
        const CGFloat left = (diameter - (2.0 * barWidth + gap)) / 2.0;
        const CGFloat bottom = (diameter - barHeight) / 2.0;
        CGMutablePathRef bars = CGPathCreateMutable();
        CGPathAddRoundedRect(bars, NULL, CGRectMake(left, bottom, barWidth, barHeight),
                             barWidth / 3.0, barWidth / 3.0);
        CGPathAddRoundedRect(bars, NULL, CGRectMake(left + barWidth + gap, bottom, barWidth, barHeight),
                             barWidth / 3.0, barWidth / 3.0);
        _glyph.path = bars;
        CGPathRelease(bars);

        [self.layer addSublayer:_track];
        [self.layer addSublayer:_glyph];
    }
    return self;
}

- (void)setColor:(NSColor *)color {
    _color = color;
    NSColor *baseColor = [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: [NSColor controlAccentColor];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _track.strokeColor = [[baseColor colorWithAlphaComponent:0.20] CGColor];
    _glyph.fillColor = [baseColor CGColor];
    [CATransaction commit];
}

@end

@implementation PSMProgressIndicator  {
    NSProgressIndicator *_indeterminateIndicator;
    PSMDeterminateIndicator *_determinateIndicator;
    PSMPausedIndicator *_pausedIndicator;
    // Showing the pause glyph. Neither indeterminate (there is no spinner to
    // run) nor determinate (there is no fraction).
    BOOL _paused;
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

        _pausedIndicator = [[PSMPausedIndicator alloc] initWithFrame:self.bounds];
        _pausedIndicator.hidden = YES;

        [self addSubview:_indeterminateIndicator];
        [self addSubview:_determinateIndicator];
        [self addSubview:_pausedIndicator];
    }
    return self;
}

- (void)setAnimate:(BOOL)animate {
    if (animate == _animate) {
        return;
    }
    _animate = animate;
    [self updateAnimation];
}

// Only the indeterminate indicator has a spinner to run. A determinate one hides it (see
// -updateAnimated:), so animating it is work nobody can see, and callers ask for animation without
// knowing which mode this is in: the tab bar turns it on for every cell it adds, on every frame
// change, and at the end of a live resize. Decide here, where the mode is known, rather than at each
// of those call sites.
- (void)updateAnimation {
    if (_animate && _indeterminate) {
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
    _paused = NO;
    [self updateAnimated:NO];
    // There is a spinner to run again now, so honor a -setAnimate:YES that arrived while this was
    // determinate.
    [self updateAnimation];
}

- (void)becomeDeterminateWithFraction:(CGFloat)fraction
                               status:(PSMStatus)status
                             animated:(BOOL)animated {
    self.animate = NO;
    _indeterminate = NO;
    _paused = NO;
    _status = status;
    _fraction = fraction;
    [self updateAnimated:animated];
}

- (void)becomePausedIndeterminate {
    self.animate = NO;
    _indeterminate = NO;
    _paused = YES;
    _status = PSMStatusWarning;
    [self updateAnimated:NO];
    // Stop a spinner that was running; there is nothing to animate now.
    [self updateAnimation];
}

- (void)updateAnimated:(BOOL)animated {
    _indeterminateIndicator.appearance = _light ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] : [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    _indeterminateIndicator.hidden = !_indeterminate;
    _determinateIndicator.hidden = _indeterminate || _paused;
    _pausedIndicator.hidden = !_paused;
    if (_paused) {
        _pausedIndicator.color = self.effectiveColor;
    } else if (!_indeterminate) {
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
