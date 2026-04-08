//
//  iTermTabBarControlView.m
//  iTerm
//
//  Created by George Nachman on 5/29/14.
//
//

#import "iTermTabBarControlView.h"

#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermPreferences.h"
#import "DebugLogging.h"
#import "NSObject+iTerm.h"
#import "NSView+iTerm.h"
#import "NSWindow+iTerm.h"
#import "PTYTab.h"
#import "SessionView.h"

@interface NSView (Private2)
- (NSRect)_opaqueRectForWindowMoveWhenInTitlebar;
@end

typedef NS_ENUM(NSInteger, iTermTabBarFlashState) {
    kFlashOff,
    kFlashHolding,  // Regular delay
    kFlashExtending,  // Staying on because cmd pressed
    kFlashFadingOut,
};

@interface PSMTabBarControl (iTermTabBarControlViewPrivate)
- (NSMutableArray<PSMTabBarCell *> *)cells;
- (void)update:(BOOL)animate;
@end

@interface iTermTabBarControlView ()
@property(nonatomic, assign) iTermTabBarFlashState flashState;
@end

@implementation iTermTabBarControlView {
    iTermDelayedPerform *_flashDelayedPerform;  // weak
    NSMutableDictionary<NSValue *, iTermProgressBarView *> *_tabProgressBars;
}

static const CGFloat iTermTabProgressBarHeight = 2;

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _tabProgressBars = [[NSMutableDictionary alloc] init];
        [self setTabsHaveCloseButtons:[iTermPreferences boolForKey:kPreferenceKeyTabsHaveCloseButton]];
        self.minimumTabDragDistance = [iTermAdvancedSettingsModel minimumTabDragDistance];
        // This used to depend on job but it's too difficult to do now that different sessions might
        // have different title formats.
        self.ignoreTrailingParentheticalsForSmartTruncation = YES;
        if (@available(macOS 26, *)) {
            if (![iTermAdvancedSettingsModel useSequoiaStyleTabs]) {
                self.height =  PSMTahoeTabStyle.horizontalTabBarHeight;
            } else {
                self.height = [iTermAdvancedSettingsModel defaultTabBarHeight];
            }
        } else {
            self.height = [iTermAdvancedSettingsModel defaultTabBarHeight];
        }
        self.showAddTabButton = ![iTermAdvancedSettingsModel removeAddTabButton];
        self.selectsTabsOnMouseDown = [iTermAdvancedSettingsModel selectsTabsOnMouseDown];
    }
    return self;
}

- (void)dealloc {
    for (iTermProgressBarView *progressBar in _tabProgressBars.allValues) {
        [progressBar removeFromSuperview];
    }
    [_tabProgressBars release];
    [super dealloc];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    [self syncTabProgressBars];
}

- (void)setCmdPressed:(BOOL)cmdPressed {
    if (cmdPressed == _cmdPressed) {
        return;
    }
    _cmdPressed = cmdPressed;
    DLog(@"Set cmdPressed=%d", (int)cmdPressed);
    switch (self.flashState) {
        case kFlashOff:
            break;

        case kFlashHolding:
            break;

        case kFlashExtending:
            if (!cmdPressed) {
                [self setFlashing:NO];
            }
            break;

        case kFlashFadingOut:
            break;
    }
}

- (BOOL)flashing {
    return self.flashState != kFlashOff;
}

- (void)cancelFadeOut {
    // Cancel fade out so a new timer can be started below, in case we were already holding or
    // fading in.
    DLog(@"Cancel fade out %@", _flashDelayedPerform);
    _flashDelayedPerform.canceled = YES;
    _flashDelayedPerform = nil;
}

- (void)setAlphaValue:(CGFloat)alphaValue animated:(BOOL)animated {
    DLog(@"setAlphaValue:%@ animated:%@ (was %@) for %@\n%@",
         @(alphaValue),
         @(animated),
         @(self.alphaValue),
         self,
         [NSThread callStackSymbols]);
    if ([self.superview conformsToProtocol:@protocol(iTermTabBarControlViewContainer)]) {
        if (animated) {
            self.superview.animator.alphaValue = alphaValue;
        } else {
            self.superview.alphaValue = alphaValue;
        }
        [super setAlphaValue:1.0];
    } else {
        if (animated) {
            NSView *animator = self.animator;
            animator.alphaValue = alphaValue;
        } else {
            [self setAlphaValue:alphaValue];
        }
    }
}

