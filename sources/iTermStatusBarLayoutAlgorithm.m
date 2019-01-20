//
//  iTermStatusBarLayoutAlgorithm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/19/19.
//

#import "iTermStatusBarLayoutAlgorithm.h"

#import "DebugLogging.h"
#import "iTermStatusBarContainerView.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "iTermStatusBarStandardLayoutAlgorithm.h"
#import "iTermStatusBarStableLayoutAlgorithm.h"

const CGFloat iTermStatusBarViewControllerMargin = 10;

@implementation iTermStatusBarLayoutAlgorithm

+ (instancetype)alloc {
    if (self.class == [iTermStatusBarLayoutAlgorithm class]) {
//        return [iTermStatusBarStandardLayoutAlgorithm alloc];
        return [iTermStatusBarStableLayoutAlgorithm alloc];
    } else {
        return [super alloc];
    }
}

- (instancetype)initWithContainerViews:(NSArray<iTermStatusBarContainerView *> *)containerViews
                        statusBarWidth:(CGFloat)statusBarWidth {
    return [super init];
}

- (NSArray<iTermStatusBarContainerView *> *)visibleContainerViews {
    assert(NO);
    return @[];
}

@end


