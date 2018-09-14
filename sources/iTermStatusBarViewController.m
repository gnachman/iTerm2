//
//  iTermStatusBarViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import "iTermStatusBarViewController.h"

#import "DebugLogging.h"
#import "iTermStatusBarContainerView.h"
#import "iTermStatusBarFixedSpacerComponent.h"
#import "iTermStatusBarLayout.h"
#import "iTermStatusBarSpringComponent.h"
#import "iTermStatusBarView.h"
#import "NSArray+iTerm.h"
#import "NSImageView+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTimer+iTerm.h"
#import "NSView+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

static const CGFloat iTermStatusBarViewControllerMargin = 10;
static const CGFloat iTermStatusBarViewControllerBottomMargin = 1;
static const CGFloat iTermStatusBarViewControllerContainerHeight = 21;

// NOTE: SessionView's kTitleHeight must equal this value
const CGFloat iTermStatusBarHeight = 22;

@interface iTermStatusBarViewController ()<
    iTermStatusBarComponentDelegate,
    iTermStatusBarLayoutDelegate>

@end

@implementation iTermStatusBarViewController {
    NSMutableArray<iTermStatusBarContainerView *> *_containerViews;
    NSArray<iTermStatusBarContainerView *> *_visibleContainerViews;
    NSInteger _updating;
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
    iTermStatusBarView *view = [[iTermStatusBarView alloc] initWithFrame:NSZeroRect];
    view.separatorColor = _layout.advancedConfiguration.separatorColor;
    view.backgroundColor = _layout.advancedConfiguration.backgroundColor;
    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self updateViews];
}

- (void)viewWillLayout {
    NSArray<iTermStatusBarContainerView *> *previouslyVisible = _visibleContainerViews.copy;
    _visibleContainerViews = [self visibleContainerViews];
    DLog(@"--- begin status bar layout ---");
    [self updateDesiredWidths];
    [self updateDesiredOrigins];

    _updating++;
    [_visibleContainerViews enumerateObjectsUsingBlock:
     ^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
         view.frame = NSMakeRect(view.desiredOrigin,
                                 iTermStatusBarViewControllerBottomMargin,
                                 view.desiredWidth,
                                 iTermStatusBarViewControllerContainerHeight);
         [view layoutSubviews];
         [view.component statusBarComponentWidthDidChangeTo:view.desiredWidth];
         view.rightSeparatorOffset = -1;
     }];
    _updating--;
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
    iTermStatusBarView *view = (iTermStatusBarView *)self.view;
    __block BOOL haveFoundNonSpacer = NO;
    __block NSColor *lastColor = nil;
    __block NSNumber *lastFixedSpacerOffset = nil;
    __block iTermStatusBarContainerView *previousObject = nil;
    view.separatorOffsets = [[_visibleContainerViews flatMapWithBlock:^id(iTermStatusBarContainerView *anObject) {
        const BOOL isSpring = [anObject.component isKindOfClass:[iTermStatusBarSpringComponent class]];
        const CGFloat margin = isSpring ? 0 : iTermStatusBarViewControllerMargin / 2.0;
        NSNumber *offset = @(anObject.desiredOrigin + anObject.desiredWidth + margin);
        if ([anObject.component isKindOfClass:[iTermStatusBarFixedSpacerComponent class]]) {
            lastFixedSpacerOffset = offset;
            previousObject = anObject;
            return nil;
        } else if (lastFixedSpacerOffset && haveFoundNonSpacer) {
            haveFoundNonSpacer = YES;
            previousObject.rightSeparatorOffset = lastFixedSpacerOffset.doubleValue;
            anObject.rightSeparatorOffset = offset.doubleValue;
            previousObject = anObject;
            NSArray *result = @[ lastFixedSpacerOffset, offset ];
            lastFixedSpacerOffset = nil;
            lastColor = nil;
            return result;
        } else {
            haveFoundNonSpacer = YES;
            anObject.rightSeparatorOffset = offset.doubleValue;
            lastFixedSpacerOffset = nil;
            previousObject = anObject;
            lastColor = anObject.backgroundColor;
            return @[ offset ];
        }
    }] uniqWithComparator:^BOOL(NSNumber *obj1, NSNumber *obj2) {
        return [obj1 isEqual:obj2];
    }];

    lastColor = nil;
    __block NSNumber *lastOffset = nil;
    view.backgroundColors = [_visibleContainerViews mapWithBlock:^id(iTermStatusBarContainerView *containerView) {
        NSColor *color = containerView.backgroundColor;
        const BOOL isSpring = [containerView.component isKindOfClass:[iTermStatusBarSpringComponent class]];
        const CGFloat margin = isSpring ? 0 : iTermStatusBarViewControllerMargin / 2.0;
        NSNumber *offset = @(containerView.desiredOrigin + containerView.desiredWidth + margin + 0.5);
        iTermTuple *result = nil;
        result = [iTermTuple tupleWithObject:lastColor andObject:lastOffset];
        lastColor = color;
        lastOffset = offset;
        return result;
    }];
    if (lastColor) {
        view.backgroundColors = [view.backgroundColors arrayByAddingObject:[iTermTuple tupleWithObject:lastColor andObject:lastOffset]];
    }

    [view setNeedsDisplay:YES];
    DLog(@"--- end status bar layout ---");
}

