//
//  iTermStatusBarViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import "iTermStatusBarViewController.h"

#import "DebugLogging.h"
#import "iTermStatusBarAutoRainbowController.h"
#import "iTermStatusBarFixedSpacerComponent.h"
#import "iTermStatusBarLayout.h"
#import "iTermStatusBarLayoutAlgorithm.h"
#import "iTermStatusBarPlaceholderComponent.h"
#import "iTermStatusBarSpringComponent.h"
#import "iTermStatusBarUnreadCountController.h"
#import "iTermStatusBarView.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSImageView+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTimer+iTerm.h"
#import "NSView+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

static const CGFloat iTermStatusBarViewControllerBottomMargin = 0;

@interface iTermStatusBarViewController ()<
    iTermStatusBarComponentDelegate,
    iTermStatusBarContainerViewDelegate,
    iTermStatusBarLayoutDelegate>

@end

@interface iTermStatusBarViewController()<iTermStatusBarAutoRainbowControllerDelegate>
@end

@implementation iTermStatusBarViewController {
    NSMutableArray<iTermStatusBarContainerView *> *_containerViews;
    NSArray<iTermStatusBarContainerView *> *_visibleContainerViews;
    NSInteger _updating;
    BOOL _makeSearchControllerFirstResponder;
    iTermStatusBarAutoRainbowController *_autoRainbowController;
}

- (instancetype)initWithLayout:(iTermStatusBarLayout *)layout
                         scope:(nonnull iTermVariableScope *)scope {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _scope = scope;
        _layout = layout;
        _autoRainbowController = [[iTermStatusBarAutoRainbowController alloc] initWithStyle:layout.advancedConfiguration.autoRainbowStyle];
        _autoRainbowController.delegate = self;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(unreadCountDidChange:)
                                                     name:iTermStatusBarUnreadCountDidChange
                                                   object:nil];
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

- (NSArray<id<iTermStatusBarComponent>> *)visibleComponents {
    return [_visibleContainerViews mapWithBlock:^id(iTermStatusBarContainerView *view) {
        return view.component;
    }];
}

- (nullable iTermStatusBarContainerView *)mandatoryView {
    if (!self.mustShowSearchComponent) {
        return nil;
    }
    return [_containerViews objectPassingTest:^BOOL(iTermStatusBarContainerView *containerView, NSUInteger index, BOOL *stop) {
        return containerView.component.statusBarComponentSearchViewController != nil;
    }];
}

- (iTermStatusBarLayoutAlgorithm *)layoutAlgorithm {
    return [iTermStatusBarLayoutAlgorithm layoutAlgorithmWithContainerViews:_containerViews
                                                              mandatoryView:self.mandatoryView
                                                             statusBarWidth:self.view.frame.size.width
                                                                    setting:_layout.advancedConfiguration.layoutAlgorithm
                                                      removeEmptyComponents:_layout.advancedConfiguration.removeEmptyComponents];
}

- (NSArray<NSNumber *> *)desiredSeparatorOffsets {
    NSMutableArray<NSNumber *> *offsets = [NSMutableArray array];
    BOOL haveFoundNonSpacer = NO;
    NSNumber *lastFixedSpacerOffset = nil;
    iTermStatusBarContainerView *previousObject = nil;
    for (iTermStatusBarContainerView *anObject in [_visibleContainerViews it_arrayByDroppingLastN:1]) {
        const BOOL isSpring = [anObject.component isKindOfClass:[iTermStatusBarSpringComponent class]];
        const CGFloat margin = isSpring ? 0 : iTermStatusBarViewControllerMargin / 2.0;
        NSNumber *offset = @(anObject.desiredOrigin + anObject.desiredWidth + margin);
        if ([anObject.component isKindOfClass:[iTermStatusBarFixedSpacerComponent class]]) {
            // Consecutive fixed spacers do not get separators. Rather than adding a separator
            // just record that we saw a fixed spacer and add the separator if we see a
            // subsequent non-spacer.
            lastFixedSpacerOffset = offset;
            previousObject = anObject;
            continue;
        }

        if (lastFixedSpacerOffset && haveFoundNonSpacer) {
            // This is a non-spacer following a spacer, but not the very first non-spacer.
            // That second clause is to prevent adding a separator between the spacer and nonspacer
            // in this example:
            //     |[spacer][nonspacer]:[whatever]|
            // While we do want separators here here (referring to the second separator, obvs):
            //     |[nonspacer]:[spacer]:[nonspacer]
            // Add a divider after the previous spacer.
            [offsets addObject:lastFixedSpacerOffset];
            previousObject.rightSeparatorOffset = lastFixedSpacerOffset.doubleValue;
            lastFixedSpacerOffset = nil;

            // And add a spacer after this object.
            haveFoundNonSpacer = YES;
            anObject.rightSeparatorOffset = offset.doubleValue;
            previousObject = anObject;
            [offsets addObject:offset];
            continue;
        }

        // Normal case: add a separator after this component
        anObject.rightSeparatorOffset = offset.doubleValue;
        [offsets addObject:offset];
    }
    return [offsets uniq];
}

