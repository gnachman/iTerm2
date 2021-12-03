//
//  PSMProgressIndicator.m
//  PSMTabBarControl
//
//  Created by John Pannell on 2/23/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import "PSMProgressIndicator.h"
#import "AMIndeterminateProgressIndicator.h"
#import <QuartzCore/QuartzCore.h>

@protocol PSMMinimalProgressIndicatorInterface <NSObject>

- (void)startAnimation:(id)sender;
- (void)stopAnimation:(id)sender;
- (void)setHidden:(BOOL)hide;
- (BOOL)isHidden;

@end

@interface PSMNativeProgressIndicator : PSMProgressIndicator
@end

@interface PSMCustomProgressIndicator: PSMProgressIndicator
@end

@implementation PSMProgressIndicator

+ (instancetype)allocWithZone:(struct _NSZone *)zone {
    if (self != [PSMProgressIndicator class]) {
        return [super allocWithZone:zone];
    }
    if (@available(macOS 12, *)) {
        return [PSMNativeProgressIndicator alloc];
    }
    return [PSMCustomProgressIndicator alloc];
}

@end

@implementation PSMNativeProgressIndicator {
    NSProgressIndicator *_indicator;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _indicator = [[NSProgressIndicator alloc] initWithFrame:self.bounds];
        _indicator.style = NSProgressIndicatorStyleSpinning;
        [self addSubview:_indicator];
    }
    return self;
}

- (void)setAnimate:(BOOL)animate {
    if (animate == [self animate]) {
        return;
    }
    [super setAnimate:animate];
    if (animate) {
        [_indicator startAnimation:nil];
    } else {
        [_indicator stopAnimation:nil];
    }
}

- (void)setLight:(BOOL)light {
    _indicator.appearance = light ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] : [NSAppearance appearanceNamed:NSAppearanceNameAqua];
}

@end


@implementation PSMCustomProgressIndicator {
    AMIndeterminateProgressIndicator *_lightIndicator;
    AMIndeterminateProgressIndicator *_darkIndicator;
}

- (id)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _darkIndicator = [[AMIndeterminateProgressIndicator alloc] initWithFrame:self.bounds];
        _darkIndicator.color = [NSColor colorWithCalibratedWhite:0 alpha:1];
        [self addSubview:_darkIndicator];

        _lightIndicator = [[AMIndeterminateProgressIndicator alloc] initWithFrame:self.bounds];
        _lightIndicator.color = [NSColor colorWithCalibratedWhite:0.8 alpha:1];
        [self addSubview:_lightIndicator];
        _lightIndicator.hidden = YES;
    }
    return self;
}

- (void)setHidden:(BOOL)flag {
    [super setHidden:flag];
    [self.delegate progressIndicatorNeedsUpdate];
    if (self.animate && flag) {
        [self stopAnimation:nil];
    }
}

- (id<PSMMinimalProgressIndicatorInterface>)currentIndicator {
    if (self.light) {
        return (id<PSMMinimalProgressIndicatorInterface>)_lightIndicator;
    } else {
        return (id<PSMMinimalProgressIndicatorInterface>)_darkIndicator;
    }
}

- (void)startAnimation:(id)sender {
    self.animate = YES;
    [self.currentIndicator startAnimation:sender];
}

- (void)stopAnimation:(id)sender {
    self.animate = NO;
    [self.currentIndicator stopAnimation:sender];
}

- (void)setLight:(BOOL)light {
    if (light == self.light) {
        return;
    }

    BOOL shouldHide = self.currentIndicator.isHidden;
    [self.currentIndicator setHidden:YES];
    [self.currentIndicator stopAnimation:nil];

    [super setLight:light];

    [self.currentIndicator setHidden:shouldHide];
    if (!shouldHide && self.animate) {
        [self.currentIndicator startAnimation:nil];
    }
}

- (void)setAnimate:(BOOL)animate {
    if (animate != self.animate) {
        [super setAnimate:animate];
        if (animate && !self.isHidden) {
            [self startAnimation:nil];
        } else {
            [self stopAnimation:nil];
        }
    }
}

@end
