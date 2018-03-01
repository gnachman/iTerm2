//
//  iTermMetalClipView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/2/17.
//

#import "iTermMetalClipView.h"

#import "DebugLogging.h"
#import "iTermRateLimitedUpdate.h"
#import <MetalKit/MetalKit.h>

@implementation iTermMetalClipView {
    iTermRateLimitedUpdate *_rateLimit;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.copiesOnScroll = NO;
        _rateLimit = [[iTermRateLimitedUpdate alloc] init];
        _rateLimit.minimumInterval = 1.0 / 60.0;
    }
    return self;
}

- (void)scrollToPoint:(NSPoint)newOrigin {
    [super scrollToPoint:newOrigin];
    if (_useMetal) {
        BOOL performed = [_rateLimit tryPerformRateLimitedBlock:^{
            [_metalView draw];
        }];
        if (!performed) {
            [_metalView setNeedsDisplay:YES];
        }
    }
}

@end