- (void)setHidden:(BOOL)hidden {
    DLog(@"setHidden:%@ (was %@) for %@\n%@",
         @(hidden),
         @(self.isHidden),
         self,
         [NSThread callStackSymbols]);
    if (!hidden || [self.itermTabBarDelegate iTermTabBarShouldHideBacking]) {
        if ([self.superview conformsToProtocol:@protocol(iTermTabBarControlViewContainer)]) {
            id<iTermTabBarControlViewContainer> container = (id<iTermTabBarControlViewContainer>)self.superview;
            [container tabBarControlViewWillHide:hidden];
        }
    }
    [super setHidden:hidden];
}

- (void)setFrame:(NSRect)frame {
    DLog(@"setFrame:%@ (was %@) for %@\n%@",
         NSStringFromRect(frame),
         NSStringFromRect(self.frame),
         self,
         [NSThread callStackSymbols]);
    [super setFrame:frame];
    [self syncTabProgressBars];
}

- (void)fadeIn {
    DLog(@"fade in");
    self.flashState = kFlashHolding;
    [_itermTabBarDelegate iTermTabBarWillBeginFlash];
    [self setAlphaValue:1.0 animated:NO];
}

- (void)scheduleFadeOutAfterDelay {
    DLog(@"schedule fade out after delay");
    // Schedule a fade out. This can be canceled.
    [self retain];
    __block BOOL aborted = NO;
    _flashDelayedPerform = [NSView animateWithDuration:[iTermAdvancedSettingsModel tabFlashAnimationDuration]
                                                 delay:[iTermAdvancedSettingsModel tabAutoShowHoldTime]
                                            animations:^{
                                                if (!_cmdPressed) {
                                                    DLog(@"delayed fade out running");
                                                    self.flashState = kFlashFadingOut;
                                                    [self setAlphaValue:0 animated:YES];
                                                } else {
                                                    DLog(@"delayed fade out aborted; extending");
                                                    self.flashState = kFlashExtending;
                                                    aborted = YES;
                                                }
                                            }
                                            completion:^(BOOL finished) {
                                                if (!aborted) {
                                                    DLog(@"delayed fade out completed");
                                                    if (finished && self.flashState == kFlashFadingOut) {
                                                        self.flashState = kFlashOff;
                                                        [_itermTabBarDelegate iTermTabBarDidFinishFlash];
                                                    }
                                                }
                                                if (_flashDelayedPerform.completed) {
                                                    _flashDelayedPerform = nil;
                                                }
                                                [self release];
                                            }];
    DLog(@"Schedule dp %@", _flashDelayedPerform);
}

- (void)stopFlashInstantly {
    DLog(@"stop flashing instantly");
    // Quickly stop flash.
    [self setAlphaValue:1.0 animated:NO];
    self.flashState = kFlashOff;
    _flashDelayedPerform.canceled = YES;
    _flashDelayedPerform = nil;
    [_itermTabBarDelegate iTermTabBarDidFinishFlash];
}

- (void)fadeOut {
    DLog(@"fade out");
    // If there is a delayed perform to fade out, cancel that so we don't try to fade out twice.
    _flashDelayedPerform.canceled = YES;
    _flashDelayedPerform = nil;

    [self retain];
    [NSView animateWithDuration:[iTermAdvancedSettingsModel tabFlashAnimationDuration]
                     animations:^{
                         self.flashState = kFlashFadingOut;
                         [self setAlphaValue:0 animated:YES];
                     }
                     completion:^(BOOL finished) {
                         if (finished && self.flashState == kFlashFadingOut) {
                             self.flashState = kFlashOff;
                             [_itermTabBarDelegate iTermTabBarDidFinishFlash];
                         }
                         [self release];
                     }];
}

