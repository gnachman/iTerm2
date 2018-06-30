//
//  iTermStatusBarViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import "iTermStatusBarViewController.h"

#import "iTermStatusBarContainerView.h"
#import "iTermStatusBarLayout.h"
#import "iTermStatusBarView.h"
#import "NSArray+iTerm.h"
#import "NSView+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

static const CGFloat iTermStatusBarViewControllerMargin = 5;
static const CGFloat iTermStatusBarViewControllerTopMargin = 2;
static const CGFloat iTermStatusBarViewControllerBottomMargin = 2;
static const CGFloat iTermStatusBarViewControllerContainerHeight = 22;

@interface iTermStatusBarViewController ()<iTermStatusBarLayoutDelegate>

@end

@implementation iTermStatusBarViewController {
    NSMutableArray<iTermStatusBarContainerView *> *_containerViews;
    NSArray<iTermStatusBarContainerView *> *_visibleContainerViews;
}

- (instancetype)initWithLayout:(iTermStatusBarLayout *)layout {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _layout = layout;
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    iTermStatusBarLayout *layout = [coder decodeObjectOfClass:[iTermStatusBarLayout class]
                                                       forKey:@"layout"];
    if (!layout) {
        return nil;
    }
    return [self initWithLayout:layout];
}

- (void)loadView {
    self.view = [[iTermStatusBarView alloc] initWithFrame:NSZeroRect];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self updateViews];
}

- (void)viewWillLayout {
    NSArray<iTermStatusBarContainerView *> *previouslyVisibleViews = _visibleContainerViews;
    _visibleContainerViews = [self visibleContainerViews];
    [self updateDesiredWidths];
    [self updateDesiredOrigins];

    NSArray<iTermStatusBarContainerView *> *moving = [previouslyVisibleViews filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *containerView) {
        return [self->_visibleContainerViews containsObject:containerView];
    }];
    NSArray<iTermStatusBarContainerView *> *removing = [previouslyVisibleViews filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *containerView) {
        return ![self->_visibleContainerViews containsObject:containerView];
    }];
    NSArray<iTermStatusBarContainerView *> *inserting = [_visibleContainerViews filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *containerView) {
        return ![previouslyVisibleViews containsObject:containerView];
    }];

    [NSView animateWithDuration:0.25
                     animations:
     ^{
         [moving enumerateObjectsUsingBlock:
          ^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
              view.animator.frame = NSMakeRect(view.desiredOrigin,
                                               iTermStatusBarViewControllerTopMargin,
                                               view.desiredWidth,
                                               iTermStatusBarViewControllerContainerHeight);
          }];
         [removing enumerateObjectsUsingBlock:
          ^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
              view.animator.frame = NSMakeRect(view.frame.origin.x,
                                               iTermStatusBarViewControllerTopMargin,
                                               0,
                                               iTermStatusBarViewControllerContainerHeight);
          }];
         [inserting enumerateObjectsUsingBlock:
          ^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
              [self.view addSubview:view];
              view.frame = NSMakeRect(view.desiredOrigin + view.desiredWidth / 2,
                                      iTermStatusBarViewControllerTopMargin,
                                      0,
                                      iTermStatusBarViewControllerContainerHeight);
              view.animator.frame = NSMakeRect(view.desiredOrigin,
                                               iTermStatusBarViewControllerTopMargin,
                                               view.desiredWidth,
                                               iTermStatusBarViewControllerContainerHeight);
          }];
     }
                     completion:
     ^(BOOL finished) {
         [removing enumerateObjectsUsingBlock:
          ^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
              [view removeFromSuperview];
          }];
     }];
}

#pragma mark - Private

- (void)updateDesiredWidths {
    const CGFloat totalMarginWidth = (_containerViews.count + 2) * iTermStatusBarViewControllerMargin;
    const CGFloat availableWidth = self.view.frame.size.width - totalMarginWidth;
    const CGFloat minimumWidth = [self minimumWidthOfContainerViews:_containerViews];
    const CGFloat minimumWidthExcludingMargins = minimumWidth - totalMarginWidth;
    const CGFloat surplusWidth = (availableWidth - minimumWidth);
    [_containerViews enumerateObjectsUsingBlock:^(iTermStatusBarContainerView * _Nonnull containerView, NSUInteger idx, BOOL * _Nonnull stop) {
        const CGFloat minimumForComponent = containerView.component.statusBarComponentMinimumWidth;
        if (containerView.component.statusBarComponentCanStretch) {
            const CGFloat weight = minimumForComponent / minimumWidthExcludingMargins;
            containerView.desiredWidth = floor(minimumForComponent + surplusWidth * weight);
        } else {
            containerView.desiredWidth = minimumForComponent;
        }
    }];
}