- (NSArray<iTermTuple<NSColor *, NSNumber *> *> *)desiredBackgroundColors {
    return [_visibleContainerViews mapWithBlock:^id(iTermStatusBarContainerView *containerView) {
        NSColor *color = containerView.backgroundColor;
        const BOOL isSpring = [containerView.component isKindOfClass:[iTermStatusBarSpringComponent class]];
        const CGFloat margin = isSpring ? 0 : iTermStatusBarViewControllerMargin / 2.0;
        NSNumber *offset = @(containerView.desiredOrigin + containerView.desiredWidth + margin + 0.5);
        return [iTermTuple tupleWithObject:color andObject:offset];
    }];
}

- (void)viewWillLayout {
    NSArray<iTermStatusBarContainerView *> *previouslyVisible = _visibleContainerViews.copy;
    DLog(@"--- begin status bar layout %@ ---", self);
    _visibleContainerViews = [self.layoutAlgorithm visibleContainerViews];
    [self updateDesiredOrigins];

    _updating++;
    [_visibleContainerViews enumerateObjectsUsingBlock:
     ^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
         view.frame = NSMakeRect(round(view.desiredOrigin),
                                 iTermStatusBarViewControllerBottomMargin,
                                 ceil(view.desiredWidth),
                                 iTermGetStatusBarHeight() - iTermStatusBarViewControllerBottomMargin);
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
    view.separatorOffsets = [self desiredSeparatorOffsets];

    view.backgroundColors = [self desiredBackgroundColors];

    [view setNeedsDisplay:YES];
    if (_makeSearchControllerFirstResponder) {
        [self.searchViewController open];
        _makeSearchControllerFirstResponder = NO;
    }
    [self updateAutoRainbowColorsIfNeeded];
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

- (NSViewController<iTermFindViewController> *)filterViewController {
    return [_containerViews mapWithBlock:^id(iTermStatusBarContainerView *containerView) {
        return containerView.component.statusBarComponentFilterViewController;
    }].firstObject;
}

- (void)setMustShowSearchComponent:(BOOL)mustShowSearchComponent {
    _mustShowSearchComponent = mustShowSearchComponent;
    _makeSearchControllerFirstResponder = mustShowSearchComponent;
    [self.view setNeedsLayout:YES];
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
    if (!components.count) {
        NSDictionary *placeholderConfiguration =
            @{iTermStatusBarComponentConfigurationKeyLayoutAdvancedConfigurationDictionaryValue: _layout.advancedConfiguration.dictionaryValue };
        [components addObject:[[iTermStatusBarPlaceholderComponent alloc] initWithConfiguration:placeholderConfiguration
                                                                                          scope:nil]];
    }
    for (id<iTermStatusBarComponent> component in components) {
        iTermStatusBarContainerView *view = [self containerViewForComponent:component];
        if (view) {
            [_containerViews removeObject:view];
        } else {
            view = [[iTermStatusBarContainerView alloc] initWithComponent:component];
            view.delegate = self;
        }
        [updatedContainerViews addObject:view];
    }
    _containerViews = updatedContainerViews;
    NSString *const sessionID = [_scope valueForVariableName:iTermVariableKeySessionID] ?: @"";

    [_containerViews enumerateObjectsUsingBlock:^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *identifier = view.component.statusBarComponentIdentifier;
        if (!identifier) {
            [view setUnreadCount:0];
            return;
        }
        [view setUnreadCount:[[iTermStatusBarUnreadCountController sharedInstance] unreadCountForComponentWithIdentifier:identifier
                                                                                                               sessionID:sessionID]];
    }];
    // setDelegate: may have side effects that expect _containerViews to be populated.
    for (id<iTermStatusBarComponent> component in components) {
        component.delegate = self;
    }
    [self updateColors];
    [self.view setNeedsLayout:YES];
}

- (void)updateColors {
    for (iTermStatusBarContainerView *view in _containerViews) {
        NSColor *tintColor = [view.component statusBarTextColor] ?: [self statusBarComponentDefaultTextColor];
        [view.iconImageView it_setTintColor:tintColor];
        [view.component statusBarDefaultTextColorDidChange];
        [view setNeedsDisplay:YES];
        [view.component statusBarTerminalBackgroundColorDidChange];
    }
    [[iTermStatusBarView castFrom:self.view] setSeparatorColor:[self.delegate statusBarSeparatorColor]];
    [[iTermStatusBarView castFrom:self.view] setBackgroundColor:[self.delegate statusBarBackgroundColor]];
    _autoRainbowController.darkBackground = [self.delegate statusBarHasDarkBackground];
    [self.delegate statusBarDidUpdate];
}

- (nullable id<iTermStatusBarComponent>)componentWithIdentifier:(NSString *)identifier {
    return [_containerViews objectPassingTest:^BOOL(iTermStatusBarContainerView *element, NSUInteger index, BOOL *stop) {
        return [element.component.statusBarComponentIdentifier isEqual:identifier];
    }].component;
}

- (nullable __kindof id<iTermStatusBarComponent>)visibleComponentWithIdentifier:(NSString *)identifier {
    return [_visibleContainerViews objectPassingTest:^BOOL(iTermStatusBarContainerView *element, NSUInteger index, BOOL *stop) {
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

- (void)statusBarComponentKnobsDidChange:(id<iTermStatusBarComponent>)component updatedKeys:(NSSet<NSString *> *)updatedKeys {
    // Shouldn't happen since this is not the setup UI
}

- (id<ProcessInfoProvider>)statusBarComponentProcessInfoProvider {
    return [self.delegate statusBarProcessInfoProvider];
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

- (NSColor *)statusBarComponentEffectiveBackgroundColor:(id<iTermStatusBarComponent>)component {
    iTermStatusBarContainerView *view = [self containerViewForComponent:component];
    if (!view) {
        return nil;
    }
    return view.backgroundColor ?: [self.delegate statusBarBackgroundColor];
}
- (void)statusBarComponent:(id<iTermStatusBarComponent>)component writeString:(NSString *)string {
    [self.delegate statusBarWriteString:string];
}

- (void)statusBarComponentOpenStatusBarPreferences:(id<iTermStatusBarComponent>)component {
    [self.delegate statusBarOpenPreferencesToComponent:nil];
}

- (void)statusBarComponentPerformAction:(iTermAction *)action {
    [self.delegate statusBarPerformAction:action];
}

- (void)statusBarComponentEditActions:(id<iTermStatusBarComponent>)component {
    [self.delegate statusBarEditActions];
}

- (void)statusBarComponentEditSnippets:(id<iTermStatusBarComponent>)component {
    [self.delegate statusBarEditSnippets];
}

- (void)statusBarComponentResignFirstResponder:(id<iTermStatusBarComponent>)component {
    [self.delegate statusBarResignFirstResponder];
}

- (void)statusBarComponentComposerRevealComposer:(id<iTermStatusBarComponent>)component {
    [self.delegate statusBarRevealComposer];
}

- (id<iTermTriggersDataSource>)statusBarComponentTriggersDataSource:(id<iTermStatusBarComponent>)component {
    return [self.delegate statusBarTriggersDataSource];
}

- (void)statusBarRemoveTemporaryComponent:(id<iTermStatusBarComponent>)component {
    if (self.temporaryLeftComponent == component) {
        self.temporaryLeftComponent = nil;
    }
    if (self.temporaryRightComponent == component) {
        self.temporaryRightComponent = nil;
    }
}

- (void)statusBarSetFilter:(NSString * _Nullable)query {
    [self.delegate statusBarSetFilter:query];
}

- (iTermActivityInfo)statusBarComponentActivityInfo:(id<iTermStatusBarComponent>)component {
    return [self.delegate statusBarActivityInfo];
}

- (void)statusBarComponent:(id<iTermStatusBarComponent>)component
      reportScriptingError:(NSError *)error
             forInvocation:(NSString *)invocation
                    origin:(NSString *)origin {
    [self.delegate statusBarReportScriptingError:error forInvocation:invocation origin:origin];
}


#pragma mark - iTermStatusBarContainerViewDelegate

- (void)statusBarContainerView:(iTermStatusBarContainerView *)sender hideComponent:(id<iTermStatusBarComponent>)component {
    iTermStatusBarLayout *layout = [[iTermStatusBarLayout alloc] initWithDictionary:[self.layout dictionaryValue]
                                                                              scope:_scope];
    layout.components = [layout.components it_arrayByRemovingObjectsPassingTest:^BOOL(id<iTermStatusBarComponent> anObject) {
        return [anObject isEqualToComponentIgnoringConfiguration:component];
    }];
    [self.delegate statusBarSetLayout:layout];
}

- (void)statusBarContainerViewDisableStatusBar:(iTermStatusBarContainerView *)sender {
    [self.delegate statusBarDisable];
}

- (BOOL)statusBarContainerViewCanDragWindow:(iTermStatusBarContainerView *)sender {
    return [self.delegate statusBarCanDragWindow];
}

- (void)statusBarContainerViewConfigureStatusBar:(iTermStatusBarContainerView *)sender {
    [self.delegate statusBarOpenPreferencesToComponent:nil];
}

- (void)statusBarContainerView:(iTermStatusBarContainerView *)sender configureComponent:(id<iTermStatusBarComponent>)component {
    [self.delegate statusBarOpenPreferencesToComponent:component];
}

#pragma mark - Notifications

- (void)unreadCountDidChange:(NSNotification *)notification {
    NSString *const sessionID = [_scope valueForVariableName:iTermVariableKeySessionID] ?: @"";
    [_containerViews enumerateObjectsUsingBlock:^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *identifier = view.component.statusBarComponentIdentifier;
        if (!identifier) {
            [view setUnreadCount:0];
            return;
        }
        if (![identifier isEqual:notification.object]) {
            return;
        }
        [view setUnreadCount:[[iTermStatusBarUnreadCountController sharedInstance] unreadCountForComponentWithIdentifier:identifier
                                                                                                               sessionID:sessionID]];
    }];
}

#pragma mark - iTermStatusBarAutoRainbowControllerDelegate

- (void)autoRainbowControllerDidInvalidateColors:(iTermStatusBarAutoRainbowController *)controller {
    [self updateAutoRainbowColorsIfNeeded];
}

- (void)updateAutoRainbowColorsIfNeeded {
    if (_autoRainbowController.style == iTermStatusBarAutoRainbowStyleDisabled) {
        return;
    }
    [_autoRainbowController enumerateColorsWithCount:_visibleContainerViews.count block:^(NSInteger i, NSColor * _Nonnull color) {
        id<iTermStatusBarComponent> component = _visibleContainerViews[i].component;
        NSMutableDictionary *knobValues = [component.configuration[iTermStatusBarComponentConfigurationKeyKnobValues] mutableCopy];
        NSDictionary *colorDict = [color dictionaryValue];
        if ([knobValues[iTermStatusBarSharedTextColorKey] isEqualToDictionary:colorDict]) {
            return;
        }
        knobValues[iTermStatusBarSharedTextColorKey] = colorDict;
        [component statusBarComponentSetKnobValues:knobValues];
    }];
}

@end

NS_ASSUME_NONNULL_END
