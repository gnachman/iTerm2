//
//  iTermTipLayerBackedView.m
//  iTerm2
//
//  Created by George Nachman on 6/17/15.
//
//

#import "iTermTipLayerBackedView.h"

@implementation iTermTipLayerBackedView

- (BOOL)isFlipped {
  return YES;
}

- (BOOL)wantsLayer {
  return YES;
}

@end
