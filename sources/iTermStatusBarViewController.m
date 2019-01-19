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
#import "iTermStatusBarLayoutAlgorithm.h"
#import "iTermStatusBarSpringComponent.h"
#import "iTermStatusBarView.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSImageView+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTimer+iTerm.h"
#import "NSView+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

static const CGFloat iTermStatusBarViewControllerBottomMargin = 0;
static const CGFloat iTermStatusBarViewControllerContainerHeight = 21;

const CGFloat iTermStatusBarHeight = 21;

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

- (iTermStatusBarLayoutAlgorithm *)layoutAlgorithm {
    return [[iTermStatusBarLayoutAlgorithm alloc] initWithContainerViews:_containerViews
                                                          statusBarWidth:self.view.frame.size.width];
}

- (void)viewWillLayout {
    NSArray<iTermStatusBarContainerView *> *previouslyVisible = _visibleContainerViews.copy;
    DLog(@"--- begin status bar layout %@ ---", self);
    _visibleContainerViews = [self.layoutAlgorithm visibleContainerViews];
    [self updateDesiredOrigins];

    _updating++;
    [_visibleContainerViews enumerateObjectsUsingBlock:
     ^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
         view.frame = NSMakeRect(view.desiredOrigin,
                                 iTermStatusBarViewControllerBottomMargin,
                                 view.desiredWidth,
                                 iTermStatusBarViewControllerContainerHeight);
         [view.component statusBarComponentWidthDidChangeTo:view.desiredWidth];
         [view layoutSubviews];
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

- (NSViewController<iTermFindViewController> *)searchViewController {
    return [_containerViews mapWithBlock:^id(iTermStatusBarContainerView *containerView) {
        return containerView.component.statusBarComponentSearchViewController;
    }].firstObject;
}

#pragma mark - Private

- (void)updateDesiredOrigins {
    CGFloat x = 0;
    for (iTermStatusBarContainerView *container in _visibleContainerViews) {
        x += container.leftMargin;
        container.desiredOrigin = x;
        x += container.desiredWidth;
        x += container.rightMargin;
    }
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
        [updatedContainerViews addObject:view];
    }
    _containerViews = updatedContainerViews;
    // setDelegate: may have side effects that expect _containerViews to be populated.
    for (id<iTermStatusBarComponent> component in components) {
        component.delegate = self;
    }
    [self updateColors];
    [self.view setNeedsLayout:YES];
}

- (void)updateColors {
    for (iTermStatusBarContainerView *view in _containerViews) {
        [view.iconImageView it_setTintColor:[view.component statusBarTextColor] ?: [self statusBarComponentDefaultTextColor]];
        [view.component statusBarDefaultTextColorDidChange];
        [view setNeedsDisplay:YES];
        [view.component statusBarTerminalBackgroundColorDidChange];
    }
    [[iTermStatusBarView castFrom:self.view] setSeparatorColor:[self.delegate statusBarSeparatorColor]];
    [[iTermStatusBarView castFrom:self.view] setBackgroundColor:[self.delegate statusBarBackgroundColor]];
    [self.delegate statusBarDidUpdate];
}

- (nullable id<iTermStatusBarComponent>)componentWithIdentifier:(NSString *)identifier {
    return [_containerViews objectPassingTest:^BOOL(iTermStatusBarContainerView *element, NSUInteger index, BOOL *stop) {
        return [element.component.statusBarComponentIdentifier isEqual:identifier];
    }].component;
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
        DLog(@"Ignoring size change because am updating");
        return;
    }
    [self.view setNeedsLayout:YES];
}

- (NSColor *)statusBarComponentDefaultTextColor {
    return [self.delegate statusBarDefaultTextColor];
}

- (BOOL)statusBarComponentIsVisible:(id<iTermStatusBarComponent>)component {
    return self.view.window != nil && !self.view.isHidden;
}

- (NSFont *)statusBarComponentTerminalFont:(id<iTermStatusBarComponent>)component {
    return [self.delegate statusBarTerminalFont];
}

- (BOOL)statusBarComponentTerminalBackgroundColorIsDark:(id<iTermStatusBarComponent>)component {
    return [[self.delegate statusBarTerminalBackgroundColor] perceivedBrightness] < 0.5;
}

- (void)statusBarComponent:(id<iTermStatusBarComponent>)component writeString:(NSString *)string {
    [self.delegate statusBarWriteString:string];
}

@end

NS_ASSUME_NONNULL_END
