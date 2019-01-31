//
//  iTermStatusBarBaseLayoutAlgorithm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/20/19.
//

#import "iTermStatusBarBaseLayoutAlgorithm.h"

#import "DebugLogging.h"
#import "iTermStatusBarComponent.h"
#import "iTermStatusBarContainerView.h"
#import "NSArray+iTerm.h"

@implementation iTermStatusBarBaseLayoutAlgorithm

- (instancetype)initWithContainerViews:(NSArray<iTermStatusBarContainerView *> *)containerViews
                         mandatoryView:(nonnull iTermStatusBarContainerView *)mandatoryView
                        statusBarWidth:(CGFloat)statusBarWidth {
    self = [super initWithContainerViews:containerViews
                           mandatoryView:mandatoryView
                          statusBarWidth:statusBarWidth];
    if (self) {
        _statusBarWidth = statusBarWidth;
        _containerViews = [containerViews copy];
    }
    return self;
}

- (CGFloat)totalMarginWidthForViews:(NSArray<iTermStatusBarContainerView *> *)views {
    const CGFloat totalMarginWidth = [[views reduceWithFirstValue:@0 block:^NSNumber *(NSNumber *sum, iTermStatusBarContainerView *view) {
        return @(sum.doubleValue + view.leftMargin + view.rightMargin);
    }] doubleValue];
    return totalMarginWidth;
}

- (CGFloat)availableWidthAfterInitializingDesiredWidthForViews:(NSArray<iTermStatusBarContainerView *> *)views {
    const CGFloat totalMarginWidth = [self totalMarginWidthForViews:views];
    __block CGFloat availableWidth = _statusBarWidth - totalMarginWidth;
    DLog(@"availableWidthAfterInitializingDesiredWidthForViews available=%@", @(availableWidth));
    // Allocate minimum widths
    [views enumerateObjectsUsingBlock:^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
        view.desiredWidth = view.component.statusBarComponentMinimumWidth;
        if (view.component.statusBarComponentIcon) {
            view.desiredWidth = view.desiredWidth + iTermStatusBarViewControllerIconWidth;
        }
        availableWidth -= view.desiredWidth;
    }];
    DLog(@"availableWidthAfterInitializingDesiredWidthForViews after assigning minimums: available=%@", @(availableWidth));
    return availableWidth;
}

- (NSArray<iTermStatusBarContainerView *> *)viewsThatCanGrowFromViews:(NSArray<iTermStatusBarContainerView *> *)views {
    return [views filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *view) {
        double preferredWidth = view.component.statusBarComponentPreferredWidth;
        if (view.component.statusBarComponentIcon) {
            preferredWidth += iTermStatusBarViewControllerIconWidth;
        }
        return ([view.component statusBarComponentCanStretch] &&
                floor(preferredWidth) > floor(view.desiredWidth));
    }];
}

- (double)sumOfSpringConstantsInViews:(NSArray<iTermStatusBarContainerView *> *)views {
    return [[views reduceWithFirstValue:@0 block:^NSNumber *(NSNumber *sum, iTermStatusBarContainerView *containerView) {
        if (![containerView.component statusBarComponentCanStretch]) {
            return sum;
        }
        return @(sum.doubleValue + containerView.component.statusBarComponentSpringConstant);
    }] doubleValue];
}

- (NSArray<iTermStatusBarContainerView *> *)viewsByRemovingViewThatCannotGrow:(NSArray<iTermStatusBarContainerView *> *)views {
    return [views filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *view) {
        double preferredWidth = view.component.statusBarComponentPreferredWidth;
        if (view.component.statusBarComponentIcon) {
            preferredWidth += iTermStatusBarViewControllerIconWidth;
        }
        const BOOL unsatisfied = floor(preferredWidth) > ceil(view.desiredWidth);
        if (unsatisfied) {
            DLog(@"%@ unsatisfied prefers=%@ allocated=%@", view.component.class, @(view.component.statusBarComponentPreferredWidth), @(view.desiredWidth));
        }
        return unsatisfied;
    }];
}

