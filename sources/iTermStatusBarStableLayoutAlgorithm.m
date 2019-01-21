//
//  iTermStatusBarStableLayoutAlgorithm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/20/19.
//

#import "iTermStatusBarStableLayoutAlgorithm.h"

#import "DebugLogging.h"
#import "iTermStatusBarComponent.h"
#import "iTermStatusBarContainerView.h"
#import "iTermStatusBarFixedSpacerComponent.h"
#import "iTermStatusBarSpringComponent.h"
#import "NSArray+iTerm.h"

@implementation iTermStatusBarStableLayoutAlgorithm

- (iTermStatusBarContainerView *)containerViewWithLargestMinimumWidthFromViews:(NSArray<iTermStatusBarContainerView *> *)views {
    return [views maxWithBlock:^NSComparisonResult(iTermStatusBarContainerView *obj1, iTermStatusBarContainerView *obj2) {
        return [@(obj1.component.statusBarComponentMinimumWidth) compare:@(obj2.component.statusBarComponentMinimumWidth)];
    }];
}

- (NSArray<iTermStatusBarContainerView *> *)allPossibleCandidateViews {
    NSArray<iTermStatusBarContainerView *> *unhidden = [self unhiddenContainerViews];
    return [self fittingSubsetOfContainerViewsFrom:unhidden];
}

- (BOOL)componentIsSpacer:(id<iTermStatusBarComponent>)component {
    return ([component isKindOfClass:[iTermStatusBarSpringComponent class]] ||
            [component isKindOfClass:[iTermStatusBarFixedSpacerComponent class]]);
}

- (BOOL)views:(NSArray<iTermStatusBarContainerView *> *)views
haveSpacersOnBothSidesOfIndex:(NSInteger)index
         left:(out id<iTermStatusBarComponent>*)leftOut
        right:(out id<iTermStatusBarComponent>*)rightOut {
    if (index == 0) {
        return NO;
    }
    if (index + 1 == views.count) {
        return NO;
    }
    id<iTermStatusBarComponent> left = views[index - 1].component;
    id<iTermStatusBarComponent> right = views[index + 1].component;
    if (![self componentIsSpacer:left] || ![self componentIsSpacer:right]) {
        return NO;
    }
    *leftOut = left;
    *rightOut = right;
    return YES;
}

- (CGFloat)minimumWidthOfContainerViews:(NSArray<iTermStatusBarContainerView *> *)views {
    iTermStatusBarContainerView *viewWithLargestMinimumWidth = [self containerViewWithLargestMinimumWidthFromViews:views];
    const CGFloat largestMinimumSize = viewWithLargestMinimumWidth.component.statusBarComponentMinimumWidth;
    NSArray<iTermStatusBarContainerView *> *viewsExFixedSpacers = [self viewsExcludingFixedSpacers:views];
    const CGFloat widthOfAllFixedSpacers = [self widthOfFixedSpacersAmongViews:views];
    return largestMinimumSize * viewsExFixedSpacers.count + widthOfAllFixedSpacers;
}

- (NSArray<iTermStatusBarContainerView *> *)visibleContainerViewsAllowingEqualSpacingFromViews:(NSArray<iTermStatusBarContainerView *> *)visibleContainerViews {
    if (_statusBarWidth >= [self minimumWidthOfContainerViews:visibleContainerViews]) {
        return visibleContainerViews;
    }

    iTermStatusBarContainerView *viewWithLargestMinimumWidth = [self containerViewWithLargestMinimumWidthFromViews:visibleContainerViews];
    iTermStatusBarContainerView *adjacentViewToRemove = [self viewToRemoveAdjacentToViewBeingRemoved:viewWithLargestMinimumWidth
                                                                                           fromViews:visibleContainerViews];
    if (adjacentViewToRemove) {
        visibleContainerViews = [visibleContainerViews arrayByRemovingObject:adjacentViewToRemove];
    }
    visibleContainerViews = [visibleContainerViews arrayByRemovingObject:viewWithLargestMinimumWidth];
    return [self visibleContainerViewsAllowingEqualSpacingFromViews:visibleContainerViews];
}

