//
//  PSMProgressIndicator.m
//  PSMTabBarControl
//
//  Created by John Pannell on 2/23/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import "PSMProgressIndicator.h"
#import <QuartzCore/QuartzCore.h>

@implementation PSMProgressIndicator {
    BOOL _light;
}

// overrides to make tab bar control re-layout things if status changes
- (void)setHidden:(BOOL)flag {
    [super setHidden:flag];
    [(PSMTabBarControl *)[self superview] update];
}

// Changing the frame of a layer-backed view doesn't seem to work very well (tested on 10.9). It
// only seems to move if we remove the layer, move it, and then re-add the layer after a spin of the
// runloop.
- (void)setFrame:(NSRect)frame {
  BOOL wasLight = _light;
  if (_light) {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(reenableLayerIfNeeded)
                                               object:nil];
    [self setWantsLayer:NO];
  }
  [super setFrame:frame];
  if (wasLight) {
    [self performSelector:@selector(reenableLayerIfNeeded) withObject:nil afterDelay:0];
  }
}

- (void)reenableLayerIfNeeded {
  if (_light) {
    [self setWantsLayer:YES];
  }
}

- (void)setLight:(BOOL)light {
    _light = light;
    if (light) {
        CIFilter *filter = [CIFilter filterWithName:@"CIColorControls"];
        [filter setDefaults];
        [filter setValue:@0.3 forKey:@"inputBrightness"];
        [self setWantsLayer:YES];
        [self setContentFilters:@[ filter ]];
    } else {
        [self setWantsLayer:NO];
        [self setContentFilters:@[ ]];
    }
}

@end