- (double)totalGrowthAfterUpdatingDesiredWidthsForAvailableWidth:(CGFloat)availableWidth
                                            sumOfSpringConstants:(double)sumOfSpringConstants
                                                           views:(NSArray<iTermStatusBarContainerView *> *)views {
    return 0;
}

- (void)updateDesiredWidthsForViews:(NSArray<iTermStatusBarContainerView *> *)allViews {
    [self updateMargins:allViews];
    CGFloat availableWidth = [self availableWidthAfterInitializingDesiredWidthForViews:allViews];

    if (availableWidth < 1) {
        return;
    }

    // Find views that can grow
    NSArray<iTermStatusBarContainerView *> *views = [self viewsThatCanGrowFromViews:allViews];

    while (views.count) {
        const double sumOfSpringConstants = [self sumOfSpringConstantsInViews:views];

        DLog(@"updateDesiredWidths have %@ views that can grow: available=%@",
             @(views.count), @(availableWidth));

        const double growth = [self totalGrowthAfterUpdatingDesiredWidthsForAvailableWidth:availableWidth
                                                                      sumOfSpringConstants:sumOfSpringConstants
                                                                                     views:views];
        availableWidth -= growth;
        DLog(@"updateDesiredWidths after divvying: available = %@", @(availableWidth));

        if (availableWidth < 1) {
            return;
        }

        const NSInteger numberBefore = views.count;
        // Remove satisfied views.
        views = [self viewsByRemovingViewThatCannotGrow:views];

        if (growth < 1 && views.count == numberBefore) {
            DLog(@"Stopping. growth=%@ views %@->%@", @(growth), @(views.count), @(numberBefore));
            return;
        }
    }
}

- (NSArray<iTermStatusBarContainerView *> *)unhiddenContainerViews {
    return [_containerViews filteredArrayUsingBlock:
            ^BOOL(iTermStatusBarContainerView *view) {
                return !view.componentHidden;
            }];
}

- (NSArray<iTermStatusBarContainerView *> *)containerViewsSortedByPriority:(NSArray<iTermStatusBarContainerView *> *)eligibleContainerViews {
    NSView *mandatoryView = self.mandatoryView;
    NSArray<iTermStatusBarContainerView *> *prioritized = [eligibleContainerViews sortedArrayUsingComparator:^NSComparisonResult(iTermStatusBarContainerView * _Nonnull obj1, iTermStatusBarContainerView * _Nonnull obj2) {
        if (obj1 == mandatoryView && obj2 != mandatoryView) {
            return NSOrderedDescending;
        }
        if (obj1 != mandatoryView && obj2 == mandatoryView) {
            return NSOrderedAscending;
        }
        if (obj1 == obj2) {
            return NSOrderedSame;
        }
        NSComparisonResult result = [@(obj1.component.statusBarComponentPriority) compare:@(obj2.component.statusBarComponentPriority)];
        if (result != NSOrderedSame) {
            return result;
        }

        NSInteger index1 = [self->_containerViews indexOfObject:obj1];
        NSInteger index2 = [self->_containerViews indexOfObject:obj2];
        return [@(index1) compare:@(index2)];
    }];
    return prioritized;
}

- (void)updateMargins:(NSArray<iTermStatusBarContainerView *> *)views {
    __block BOOL foundMargin = NO;
    [views enumerateObjectsUsingBlock:^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
        const BOOL hasMargins = view.component.statusBarComponentHasMargins;
        if (hasMargins) {
            view.leftMargin = iTermStatusBarViewControllerMargin / 2 + 1;
        } else {
            view.leftMargin = 0;
        }
    }];

    foundMargin = NO;
    [views enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
        const BOOL hasMargins = view.component.statusBarComponentHasMargins;
        if (hasMargins && !foundMargin) {
            view.rightMargin = iTermStatusBarViewControllerMargin;
            foundMargin = YES;
        } else if (hasMargins) {
            view.rightMargin = iTermStatusBarViewControllerMargin / 2;
        } else {
            view.rightMargin = 0;
        }
    }];
}

