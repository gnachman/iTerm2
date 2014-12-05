//
//  PSMProgressIndicator.m
//  PSMTabBarControl
//
//  Created by John Pannell on 2/23/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import "PSMProgressIndicator.h"
#import <QuartzCore/QuartzCore.h>

@interface PSMProgressIndicator ()
@property BOOL animate;
@property BOOL hidden;
@end

@implementation PSMProgressIndicator {
    NSProgressIndicator *_indicator;
    BOOL _light;
    BOOL _animating;
}

- (id)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _indicator = [[NSProgressIndicator alloc] initWithFrame:self.bounds];
        [self observeIndicator];
        [self addSubview:_indicator];
        [[self class] exposeBinding:@"animate"];
        [[self class] exposeBinding:@"hidden"];
    }
    return self;
}

- (void)dealloc {
    [self stopObservingIndicator];
    [_indicator release];
    [super dealloc];
}

// overrides to make tab bar control re-layout things if status changes
- (void)setHidden:(BOOL)flag {
    [super setHidden:flag];
    [_delegate progressIndicatorNeedsUpdate];
}

// Changing the frame of a layer-backed view doesn't seem to work very well (tested on 10.9). It
// only seems to move if we remove the layer, move it, and then re-add the layer after a spin of the
// runloop.
- (void)setFrame:(NSRect)frame {
    if (_light) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(reenableLayerIfNeeded)
                                                   object:nil];
        [self performSelector:@selector(reenableLayerIfNeeded) withObject:nil afterDelay:0];
        [self setWantsLayer:NO];
    }
    [super setFrame:frame];
}

- (void)reenableLayerIfNeeded {
  if (_light) {
    [self setWantsLayer:YES];
  }
}

- (void)startAnimation:(id)sender {
    _animating = YES;
    [_indicator startAnimation:sender];
}

- (void)stopAnimation:(id)sender {
    _animating = NO;
    [_indicator stopAnimation:sender];
}


- (void)setLight:(BOOL)light {
    if (light == _light) {
        return;
    }
    _light = light;

    NSControlSize controlSize = _indicator.controlSize;
    NSProgressIndicatorStyle style = _indicator.style;
    [self stopObservingIndicator];
    [_indicator removeFromSuperview];
    [_indicator release];

    _indicator = [[NSProgressIndicator alloc] initWithFrame:self.bounds];
    _indicator.style = style;
    _indicator.controlSize = controlSize;
    [self addSubview:_indicator];
    [self observeIndicator];
    if (_animating) {
        [_indicator startAnimation:nil];
    }

    if (light) {
        CIFilter *filter = [CIFilter filterWithName:@"CIColorControls"];
        [filter setDefaults];
        [filter setValue:@0.3 forKey:@"inputBrightness"];
        [_indicator setWantsLayer:YES];
        if ([_indicator respondsToSelector:@selector(layerUsesCoreImageFilters)]) {
            _indicator.layerUsesCoreImageFilters = YES;
        }
        [_indicator setContentFilters:@[ filter ]];
    }
}

- (void)setStyle:(NSProgressIndicatorStyle)style {
    [_indicator setStyle:style];
}

- (NSProgressIndicatorStyle)style {
    return _indicator.style;
}

- (void)setControlSize:(NSControlSize)controlSize {
    [_indicator setControlSize:controlSize];
}

- (NSControlSize)controlSize {
    return _indicator.controlSize;
}

- (void)observeIndicator {
    [_indicator bind:@"animate" toObject:self withKeyPath:@"animate" options:nil];
    [_indicator bind:@"hidden" toObject:self withKeyPath:@"hidden" options:nil];
}

- (void)stopObservingIndicator {
    [_indicator unbind:@"animate"];
    [_indicator unbind:@"hidden"];
}

@end