- (void)setTemporaryLeftComponent:(nullable id<iTermStatusBarComponent>)temporaryLeftComponent {
    _temporaryLeftComponent = temporaryLeftComponent;
    [self updateViews];
    [self.view layoutSubtreeIfNeeded];
}

- (void)setTemporaryRightComponent:(nullable id<iTermStatusBarComponent>)temporaryRightComponent {
    _temporaryRightComponent = temporaryRightComponent;
    [self updateViews];
    [self.view layoutSubtreeIfNeeded];
}

- (void)variablesDidChange:(NSSet<NSString *> *)names {
    [_layout.components enumerateObjectsUsingBlock:^(id<iTermStatusBarComponent> _Nonnull component, NSUInteger idx, BOOL * _Nonnull stop) {
        NSSet<NSString *> *dependencies = [component statusBarComponentVariableDependencies];
        if ([dependencies intersectsSet:names]) {
            [component statusBarComponentVariablesDidChange:names];
        }
    }];
}

- (NSViewController<iTermFindViewController> *)searchViewController {
    return [_containerViews mapWithBlock:^id(iTermStatusBarContainerView *containerView) {
        return containerView.component.statusBarComponentSearchViewController;
    }].firstObject;
}

#pragma mark - Private

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

- (void)updateDesiredWidths {
    [self updateMargins:_visibleContainerViews];
    
     const CGFloat totalMarginWidth = [[_visibleContainerViews reduceWithFirstValue:@0 block:^NSNumber *(NSNumber *sum, iTermStatusBarContainerView *view) {
        return @(sum.doubleValue + view.leftMargin + view.rightMargin);
    }] doubleValue];
     
    __block CGFloat availableWidth = self.view.frame.size.width - totalMarginWidth;
    DLog(@"updateDesiredWidths available=%@", @(availableWidth));
    // Allocate minimum widths
    [_visibleContainerViews enumerateObjectsUsingBlock:^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
        view.desiredWidth = view.component.statusBarComponentMinimumWidth;
        if (view.component.statusBarComponentIcon) {
            view.desiredWidth = view.desiredWidth + iTermStatusBarViewControllerIconWidth;
        }
        availableWidth -= view.desiredWidth;
    }];
    DLog(@"updateDesiredWidths after assigning minimums: available=%@", @(availableWidth));

    if (availableWidth < 1) {
        return;
    }

    // Find views that can grow
    NSArray<iTermStatusBarContainerView *> *views = [_visibleContainerViews filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *view) {
        return ([view.component statusBarComponentCanStretch] &&
                floor(view.component.statusBarComponentPreferredWidth) > floor(view.desiredWidth));
    }];


    while (views.count) {
        double sumOfSpringConstants = [[views reduceWithFirstValue:@0 block:^NSNumber *(NSNumber *sum, iTermStatusBarContainerView *containerView) {
            if (![containerView.component statusBarComponentCanStretch]) {
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
            double delta = floor(availableWidth * weight);
            const double maximum = view.component.statusBarComponentPreferredWidth + (view.component.statusBarComponentIcon ? iTermStatusBarViewControllerIconWidth : 0);
            const double proposed = view.desiredWidth + delta;
            const double overage = floor(MAX(0, proposed - maximum));
            delta -= overage;
            view.desiredWidth += delta;
            growth += delta;
            DLog(@"  grow %@ by %@ to %@. Its preferred width is %@", view.component, @(delta), @(view.desiredWidth), @(view.component.statusBarComponentPreferredWidth));
        }];
        availableWidth -= growth;
        DLog(@"updateDesiredWidths after divvying: available = %@", @(availableWidth));

        if (availableWidth < 1) {
            return;
        }

        const NSInteger numberBefore = views.count;
        // Remove satisifed views.
        views = [views filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *view) {
            const BOOL unsatisfied = floor(view.component.statusBarComponentPreferredWidth) > ceil(view.desiredWidth);
            if (unsatisfied) {
                DLog(@"%@ unsatisfied prefers=%@ allocated=%@", view.component.class, @(view.component.statusBarComponentPreferredWidth), @(view.desiredWidth));
            }
            return unsatisfied;
        }];
        if (growth < 1 && views.count == numberBefore) {
            DLog(@"Stopping. growth=%@ views %@->%@", @(growth), @(views.count), @(numberBefore));
            return;
        }
    }
}

