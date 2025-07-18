//
//  iTermMetalClipView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/2/17.
//

#import "iTermMetalClipView.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermRateLimitedUpdate.h"
#import <MetalKit/MetalKit.h>

NSString *const iTermMetalClipViewWillScroll = @"iTermMetalClipViewWillScroll";

@interface NSClipView(Private)
- (BOOL)_shouldShowOverlayScrollersForScrollToPoint:(CGPoint)point;
@end

@implementation iTermMetalClipView {
    NSInteger _disableShowingOverlayScrollers;
}

- (void)scrollToPoint:(NSPoint)newOrigin {
    DLog(@"scrollToPoint:%@\n%@", NSStringFromPoint(newOrigin), [NSThread callStackSymbols]);
    [super scrollToPoint:newOrigin];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermMetalClipViewWillScroll object:self];
    if (_useMetal) {
        [_metalView setNeedsDisplay:YES];
    } else {
        [_legacyView setNeedsDisplay:YES];
    }
}

- (void)performBlockWithoutShowingOverlayScrollers:(void (^ NS_NOESCAPE)(void))block {
    _disableShowingOverlayScrollers += 1;
    block();
    _disableShowingOverlayScrollers -= 1;
}

- (BOOL)_shouldShowOverlayScrollersForScrollToPoint:(CGPoint)point {
    if (_disableShowingOverlayScrollers) {
        return NO;
    }
    return [super _shouldShowOverlayScrollersForScrollToPoint:point];
}

@end