- (void)setFlashing:(BOOL)flashing {
    flashing &= [_itermTabBarDelegate iTermTabBarShouldFlashAutomatically];
    DLog(@"Set flashing to %d", (int)flashing);
    if (flashing) {
        switch (self.flashState) {
            case kFlashOff:
            case kFlashFadingOut:
                [self fadeIn];
                [self cancelFadeOut];
                [self scheduleFadeOutAfterDelay];
                break;

            case kFlashHolding:
                // Restart the timer.
                [self cancelFadeOut];
                [self scheduleFadeOutAfterDelay];
                break;

            case kFlashExtending:
                break;
        }
    } else {
        switch (self.flashState) {
            case kFlashOff:
                break;

            case kFlashHolding:
            case kFlashExtending:
                [self fadeOut];
                break;

            case kFlashFadingOut:
                [self stopFlashInstantly];
                break;
        }
    }
}

- (void)updateFlashing {
    if ([self flashing] &&
        ![_itermTabBarDelegate iTermTabBarShouldFlashAutomatically]) {
        [self setFlashing:NO];
    }
}

- (void)setOrientation:(PSMTabBarOrientation)orientation {
    [super setOrientation:orientation];
    if (@available(macOS 26, *)) {
        self.style.orientation = self.orientation;
        CGFloat tabBarHeight = self.style.tabBarHeight;
        if (tabBarHeight <= 0) {
            tabBarHeight = [self.delegate tabViewDesiredTabBarHeight:self.tabView];
        }
        self.height = tabBarHeight;
    }
    self.showAddTabButton = ![iTermAdvancedSettingsModel removeAddTabButton] && (orientation == PSMTabBarHorizontalOrientation);
    [self syncTabProgressBars];
}

- (void)update:(BOOL)animate {
    [super update:animate];
    [self syncTabProgressBars];
}

- (void)setProgress:(PSMProgress)progress forTabWithIdentifier:(id)identifier {
    [super setProgress:progress forTabWithIdentifier:identifier];
    [self syncTabProgressBars];
}

- (void)removeTabForCell:(PSMTabBarCell *)cell {
    [self removeProgressBarForCell:cell];
    [super removeTabForCell:cell];
}

- (void)removeCell:(PSMTabBarCell *)cell {
    [self removeProgressBarForCell:cell];
    [super removeCell:cell];
}

#pragma mark - Private

- (NSValue *)progressBarKeyForCell:(PSMTabBarCell *)cell {
    return [NSValue valueWithNonretainedObject:cell];
}

- (BOOL)cellAllowsTabProgressBar:(PSMTabBarCell *)cell {
    NSTabViewItem *item = (NSTabViewItem *)cell.representedObject;
    PTYTab *tab = item.identifier;
    if (![tab isKindOfClass:[PTYTab class]]) {
        return YES;
    }
    return tab.activeSession.view.enableProgressBars;
}

- (BOOL)cellShouldShowTabProgressBar:(PSMTabBarCell *)cell {
    if (self.tabView.numberOfTabViewItems <= 1 ||
        cell.isPlaceholder ||
        cell.isInOverflowMenu ||
        ![self cellAllowsTabProgressBar:cell]) {
        return NO;
    }
    switch (cell.progress) {
        case PSMProgressStopped:
            return NO;
        case PSMProgressError:
        case PSMProgressIndeterminate:
            return YES;
        case PSMProgressSuccessBase:
        case PSMProgressWarningBase:
        case PSMProgressErrorBase:
            break;
    }
    return ((cell.progress >= PSMProgressSuccessBase && cell.progress <= PSMProgressSuccessBase + 100) ||
            (cell.progress >= PSMProgressErrorBase && cell.progress <= PSMProgressErrorBase + 100) ||
            (cell.progress >= PSMProgressWarningBase && cell.progress <= PSMProgressWarningBase + 100));
}

- (NSString *)tabProgressBarColorSchemeForCell:(PSMTabBarCell *)cell {
    NSTabViewItem *item = (NSTabViewItem *)cell.representedObject;
    PTYTab *tab = item.identifier;
    if (![tab isKindOfClass:[PTYTab class]]) {
        return iTermProgressBarColorSchemeDefault;
    }
    return tab.activeSession.view.progressBarColorScheme ?: iTermProgressBarColorSchemeDefault;
}

- (NSRect)frameForProgressBarInCell:(PSMTabBarCell *)cell {
    return NSMakeRect(cell.frame.origin.x,
                      cell.frame.origin.y,
                      cell.frame.size.width,
                      iTermTabProgressBarHeight);
}