- (void)updateDesiredOrigins {
    CGFloat x = 0;
    for (iTermStatusBarContainerView *container in _visibleContainerViews) {
        x += container.leftMargin;
        container.desiredOrigin = x;
        x += container.desiredWidth;
        x += container.rightMargin;
    }
}

- (NSArray<iTermStatusBarContainerView *> *)visibleContainerViews {
    const CGFloat allowedWidth = self.view.frame.size.width;
    if (allowedWidth < iTermStatusBarViewControllerMargin * 2) {
        return @[];
    }

    NSMutableArray<iTermStatusBarContainerView *> *prioritized = [_containerViews sortedArrayUsingComparator:^NSComparisonResult(iTermStatusBarContainerView * _Nonnull obj1, iTermStatusBarContainerView * _Nonnull obj2) {
        NSComparisonResult result = [@(obj2.component.statusBarComponentPriority) compare:@(obj1.component.statusBarComponentPriority)];
        if (result != NSOrderedSame) {
            return result;
        }

        NSInteger index1 = [self->_containerViews indexOfObject:obj1];
        NSInteger index2 = [self->_containerViews indexOfObject:obj2];
        return [@(index1) compare:@(index2)];
    }].mutableCopy;
    NSMutableArray<iTermStatusBarContainerView *> *prioritizedNonzerominimum = [prioritized filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *anObject) {
        return anObject.component.statusBarComponentMinimumWidth > 0 || anObject.component.statusBarComponentIcon != nil;
    }].mutableCopy;
    CGFloat desiredWidth = [self minimumWidthOfContainerViews:prioritized];
    while (desiredWidth > allowedWidth && allowedWidth >= 0) {
        iTermStatusBarContainerView *viewToRemove = prioritizedNonzerominimum.lastObject;
        [prioritized removeObject:viewToRemove];
        [prioritizedNonzerominimum removeObject:viewToRemove];
        desiredWidth = [self minimumWidthOfContainerViews:prioritizedNonzerominimum];
    }

    // Preserve original order
    return [_containerViews filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *anObject) {
        return [prioritized containsObject:anObject];
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

- (iTermStatusBarContainerView *)containerViewForComponent:(id<iTermStatusBarComponent>)component {
    return [_containerViews objectPassingTest:^BOOL(iTermStatusBarContainerView *containerView, NSUInteger index, BOOL *stop) {
        return [containerView.component isEqualToComponent:component];
    }];
}

- (void)updateViews {
    NSMutableArray<iTermStatusBarContainerView *> *updatedContainerViews = [NSMutableArray array];
    NSMutableArray<id<iTermStatusBarComponent>> *components = [_layout.components mutableCopy];
    if (_temporaryLeftComponent) {
        [components insertObject:_temporaryLeftComponent atIndex:0];
    }
    if (_temporaryRightComponent) {
        iTermStatusBarSpringComponent *spring = [iTermStatusBarSpringComponent springComponentWithCompressionResistance:1];
        [components addObject:spring];
        [components addObject:_temporaryRightComponent];
    }
    for (id<iTermStatusBarComponent> component in components) {
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
    [self updateColors];
    [self.view setNeedsLayout:YES];
}

- (void)updateColors {
    for (iTermStatusBarContainerView *view in _containerViews) {
        [view.iconImageView it_setTintColor:[view.component statusBarTextColor] ?: [self statusBarComponentDefaultTextColor]];
        [view.component statusBarDefaultTextColorDidChange];
        [view setNeedsDisplay:YES];
    }
    [[iTermStatusBarView castFrom:self.view] setSeparatorColor:[self.delegate statusBarSeparatorColor]];
    [[iTermStatusBarView castFrom:self.view] setBackgroundColor:[self.delegate statusBarBackgroundColor]];
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
    DLog(@"Preferred size did change for %@", component);
    if (_updating) {
        DLog(@"Igoring size change because am updating");
        return;
    }
    [self.view setNeedsLayout:YES];
}

- (NSColor *)statusBarComponentDefaultTextColor {
    return [self.delegate statusBarDefaultTextColor];
}

@end

NS_ASSUME_NONNULL_END
