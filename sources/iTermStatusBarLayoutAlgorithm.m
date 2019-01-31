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
                                    mandatoryView:(nonnull iTermStatusBarContainerView *)mandatoryView
                                   statusBarWidth:(CGFloat)statusBarWidth
                                          setting:(iTermStatusBarLayoutAlgorithmSetting)setting {
    switch (setting) {
        case iTermStatusBarLayoutAlgorithmSettingStable:
            return [[iTermStatusBarStableLayoutAlgorithm alloc] initWithContainerViews:containerViews
                                                                         mandatoryView:mandatoryView
                                                                        statusBarWidth:statusBarWidth];
        case iTermStatusBarLayoutAlgorithmSettingTightlyPacked:
            return [[iTermStatusBarTightlyPackedLayoutAlgorithm alloc] initWithContainerViews:containerViews
                                                                                mandatoryView:mandatoryView
                                                                          statusBarWidth:statusBarWidth];
    }
    return nil;
}

- (instancetype)initWithContainerViews:(NSArray<iTermStatusBarContainerView *> *)containerViews
                         mandatoryView:(nonnull iTermStatusBarContainerView *)mandatoryView
                        statusBarWidth:(CGFloat)statusBarWidth {
    self = [super init];
    if (self) {
        _mandatoryView = mandatoryView;
    }
    return self;
}

- (NSArray<iTermStatusBarContainerView *> *)visibleContainerViews {
    assert(NO);
    return @[];
}

@end


