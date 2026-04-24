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
                                    mandatoryView:(nullable iTermStatusBarContainerView *)mandatoryView
                                   statusBarWidth:(CGFloat)statusBarWidth
                                          setting:(iTermStatusBarLayoutAlgorithmSetting)setting
                            removeEmptyComponents:(BOOL)removeEmptyComponents {
    switch (setting) {
        case iTermStatusBarLayoutAlgorithmSettingStable:
            return [[iTermStatusBarStableLayoutAlgorithm alloc] initWithContainerViews:containerViews
                                                                         mandatoryView:mandatoryView
                                                                        statusBarWidth:statusBarWidth
                                                                 removeEmptyComponents:removeEmptyComponents];
        case iTermStatusBarLayoutAlgorithmSettingTightlyPacked:
            return [[iTermStatusBarTightlyPackedLayoutAlgorithm alloc] initWithContainerViews:containerViews
                                                                                mandatoryView:mandatoryView
                                                                          statusBarWidth:statusBarWidth
                                                                        removeEmptyComponents:removeEmptyComponents];
    }
    return nil;
}

- (instancetype)initWithContainerViews:(NSArray<iTermStatusBarContainerView *> *)containerViews
                         mandatoryView:(nonnull iTermStatusBarContainerView *)mandatoryView
                        statusBarWidth:(CGFloat)statusBarWidth
                 removeEmptyComponents:(BOOL)removeEmptyComponents {
    self = [super init];
    if (self) {
        _mandatoryView = mandatoryView;
        _removeEmptyComponents = removeEmptyComponents;
    }
    return self;
}

- (NSArray<iTermStatusBarContainerView *> *)visibleContainerViews {
    assert(NO);
    return @[];
}

@end


