//
//  iTermStatusBarTightlyPackedLayoutAlgorithm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/20/19.
//

#import "iTermStatusBarTightlyPackedLayoutAlgorithm.h"

#import "DebugLogging.h"
#import "iTermStatusBarComponent.h"
#import "iTermStatusBarContainerView.h"
#import "NSArray+iTerm.h"

@implementation iTermStatusBarTightlyPackedLayoutAlgorithm

- (double)totalGrowthAfterUpdatingDesiredWidthsForAvailableWidth:(CGFloat)availableWidth
                                            sumOfSpringConstants:(double)sumOfSpringConstants
                                                           views:(NSArray<iTermStatusBarContainerView *> *)views {
    __block double growth = 0;
    // Divvy up space proportionate to spring constants.
    [views enumerateObjectsUsingBlock:^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
        const double weight = view.component.statusBarComponentSpringConstant / sumOfSpringConstants;
        double delta = floor(availableWidth * weight);
        const double maximum = view.component.statusBarComponentPreferredWidth + (view.component.statusBarComponentIcon ? iTermStatusBarViewControllerIconWidth : 0);
        const double proposed = view.desiredWidth + delta;
        const double overage = floor(MAX(0, proposed - maximum));
        delta -= overage;
        view.desiredWidth += delta;
        growth += delta;
        DLog(@"  grow %@ by %@ to %@. Its preferred width is %@", view.component, @(delta), @(view.desiredWidth), @(view.component.statusBarComponentPreferredWidth));
    }];
    return growth;
}


@end