- (void)removeProgressBarForCell:(PSMTabBarCell *)cell {
    NSValue *key = [self progressBarKeyForCell:cell];
    iTermProgressBarView *progressBar = _tabProgressBars[key];
    if (!progressBar) {
        return;
    }
    [progressBar removeFromSuperview];
    [_tabProgressBars removeObjectForKey:key];
}

- (void)syncTabProgressBars {
    NSMutableSet<NSValue *> *visibleKeys = [NSMutableSet set];
    for (PSMTabBarCell *cell in self.cells) {
        if (![self cellShouldShowTabProgressBar:cell]) {
            [self removeProgressBarForCell:cell];
            continue;
        }
        NSValue *key = [self progressBarKeyForCell:cell];
        [visibleKeys addObject:key];
        iTermProgressBarView *progressBar = _tabProgressBars[key];
        if (!progressBar) {
            progressBar = [[[iTermProgressBarView alloc] init] autorelease];
            progressBar.heightValue = iTermTabProgressBarHeight;
            _tabProgressBars[key] = progressBar;
        }
        progressBar.darkMode = self.style.useLightControls;
        progressBar.colorScheme = [self tabProgressBarColorSchemeForCell:cell];
        progressBar.state = (VT100ScreenProgress)cell.progress;
        progressBar.frame = [self frameForProgressBarInCell:cell];
        progressBar.hidden = NO;
        if (progressBar.superview != self) {
            [self addSubview:progressBar];
        }
        cell.indicator.hidden = YES;
        cell.indicator.animate = NO;
        [cell.indicator removeFromSuperview];
    }

    for (NSValue *key in [_tabProgressBars allKeys]) {
        if (![visibleKeys containsObject:key]) {
            iTermProgressBarView *progressBar = _tabProgressBars[key];
            [progressBar removeFromSuperview];
            [_tabProgressBars removeObjectForKey:key];
        }
    }
}

- (void)setFlashState:(iTermTabBarFlashState)flashState {
    NSArray *names = @[ @"Off", @"FadeIn", @"Holding", @"Extending", @"FadeOut" ];
    DLog(@"%@ -> %@ from\n%@", names[self.flashState], names[flashState], [NSThread callStackSymbols]);
    _flashState = flashState;
}

#pragma mark - Window Dragging

- (BOOL)mouseDownCanMoveWindow {
    return [self.itermTabBarDelegate iTermTabBarCanDragWindow] ? NO : [super mouseDownCanMoveWindow];
}

- (NSRect)_opaqueRectForWindowMoveWhenInTitlebar {
    return [self.itermTabBarDelegate iTermTabBarCanDragWindow] ? self.bounds : [super _opaqueRectForWindowMoveWhenInTitlebar];
}

- (void)mouseDown:(NSEvent *)event {
    if (![self.itermTabBarDelegate iTermTabBarCanDragWindow]) {
        [super mouseDown:event];
        return;
    }

    NSView *superview = [self superview];
    NSPoint hitLocation = [[superview superview] convertPoint:[event locationInWindow]
                                                     fromView:nil];
    NSView *hitView = [superview hitTest:hitLocation];

    NSPoint pointInView = [self convertPoint:event.locationInWindow fromView:nil];
    const BOOL handleDrag = ([self.itermTabBarDelegate iTermTabBarCanDragWindow] &&
                             ![self wantsMouseDownAtPoint:pointInView] &&
                             hitView == self &&
                             ![self.itermTabBarDelegate iTermTabBarWindowIsFullScreen]);
    if (handleDrag) {
        [self.window orderFrontRegardless];
        [self.window performWindowDragWithEvent:event];
        return;
    }
    
    [super mouseDown:event];
}

- (BOOL)clickedInCell:(NSEvent *)event {
    const NSPoint clickPoint = [self convertPoint:event.locationInWindow
                                         fromView:nil];
    NSRect cellFrame;
    PSMTabBarCell *const cell = [self cellForPoint:clickPoint
                                         cellFrame:&cellFrame];
    return cell != nil;
}

- (void)mouseUp:(NSEvent *)event {
    if (event.clickCount == 2 &&
        [self.itermTabBarDelegate iTermTabBarCanDragWindow] &&
        ![self clickedInCell:event]) {
        [self.window it_titleBarDoubleClick];
        return;
    }
    [super mouseUp:event];
}

@end