- (CGFloat)minimumWidthOfContainerViews:(NSArray<iTermStatusBarContainerView *> *)views {
    [self updateMargins:views];
    NSNumber *sumOfMinimumWidths = [views reduceWithFirstValue:@0 block:^id(NSNumber *sum, iTermStatusBarContainerView *containerView) {
        CGFloat minimumWidth = containerView.component.statusBarComponentMinimumWidth;
        if (containerView.component.statusBarComponentIcon != nil) {
            minimumWidth += iTermStatusBarViewControllerIconWidth;
        }
        DLog(@"Minimum width of %@ is %@", containerView.component.class, @(minimumWidth));
        return @(sum.doubleValue + containerView.leftMargin + minimumWidth + containerView.rightMargin);
    }];
    return sumOfMinimumWidths.doubleValue;
}

- (iTermStatusBarContainerView *)viewToRemoveAdjacentToViewBeingRemoved:(iTermStatusBarContainerView *)view
                                                              fromViews:(NSArray<iTermStatusBarContainerView *> *)views {
    return nil;
}

- (NSArray<iTermStatusBarContainerView *> *)viewsFrom:(NSArray<iTermStatusBarContainerView *> *)allowedViewsSubset
                                       keepingOrderIn:(NSArray<iTermStatusBarContainerView *> *)orderedViewsSuperset {
    return [orderedViewsSuperset filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *view) {
        return [allowedViewsSubset containsObject:view];
    }];
}

// Returns a subset of views by removing the lowest priority item until their minimum sizes all fit within the status bar's width.
- (NSArray<iTermStatusBarContainerView *> *)fittingSubsetOfContainerViewsFrom:(NSArray<iTermStatusBarContainerView *> *)views {
    const CGFloat allowedWidth = _statusBarWidth;
    if (allowedWidth < iTermStatusBarViewControllerMargin * 2) {
        return @[];
    }

    NSMutableArray<iTermStatusBarContainerView *> *prioritized = [self containerViewsSortedByPriority:views].mutableCopy;
    NSMutableArray<iTermStatusBarContainerView *> *prioritizedNonzerominimum = [prioritized filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *anObject) {
        return anObject.component.statusBarComponentMinimumWidth > 0 || anObject.component.statusBarComponentIcon != nil;
    }].mutableCopy;
    CGFloat desiredWidth = [self minimumWidthOfContainerViews:prioritized];
    while (desiredWidth > allowedWidth) {
        iTermStatusBarContainerView *viewToRemove = prioritizedNonzerominimum.firstObject;
        iTermStatusBarContainerView *adjacentViewToRemove = [self viewToRemoveAdjacentToViewBeingRemoved:viewToRemove
                                                                                               fromViews:[self viewsFrom:prioritized keepingOrderIn:_containerViews]];

        // Remove the view with the lowest priority
        [prioritized removeObject:viewToRemove];
        [prioritizedNonzerominimum removeObject:viewToRemove];
        desiredWidth = [self minimumWidthOfContainerViews:prioritizedNonzerominimum];

        // And remove an adjacent spring if the algorithm so prefers.
        if (adjacentViewToRemove) {
            [prioritized removeObject:adjacentViewToRemove];
            [prioritizedNonzerominimum removeObject:adjacentViewToRemove];
            desiredWidth = [self minimumWidthOfContainerViews:prioritizedNonzerominimum];
        }
    }

    // Preserve original order
    return [self viewsFrom:prioritized keepingOrderIn:_containerViews];
}

// Returns non-hidden container views that all satisfy their minimum width requirement.
- (NSArray<iTermStatusBarContainerView *> *)visibleContainerViews {
    NSArray<iTermStatusBarContainerView *> *unhiddenViews = [self unhiddenContainerViews];
    NSArray<iTermStatusBarContainerView *> *visibleContainerViews = [self fittingSubsetOfContainerViewsFrom:unhiddenViews];
    [self updateDesiredWidthsForViews:visibleContainerViews];
    return visibleContainerViews;
}

@end
