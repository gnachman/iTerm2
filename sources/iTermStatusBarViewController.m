//
//  iTermStatusBarViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import "iTermStatusBarViewController.h"

#import "DebugLogging.h"
#import "iTermStatusBarContainerView.h"
#import "iTermStatusBarLayout.h"
#import "iTermStatusBarView.h"
#import "NSArray+iTerm.h"
#import "NSView+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

static const CGFloat iTermStatusBarViewControllerMargin = 5;
static const CGFloat iTermStatusBarViewControllerTopMargin = 2;
static const CGFloat iTermStatusBarViewControllerContainerHeight = 22;

@interface iTermStatusBarViewController ()<
    iTermStatusBarComponentDelegate,
    iTermStatusBarLayoutDelegate>

@end

@implementation iTermStatusBarViewController {
    NSMutableArray<iTermStatusBarContainerView *> *_containerViews;
    NSArray<iTermStatusBarContainerView *> *_visibleContainerViews;
}

- (instancetype)initWithLayout:(iTermStatusBarLayout *)layout
                         scope:(nonnull iTermVariableScope *)scope {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _scope = scope;
        _layout = layout;
        for (id<iTermStatusBarComponent> component in layout.components) {
            [component statusBarComponentSetVariableScope:scope];
        }
    }
    return self;
}

- (void)loadView {
    self.view = [[iTermStatusBarView alloc] initWithFrame:NSZeroRect];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self updateViews];
}

- (void)viewWillLayout {
    NSArray<iTermStatusBarContainerView *> *previouslyVisible = _visibleContainerViews.copy;
    _visibleContainerViews = [self visibleContainerViews];
    [self updateDesiredWidths];
    [self updateDesiredOrigins];

    [_visibleContainerViews enumerateObjectsUsingBlock:
     ^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
         view.frame = NSMakeRect(view.desiredOrigin,
                                 iTermStatusBarViewControllerTopMargin,
                                 view.desiredWidth,
                                 iTermStatusBarViewControllerContainerHeight);
     }];
    // Remove defunct views
    for (iTermStatusBarContainerView *view in previouslyVisible) {
        if (![_visibleContainerViews containsObject:view]) {
            [view removeFromSuperview];
        }
    }
    // Add new views
    for (iTermStatusBarContainerView *view in _visibleContainerViews) {
        if (view.superview != self.view) {
            [self.view addSubview:view];
        }
    }
}

- (void)variablesDidChange:(NSSet<NSString *> *)names {
    [_layout.components enumerateObjectsUsingBlock:^(id<iTermStatusBarComponent> _Nonnull component, NSUInteger idx, BOOL * _Nonnull stop) {
        NSSet<NSString *> *dependencies = [component statusBarComponentVariableDependencies];
        if ([dependencies intersectsSet:names]) {
            [component statusBarComponentVariablesDidChange:names];
        }
    }];
}

#pragma mark - Private

- (void)updateDesiredWidths {
    const CGFloat totalMarginWidth = (_containerViews.count + 2) * iTermStatusBarViewControllerMargin;
    __block CGFloat availableWidth = self.view.frame.size.width - totalMarginWidth;

    DLog(@"updateDesiredWidths available=%@", @(availableWidth));
    // Allocate minimum widths
    [_containerViews enumerateObjectsUsingBlock:^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
        view.desiredWidth = view.component.statusBarComponentMinimumWidth;
        availableWidth -= view.desiredWidth;
    }];
    DLog(@"updateDesiredWidths after assigning minimums: available=%@", @(availableWidth));

    if (availableWidth < 1) {
        return;
    }

    // Find views that can grow
    NSArray<iTermStatusBarContainerView *> *views = [_containerViews filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *view) {
        return (view.component.statusBarComponentCanStretch &&
                view.component.statusBarComponentPreferredWidth > view.desiredWidth);
    }];


    while (1) {
        double sumOfSpringConstants = [[views reduceWithFirstValue:@0 block:^NSNumber *(NSNumber *sum, iTermStatusBarContainerView *containerView) {
            if (!containerView.component.statusBarComponentCanStretch) {
                return sum;
            }
            return @(sum.doubleValue + containerView.component.statusBarComponentSpringConstant);
        }] doubleValue];

        DLog(@"updateDesiredWidths have %@ views that can grow: available=%@",
              @(views.count), @(availableWidth));

        __block double growth = 0;
        // Divvy up space proportionate to spring constants.
        [views enumerateObjectsUsingBlock:^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
            const double weight = view.component.statusBarComponentSpringConstant / sumOfSpringConstants;
            double delta = availableWidth * weight;
            const double maximum = view.component.statusBarComponentPreferredWidth;
            const double proposed = view.desiredWidth + delta;
            const double overage = MAX(0, proposed - maximum);
            delta -= overage;
            view.desiredWidth += delta;
            growth += delta;
            DLog(@"  grow %@ by %@ to %@", view, @(delta), @(view.desiredWidth));
        }];
        availableWidth -= growth;
        NSLog(@"updateDesiredWidths after divvying: available = %@", @(availableWidth));

        if (availableWidth < 1) {
            return;
        }

        // Remove satisifed views.
        views = [views filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *view) {
            return view.component.statusBarComponentPreferredWidth > view.desiredWidth;
        }];
    }
}

- (void)updateDesiredOrigins {
    CGFloat x = iTermStatusBarViewControllerMargin;
    for (iTermStatusBarContainerView *container in _containerViews) {
        container.desiredOrigin = x;
        x += container.desiredWidth;
        x += iTermStatusBarViewControllerMargin;
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
        component.delegate = self;
        [updatedContainerViews addObject:view];
    }
    _containerViews = updatedContainerViews;
    [self.view setNeedsLayout:YES];
}

#pragma mark - iTermStatusBarLayoutDelegate

- (void)statusBarLayoutDidChange:(iTermStatusBarLayout *)layout {
    [self updateViews];
}

#pragma mark - iTermStatusBarComponentDelegate

- (BOOL)statusBarComponentIsInSetupUI:(id<iTermStatusBarComponent>)component {
    return NO;
}

- (void)statusBarComponentKnobsDidChange:(id<iTermStatusBarComponent>)component {
    // Shouldn't happen since this is not the setup UI
}

- (void)statusBarComponentPreferredSizeDidChange:(id<iTermStatusBarComponent>)component {
    [self.view setNeedsLayout:YES];
}

@end

NS_ASSUME_NONNULL_END