- (NSArray<iTermStatusBarContainerView *> *)visibleContainerViewsAllowingEqualSpacing {
    if (_statusBarWidth <= 0) {
        return @[];
    }
    return [self visibleContainerViewsAllowingEqualSpacingFromViews:[self allPossibleCandidateViews]];
}

- (iTermStatusBarContainerView *)viewToRemoveAdjacentToViewBeingRemoved:(iTermStatusBarContainerView *)viewBeingRemoved
                                                              fromViews:(NSArray<iTermStatusBarContainerView *> *)views {
    NSInteger index = [views indexOfObject:viewBeingRemoved];
    assert(index != NSNotFound);
    id<iTermStatusBarComponent> left;
    id<iTermStatusBarComponent> right;
    if (![self views:views haveSpacersOnBothSidesOfIndex:[views indexOfObject:viewBeingRemoved] left:&left right:&right]) {
        return nil;
    }
    if (left.statusBarComponentSpringConstant > right.statusBarComponentSpringConstant) {
        return views[index - 1];
    } else if (left.statusBarComponentSpringConstant < right.statusBarComponentSpringConstant) {
        return views[index + 1];
    } else if (index < views.count / 2) {
        return views[index + 1];
    } else {
        return views[index - 1];
    }
}

- (NSArray<iTermStatusBarContainerView *> *)viewsExcludingFixedSpacers:(NSArray<iTermStatusBarContainerView *> *)views {
    return [views filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *view) {
        return ![view.component isKindOfClass:[iTermStatusBarFixedSpacerComponent class]];
    }];
}

- (CGFloat)widthOfFixedSpacersAmongViews:(NSArray<iTermStatusBarContainerView *> *)views {
    return [[views reduceWithFirstValue:@0 block:^id(NSNumber *partialSum, iTermStatusBarContainerView *view) {
        if (![view.component isKindOfClass:[iTermStatusBarFixedSpacerComponent class]]) {
            return partialSum;
        }
        return @(partialSum.doubleValue + view.component.statusBarComponentMinimumWidth);
    }] doubleValue];
}

- (double)sumOfSpringConstantsInViews:(NSArray<iTermStatusBarContainerView *> *)views {
    return [[views reduceWithFirstValue:@0 block:^id(NSNumber *partialSum, iTermStatusBarContainerView *view) {
        return @(partialSum.doubleValue + view.component.statusBarComponentSpringConstant);
    }] doubleValue];
}

- (void)updateDesiredWidthsForViews:(NSArray<iTermStatusBarContainerView *> *)views {
    [self updateMargins:views];
    NSArray<iTermStatusBarContainerView *> *viewsExFixedSpacers = [self viewsExcludingFixedSpacers:views];
    const CGFloat widthOfAllFixedSpacers = [self widthOfFixedSpacersAmongViews:views];
    const CGFloat totalMarginWidth = [self totalMarginWidthForViews:views];
    const CGFloat availableWidth = _statusBarWidth - totalMarginWidth - widthOfAllFixedSpacers;
    const double sumOfSpringConstants = [self sumOfSpringConstantsInViews:viewsExFixedSpacers];
    const CGFloat apportionment = availableWidth / sumOfSpringConstants;
    DLog(@"updateDesiredWidthsForViews available=%@ apportionment=%@", @(availableWidth), @(apportionment));
    // Allocate minimum widths
    [views enumerateObjectsUsingBlock:^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([view.component isKindOfClass:[iTermStatusBarFixedSpacerComponent class]]) {
            view.desiredWidth = view.component.statusBarComponentMinimumWidth;
            return;
        }
        view.desiredWidth = apportionment * view.component.statusBarComponentSpringConstant;
    }];
}

- (NSArray<iTermStatusBarContainerView *> *)visibleContainerViews {
    NSArray<iTermStatusBarContainerView *> *visibleContainerViews = [self visibleContainerViewsAllowingEqualSpacing];

    [self updateDesiredWidthsForViews:visibleContainerViews];
    return visibleContainerViews;
}

@end
