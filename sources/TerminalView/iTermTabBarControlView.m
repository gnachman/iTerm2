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

@interface iTermTabBarControlView ()
@property(nonatomic, assign) iTermTabBarFlashState flashState;
@end

@implementation iTermTabBarControlView {
    iTermDelayedPerform *_flashDelayedPerform;  // weak
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(advancedSettingsDidChange:)
                                                     name:iTermAdvancedSettingsDidChange
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
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

// Grow a style-provided single-row height to fit the rows the bar will actually use.
// Styles report their own single-row height; the two-row geometry belongs to the
// shared layer (PSMTabBarControl) so every theme gets it. A no-op on one row, and
// for vertical bars, where horizontalRowCount is always 1.
- (CGFloat)heightForRowsGivenSingleRowHeight:(CGFloat)singleRowHeight {
    if ([self horizontalRowCount] > 1) {
        return [self twoRowHeightForSingleRowHeight:singleRowHeight];
    }
    return singleRowHeight;
}

- (void)setOrientation:(PSMTabBarOrientation)orientation {
    [super setOrientation:orientation];
    if (@available(macOS 26, *)) {
        self.style.orientation = self.orientation;
        const CGFloat styleHeight = self.style.tabBarHeight;
        if (styleHeight > 0) {
            // The style's height is per-row, so apply the row count here. This method
            // runs on every layout pass (via setTabLocation:), so without it a
            // two-row bar was immediately shrunk back to one row's height after
            // updateHeightWithDefault: had set it correctly — leaving both rows
            // crammed into a single-row-tall bar in themes whose style reports a
            // nonzero height, i.e. everything except Minimal (0) and Tahoe.
            self.height = [self heightForRowsGivenSingleRowHeight:styleHeight];
        } else {
            // Already row-aware: the delegate's desired height accounts for the rows.
            self.height = [self.delegate tabViewDesiredTabBarHeight:self.tabView];
        }
    }
    self.showAddTabButton = ![iTermAdvancedSettingsModel removeAddTabButton] && (orientation == PSMTabBarHorizontalOrientation);
}

- (void)updateHeightWithDefault:(CGFloat)defaultHeight {
    const CGFloat previousHeight = self.height;
    if (@available(macOS 26, *)) {
        if (self.orientation == PSMTabBarVerticalOrientation) {
            self.style.orientation = self.orientation;
            const CGFloat styleHeight = self.style.tabBarHeight;
            if (styleHeight > 0) {
                self.height = [self heightForRowsGivenSingleRowHeight:styleHeight];
                if (self.height != previousHeight) {
                    [self update:NO];
                }
                return;
            }
        }
    }
    self.height = defaultHeight;
    if (self.height != previousHeight) {
        [self update:NO];
    }
}

#pragma mark - Private

- (BOOL)cellAllowsTabProgressBar:(PSMTabBarCell *)cell {
    NSTabViewItem *item = (NSTabViewItem *)cell.representedObject;
    PTYTab *tab = item.identifier;
    if (![tab isKindOfClass:[PTYTab class]]) {
        return YES;
    }
    return tab.activeSession.view.enableProgressBars;
}

- (BOOL)cellShouldShowTabProgressBar:(PSMTabBarCell *)cell {
    // Not drawn in the bar (scrolled into the overflow menu OR hidden inside a
    // collapsed group) means there is nowhere to put the in-bar progress bar; the
    // inline (in-session) fallback covers those. Gating only on isInOverflowMenu
    // used to leave a horizontal collapsed member (zero frame, isInOverflowMenu==NO)
    // returning YES, instantiating a phantom zero-size progress view.
    if (self.tabView.numberOfTabViewItems <= 1 ||
        cell.isPlaceholder ||
        ![self cellIsDrawnInBar:cell] ||
        ![self cellAllowsTabProgressBar:cell]) {
        return NO;
    }
    return VT100ScreenProgressIsVisible((VT100ScreenProgress)cell.progress);
}

- (NSString *)tabProgressBarColorSchemeForCell:(PSMTabBarCell *)cell {
    NSTabViewItem *item = (NSTabViewItem *)cell.representedObject;
    PTYTab *tab = item.identifier;
    if (![tab isKindOfClass:[PTYTab class]]) {
        return iTermProgressBarColorSchemeDefault;
    }
    return tab.activeSession.view.progressBarColorScheme ?: iTermProgressBarColorSchemeDefault;
}

- (BOOL)shouldShowCustomProgressBarForTabCell:(PSMTabBarCell *)cell {
    return [self cellShouldShowTabProgressBar:cell];
}

- (NSView *)customProgressBarViewForTabCell:(PSMTabBarCell *)cell {
    iTermProgressBarView *progressBar = [[[iTermProgressBarView alloc] init] autorelease];
    progressBar.heightValue = PSMTabBarProgressBarHeight;
    return progressBar;
}

- (void)configureCustomProgressBarView:(NSView *)view forTabCell:(PSMTabBarCell *)cell {
    iTermProgressBarView *progressBar = (iTermProgressBarView *)view;
    // The gradient fills the view's full height before the clip-path mask is
    // applied. For the flush bar styles the view is PSMTabBarProgressBarHeight
    // tall; for the Tahoe ring it's the outset pill height, so the gradient
    // fills the ring before the mask carves out its center.
    progressBar.heightValue = MAX(PSMTabBarProgressBarHeight, NSHeight(view.frame));
    progressBar.transparent = [self.style respondsToSelector:@selector(progressBarClipPathForTabCell:)];
    progressBar.darkMode = self.style.useLightControls;
    progressBar.colorScheme = [self tabProgressBarColorSchemeForCell:cell];
    progressBar.state = (VT100ScreenProgress)cell.progress;
}

- (void)syncTabProgressBars {
    [super syncTabProgressBars];
    if ([_itermTabBarDelegate respondsToSelector:@selector(iTermTabBarDidUpdateProgressBars)]) {
        [_itermTabBarDelegate iTermTabBarDidUpdateProgressBars];
    }
}

- (void)advancedSettingsDidChange:(NSNotification *)notification {
    [self syncTabProgressBars];
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
