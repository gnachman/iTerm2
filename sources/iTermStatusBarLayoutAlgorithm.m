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
#import "iTermStatusBarTightlyPackedLayoutAlgorithm.h"
#import "iTermStatusBarStableLayoutAlgorithm.h"

const CGFloat iTermStatusBarViewControllerMargin = 10;

@implementation iTermStatusBarLayoutAlgorithm

+ (instancetype)alloc {
    if ([self class] == [iTermStatusBarLayoutAlgorithm class]) {
        assert(NO);
    }
    return [super alloc];
}

+ (instancetype)layoutAlgorithmWithContainerViews:(NSArray<iTermStatusBarContainerView *> *)containerViews
                                   statusBarWidth:(CGFloat)statusBarWidth
                                          setting:(iTermStatusBarLayoutAlgorithmSetting)setting {
    switch (setting) {
        case iTermStatusBarLayoutAlgorithmSettingStable:
            return [[iTermStatusBarStableLayoutAlgorithm alloc] initWithContainerViews:containerViews
                                                                        statusBarWidth:statusBarWidth];
        case iTermStatusBarLayoutAlgorithmSettingTightlyPacked:
            return [[iTermStatusBarTightlyPackedLayoutAlgorithm alloc] initWithContainerViews:containerViews
                                                                          statusBarWidth:statusBarWidth];
    }
    return nil;
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


