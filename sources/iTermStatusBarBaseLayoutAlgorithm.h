//
//  iTermStatusBarBaseLayoutAlgorithm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/20/19.
//

#import "iTermStatusBarLayoutAlgorithm.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermStatusBarBaseLayoutAlgorithm : iTermStatusBarLayoutAlgorithm {
@protected
    CGFloat _statusBarWidth;
    NSArray<iTermStatusBarContainerView *> *_containerViews;
}

- (NSArray<iTermStatusBarContainerView *> *)unhiddenContainerViews;
- (NSArray<iTermStatusBarContainerView *> *)fittingSubsetOfContainerViewsFrom:(NSArray<iTermStatusBarContainerView *> *)views;
- (void)updateMargins:(NSArray<iTermStatusBarContainerView *> *)views;
- (CGFloat)totalMarginWidthForViews:(NSArray<iTermStatusBarContainerView *> *)views;
- (CGFloat)minimumWidthOfContainerViews:(NSArray<iTermStatusBarContainerView *> *)views;
- (NSArray<iTermStatusBarContainerView *> *)containerViewsSortedByPriority:(NSArray<iTermStatusBarContainerView *> *)eligibleContainerViews;

@end

NS_ASSUME_NONNULL_END
