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

@implementation PSMProgressIndicator {
    AMIndeterminateProgressIndicator *_lightIndicator;
    AMIndeterminateProgressIndicator *_darkIndicator;
    BOOL _light;
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

- (void)dealloc {
    [_darkIndicator release];
    [_lightIndicator release];
    [super dealloc];
}

- (void)setHidden:(BOOL)flag {
    [super setHidden:flag];
    [_delegate progressIndicatorNeedsUpdate];
    if (_animate && flag) {
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
    if (light == _light) {
        return;
    }

    BOOL shouldHide = self.currentIndicator.isHidden;
    [self.currentIndicator setHidden:YES];
    [self.currentIndicator stopAnimation:nil];

    _light = light;

    [self.currentIndicator setHidden:shouldHide];
    if (!shouldHide && _animate) {
        [self.currentIndicator startAnimation:nil];
    }
}

- (void)setAnimate:(BOOL)animate {
    if (animate != _animate) {
        _animate = animate;
        if (animate && !self.isHidden) {
            [self startAnimation:nil];
        } else {
            [self stopAnimation:nil];
        }
    }
}

@end