- (void)updateDesiredOrigins {
    NSDictionary<NSNumber *, NSArray<iTermStatusBarContainerView *> *> *classified;
    classified = [_containerViews classifyWithBlock:^id(iTermStatusBarContainerView *view) {
        return @(view.component.statusBarComponentJustification);
    }];
    CGFloat left = iTermStatusBarViewControllerMargin;
    for (iTermStatusBarContainerView *view in classified[@(iTermStatusBarComponentJustificationLeft)]) {
        view.desiredOrigin = left;
        left += view.desiredWidth + iTermStatusBarViewControllerMargin;
    }
    CGFloat right = self.view.frame.size.width - iTermStatusBarViewControllerMargin;
    for (iTermStatusBarContainerView *view in classified[@(iTermStatusBarComponentJustificationRight)].reverseObjectEnumerator) {
        view.desiredOrigin = right - view.desiredWidth;
        right -= (view.desiredWidth + iTermStatusBarViewControllerMargin);
    }

    NSArray<iTermStatusBarContainerView *> *centeredViews = classified[@(iTermStatusBarComponentJustificationCenter)];
    CGFloat sumOfCenteredViewsWidths = [[centeredViews reduceWithFirstValue:@0 block:^NSNumber *(NSNumber *sum, iTermStatusBarContainerView *view) {
        return @(sum.doubleValue + view.desiredWidth);
    }] doubleValue];

    CGFloat inset = floor(((right - left) - sumOfCenteredViewsWidths) / 2);
    left += inset;
    for (iTermStatusBarContainerView *view in centeredViews) {
        view.desiredOrigin = left;
        left += view.desiredWidth + iTermStatusBarViewControllerMargin;
    }
}

- (NSArray<iTermStatusBarContainerView *> *)visibleContainerViews {
    const CGFloat allowedWidth = self.view.frame.size.width;
    if (allowedWidth < iTermStatusBarViewControllerMargin * 2) {
        return @[];
    }

    NSArray<iTermStatusBarContainerView *> *prioritized = [_containerViews sortedArrayUsingComparator:^NSComparisonResult(iTermStatusBarContainerView * _Nonnull obj1, iTermStatusBarContainerView * _Nonnull obj2) {
        NSComparisonResult result = [@(obj1.component.statusBarComponentPriority) compare:@(obj2.component.statusBarComponentPriority)];
        if (result != NSOrderedSame) {
            return result;
        }

        NSInteger index1 = [self->_containerViews indexOfObject:obj1];
        NSInteger index2 = [self->_containerViews indexOfObject:obj2];
        return [@(index1) compare:@(index2)];
    }];
    CGFloat desiredWidth = [self minimumWidthOfContainerViews:prioritized];
    while (desiredWidth > allowedWidth) {
        prioritized = [prioritized arrayByRemovingLastObject];
        desiredWidth = [self minimumWidthOfContainerViews:prioritized];
    }

    // Preserve original order
    return [_containerViews filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *anObject) {
        return [prioritized containsObject:anObject];
    }];
}

- (CGFloat)minimumWidthOfContainerViews:(NSArray<iTermStatusBarContainerView *> *)views {
    NSNumber *sumOfMinimumWidths = [views reduceWithFirstValue:@0 block:^id(NSNumber *sum, iTermStatusBarContainerView *containerView) {
        return @(sum.doubleValue + containerView.component.statusBarComponentMinimumWidth);
    }];
    const NSInteger numberOfViews = views.count;
    return sumOfMinimumWidths.doubleValue + iTermStatusBarViewControllerMargin * (numberOfViews + 1);
}

- (iTermStatusBarContainerView *)containerViewForComponent:(id<iTermStatusBarComponent>)component {
    return [_containerViews objectPassingTest:^BOOL(iTermStatusBarContainerView *containerView, NSUInteger index, BOOL *stop) {
        return [containerView.component isEqualToComponent:component];
    }];
}

- (void)updateViews {
    NSMutableArray<iTermStatusBarContainerView *> *updatedContainerViews = [NSMutableArray array];
    for (id<iTermStatusBarComponent> component in _layout.components) {
        iTermStatusBarContainerView *view = [self containerViewForComponent:component];
        if (view) {
            [_containerViews removeObject:view];
        } else {
            view = [[iTermStatusBarContainerView alloc] initWithComponent:component];
        }
        [updatedContainerViews addObject:view];
    }
    _containerViews = updatedContainerViews;
    [self.view setNeedsLayout:YES];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [super encodeWithCoder:aCoder];
    [aCoder encodeObject:_layout forKey:@"layout"];
}

#pragma mark - iTermStatusBarLayoutDelegate

- (void)statusBarLayoutDidChange:(iTermStatusBarLayout *)layout {
    [self updateViews];
}

@end

NS_ASSUME_NONNULL_END
