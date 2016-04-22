
//
//  iTermWelcomeWindowController.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermTipWindowController.h"

#import "GTMCarbonEvent.h"
#import "iTermTip.h"
#import "iTermTipCardActionButton.h"
#import "iTermTipCardViewController.h"
#import "iTermFlippedView.h"
#import "NSView+iTerm.h"
#import "SolidColorView.h"

#import <QuartzCore/QuartzCore.h>

static NSString *const kLearnMoreTitle = @"Learn More";
static NSString *const kDismissTipTitle = @"Dismiss Tip";
static NSString *const kFewerOptionsTitle = @"Fewer Options";
static NSString *const kMoreOptionsTitle = @"More Options";
static NSString *const kShowThisLaterTitle = @"Show This Later";
static NSString *const kDisableTipsTitle = @"Disable Tips";
static NSString *const kEnableTipsTitle = @"Enable Tips";
static NSString *const kReallyDisableTipsTitle = @"Click Again to Disable Tips";
static NSString *const kShowNextTipTitle = @"Show Next Tip";
static NSString *const kShowPreviousTipTitle = @"Show Previous Tip";

static const CGFloat kWindowWidth = 400;

@interface iTermTipWindowController()<NSWindowDelegate>

@property(nonatomic, retain) iTermTipCardViewController *cardViewController;
@property(nonatomic, retain) iTermTip *tip;

// This is a layer-backed view that contains the card because the contentView
// can't be layer backed and clear.
@property(nonatomic, retain) NSView *intermediateView;

// Can the window shrink now? Window shrinking is desirable to prevent when
// the card's size is animating down but the window oughtn't shrink til the
// animation is complete.
@property(nonatomic, assign) BOOL windowCanShrink;

// Allowed to click on buttons? Clicks are off during animations to keep things
// simple.
@property(nonatomic, assign) BOOL buttonsEnabled;
@end

@implementation iTermTipWindowController {
    // If you tried to resize the window but windowCanShrink is NO this saves
    // the last desired window size. When the window can shrink again then it
    // will be updated.
    NSRect _desiredWindowFrame;

    // Reference count of window-can-shrink disablements.
    NSInteger _holdWindowSizeCount;

    // Cards that are animating out. In practice this can have up to 1 element.
    NSMutableArray *_exitingCardViewControllers;

    GTMCarbonHotKey *_hotkey;
}

- (instancetype)initWithTip:(id)tip {
    self = [self init];
    if (self) {
        _tip = [tip retain];
    }
    return self;
}

- (instancetype)init {
    self = [self initWithWindowNibName:@"iTermTipWindowController"];
    if (self) {
        _buttonsEnabled = YES;
        _exitingCardViewControllers = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_tip release];
    [_cardViewController release];
    [_intermediateView release];
    [_exitingCardViewControllers release];
    [super dealloc];
}

// Expanded means the "more options" is open.
- (void)loadCardExpanded:(BOOL)expanded {
    iTermTipCardViewController *card =
        [[[iTermTipCardViewController alloc] initWithNibName:@"iTermTipCardViewController"
                                                      bundle:nil] autorelease];
    self.cardViewController = card;
    [card view];
    card.titleString = self.tip.title;
    card.bodyText = self.tip.body;

    [self addButtonsToCard:card expanded:expanded];
    [_intermediateView addSubview:_cardViewController.view];
    [self layoutCard:card animated:NO];
}

// Add the standard buttons.
- (void)addButtonsToCard:(iTermTipCardViewController *)card expanded:(BOOL)expanded {
    if (_tip.url) {
        [card addActionWithTitle:kLearnMoreTitle
                            icon:[NSImage imageNamed:@"Navigate"]
                           block:^(id sendingCard) {
                               [self openURL];
                           }];
    }
    [card addActionWithTitle:kDismissTipTitle
                    shortcut:@"⎋"
                        icon:[NSImage imageNamed:@"Dismiss"]
                       block:^(id sendingCard) {
                           [self dismiss];
                       }];

    NSString *toggleTitle = expanded ? kFewerOptionsTitle : kMoreOptionsTitle;
    iTermTipCardActionButton *button =
        [card addActionWithTitle:toggleTitle
                            icon:[NSImage imageNamed:@"ChevronDown"]
                           block:^(id sendingCard) {
                               [self toggleOptionsInCard:sendingCard];
                           }];
    [button setIconFlipped:expanded];

    button =
        [card addActionWithTitle:kShowThisLaterTitle
                            icon:[NSImage imageNamed:@"Later"]
                           block:^(id sendingCard) {
                               [self showThisLater];
                           }];
    if (!expanded) {
        [button setCollapsed:YES];
    }

    NSString *enableOrDisableTitle;
    if ([_delegate tipWindowTipsAreDisabled]) {
        enableOrDisableTitle = kEnableTipsTitle;
    } else {
        enableOrDisableTitle = kDisableTipsTitle;
    }
    button =
        [card addActionWithTitle:enableOrDisableTitle
                            icon:[NSImage imageNamed:@"DisableTips"]
                           block:^(id sendingCard) {
                               if (![_delegate tipWindowTipsAreDisabled]) {
                                   iTermTipCardActionButton *theButton = [card actionWithTitle:kDisableTipsTitle];
                                   if (theButton) {
                                       [theButton setImportant:YES];
                                       [theButton setTitle:kReallyDisableTipsTitle];
                                   } else {
                                       [self disableTips];
                                   }
                               } else {
                                   iTermTipCardActionButton *theButton = [card actionWithTitle:kEnableTipsTitle];
                                   [self enableTips];
                                   [theButton setTitle:kDisableTipsTitle];
                               }
                           }];
    if (!expanded) {
        [button setCollapsed:YES];
    }

    if ([_delegate tipWindowTipAfterTipWithIdentifier:self.tip.identifier]) {
        button =
            [card addActionWithTitle:kShowNextTipTitle
                                icon:[NSImage imageNamed:@"NextTip"]
                               block:^(id sendingCard) {
                                   [self showNextTip];
                               }];
        if (!expanded) {
            [button setCollapsed:YES];
        }
    }
    if ([_delegate tipWindowTipBeforeTipWithIdentifier:self.tip.identifier]) {
        button =
            [card addActionWithTitle:kShowPreviousTipTitle
                                icon:[NSImage imageNamed:@"NextTip"]
                               block:^(id sendingCard) {
                                   [self showPreviousTip];
                               }];
        [button setIconFlipped:YES];
        if (!expanded) {
            [button setCollapsed:YES];
        }
        iTermTipCardActionButton *nextButton = [card actionWithTitle:kShowNextTipTitle];
        if (nextButton) {
            [card combineActionWithTitle:kShowPreviousTipTitle andTitle:kShowNextTipTitle];
        }
    }

    if (!expanded) {
        for (NSString *title in self.collapsingTitles) {
            button = [card actionWithTitle:title];
            if (button) {
                button.collapsed = YES;
            }
        }
    }
    for (iTermTipCardActionButton *aButton in card.actionButtons) {
        aButton.enabled = _buttonsEnabled;
    }
}

// Action button titles that are collapsable. These must appear adjacently and last.
- (NSArray *)collapsingTitles {
    return @[ kShowThisLaterTitle,
              kDisableTipsTitle,
              kReallyDisableTipsTitle,
              kEnableTipsTitle,
              kShowNextTipTitle,
              kShowPreviousTipTitle ];
}

// I originally preferred to do this in windowDidLoad, but the window's frame
// changes right after windowDidLoad returns.
- (void)showTipWindow {
    [self.window orderFront:nil];

    self.window.level = NSModalPanelWindowLevel;
    self.window.opaque = NO;
    self.window.alphaValue = 0;

    NSView *contentView = self.window.contentView;
    contentView.autoresizesSubviews = YES;

    self.intermediateView = [[[iTermFlippedView alloc] initWithFrame:[self.window.contentView bounds]] autorelease];
    [_intermediateView setWantsLayer:YES];
    _intermediateView.layer.opaque = NO;
    _intermediateView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _intermediateView.autoresizesSubviews = NO;

    [self.window.contentView addSubview:_intermediateView];

    [self loadCardExpanded:NO];

    // Animate in the window.
    [self present];

    if (!_hotkey) {
        _hotkey = [[[GTMCarbonEventDispatcherHandler sharedEventDispatcherHandler]
                          registerHotKey:kVK_Escape
                          modifiers:0
                          target:self
                          action:@selector(dismissByKeyboard:)
                          userInfo:nil
                          whenPressed:YES] retain];
    }
}

- (void)dismissByKeyboard:(id)sender {
    [self dismiss];
}

// Update the card's size.
- (void)layoutCard:(iTermTipCardViewController *)card animated:(BOOL)animated {
    NSRect originalCardFrame = card.view.frame;
    [card sizeThatFits:NSMakeSize(kWindowWidth, CGFLOAT_MAX)];
    NSRect postAnimationFrame = card.postAnimationFrame;
    NSRect frame = postAnimationFrame;
    frame.size.height = MAX(frame.size.height, card.view.frame.size.height);
    frame.origin = NSZeroPoint;

    static const CGFloat kWindowLeftMargin = 8;
    static const CGFloat kWindowTopMargin = 24;
    NSRect screenFrame = self.window.screen.visibleFrame;
    NSRect windowFrame = NSMakeRect(NSMinX(screenFrame) + kWindowLeftMargin,
                                    NSMaxY(screenFrame) - NSHeight(frame) - kWindowTopMargin,  // In case menu bar is hidden and later becomes visible
                                    frame.size.width,
                                    frame.size.height);
    [self setWindowFrame:windowFrame];
    [card layoutWithWidth:kWindowWidth origin:NSZeroPoint];

    if (animated) {
        // Disable buttons until animation is done.
        self.buttonsEnabled = NO;
        CGFloat heightChange = card.postAnimationFrame.size.height - card.view.frame.size.height;
        NSRect finalWindowFrame = NSMakeRect(NSMinX(screenFrame) + kWindowLeftMargin,
                                             NSMaxY(screenFrame) - NSHeight(postAnimationFrame) - kWindowTopMargin,
                                             postAnimationFrame.size.width,
                                             postAnimationFrame.size.height);

        [self retain];
        [card animateCardWithDuration:0.25
                         heightChange:heightChange
                    originalCardFrame:originalCardFrame
                   postAnimationFrame:postAnimationFrame
                       superviewWidth:kWindowWidth
                                block:^() {
                                    [self setWindowFrame:finalWindowFrame];
                                    self.buttonsEnabled = YES;
                                    [self release];
                                }];
    }
}

#pragma mark - User Actions

- (void)dismiss {
    if (_hotkey) {
        [[GTMCarbonEventDispatcherHandler sharedEventDispatcherHandler] unregisterHotKey:_hotkey];
        [_hotkey release];
        _hotkey = nil;
    }
    [self animateOut];
    [_delegate tipWindowDismissed];
}

- (void)animateOut {
    NSRect newFrame = _cardViewController.view.frame;
    newFrame.origin.y -= NSMaxY(newFrame);
    NSTimeInterval duration = 0.35;
    [[NSAnimationContext currentContext] setDuration:duration];
    [[NSAnimationContext currentContext] setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
    [self retain];
    self.buttonsEnabled = NO;
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        self.buttonsEnabled = YES;
        [self close];
        // Buttons hold references to us.
        for (iTermTipCardActionButton *button in _cardViewController.actionButtons) {
            button.block = nil;
        }
        [self release];
    }];
    [_cardViewController.view.animator setFrame:newFrame];
}

- (void)openURL {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:self.tip.url]];
    [self dismiss];
}

- (void)toggleOptionsInCard:(iTermTipCardViewController *)card {
    iTermTipCardActionButton *action = [card actionWithTitle:kMoreOptionsTitle];
    if (action) {
        // Expanding
        [action setIconFlipped:YES];
        [action setTitle:kFewerOptionsTitle];
        [[card actionWithTitle:kShowThisLaterTitle] setAnimationState:kTipCardButtonAnimatingIn];
        [[card actionWithTitle:kDisableTipsTitle] setAnimationState:kTipCardButtonAnimatingIn];
        [[card actionWithTitle:kReallyDisableTipsTitle] setAnimationState:kTipCardButtonAnimatingIn];
        [[card actionWithTitle:kEnableTipsTitle] setAnimationState:kTipCardButtonAnimatingIn];
        [[card actionWithTitle:kShowNextTipTitle] setAnimationState:kTipCardButtonAnimatingIn];
        [[card actionWithTitle:kShowPreviousTipTitle] setAnimationState:kTipCardButtonAnimatingIn];
    } else {
        // Collapsing
        action = [card actionWithTitle:kFewerOptionsTitle];
        [action setIconFlipped:NO];
        [action setTitle:kMoreOptionsTitle];
        [[card actionWithTitle:kShowThisLaterTitle] setAnimationState:kTipCardButtonAnimatingOut];
        [[card actionWithTitle:kDisableTipsTitle] setAnimationState:kTipCardButtonAnimatingOut];
        [[card actionWithTitle:kReallyDisableTipsTitle] setAnimationState:kTipCardButtonAnimatingOut];
        [[card actionWithTitle:kEnableTipsTitle] setAnimationState:kTipCardButtonAnimatingOut];
        [[card actionWithTitle:kShowNextTipTitle] setAnimationState:kTipCardButtonAnimatingOut];
        [[card actionWithTitle:kShowPreviousTipTitle] setAnimationState:kTipCardButtonAnimatingOut];
    }
    [self layoutCard:card animated:YES];
}

- (void)showThisLater {
    [self animateOut];
    [_delegate tipWindowPostponed];
}

- (void)enableTips {
    [_delegate tipWindowRequestsEnable];
}

- (void)disableTips {
    [self animateOut];
    [_delegate tipWindowRequestsDisable];
}

- (void)showNextTip {
    iTermTip *nextTip = [_delegate tipWindowTipAfterTipWithIdentifier:_tip.identifier];
    if (nextTip) {
        [self rollInTip:nextTip fromRight:YES];
    }
}

- (void)showPreviousTip {
    iTermTip *previousTip = [_delegate tipWindowTipBeforeTipWithIdentifier:_tip.identifier];
    if (previousTip) {
        [self rollInTip:previousTip fromRight:NO];
    }
}

- (void)rollInTip:(iTermTip *)nextTip fromRight:(BOOL)fromRight {
    self.windowCanShrink = NO;
    self.buttonsEnabled = NO;

    // Prepare to animate old card out and new card in.
    [[NSAnimationContext currentContext] setDuration:0.5];

    iTermTipCardViewController *exitingCardViewController = _cardViewController;

    [self retain];
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        // Kill old card and go back to normal behavior.
        [exitingCardViewController.view removeFromSuperview];
        [_exitingCardViewControllers removeObject:exitingCardViewController];
        self.buttonsEnabled = YES;
        self.windowCanShrink = YES;
        [self release];
    }];

    // Move old card to the side, out of the window.
    NSRect frame = _cardViewController.view.frame;
    if (fromRight) {
        frame.origin.x = -frame.size.width;
    } else {
        frame.origin.x = frame.size.width;
    }
    _cardViewController.view.autoresizingMask = 0;

    [_cardViewController.view.animator setFrame:frame];

    // Tell the delegate we're going to show another tip, then show it.
    [_delegate tipWindowWillShowTipWithIdentifier:nextTip.identifier];
    self.tip = nextTip;
    BOOL expanded = ([_cardViewController actionWithTitle:kMoreOptionsTitle] == nil);
    // Card moved to exitingCardViewControllers while buttons are disabled so buttons will
    // never be enabled in this card again.
    [_exitingCardViewControllers addObject:_cardViewController];
    _cardViewController = nil;
    [self loadCardExpanded:expanded];

    // Animate the new card in.
    frame = _cardViewController.view.frame;
    if (fromRight) {
        frame.origin.x += self.window.frame.size.width;
    } else {
        frame.origin.x -= self.window.frame.size.width;
    }
    [_cardViewController.view setFrame:frame];

    if (fromRight) {
        frame.origin.x -= self.window.frame.size.width;
    } else {
        frame.origin.x += self.window.frame.size.width;
    }
    [_cardViewController.view.animator setFrame:frame];
}

- (void)present {
    [[NSAnimationContext currentContext] setDuration:0.5];
    NSRect endFrame = _cardViewController.view.frame;
    NSRect startFrame = _cardViewController.view.frame;
    startFrame.origin.y -= self.window.frame.size.height;
    _cardViewController.view.frame = startFrame;
    [_cardViewController.view.animator setFrame:endFrame];
    self.window.alphaValue = 1;
}

- (void)setWindowCanShrink:(BOOL)windowCanShrink {
    if (windowCanShrink) {
        --_holdWindowSizeCount;
    } else {
        ++_holdWindowSizeCount;
    }

    if (_holdWindowSizeCount == 0 && _desiredWindowFrame.size.width > 0) {
        // Have a saved window shrink.
        [self.window setFrame:_desiredWindowFrame display:NO];
        _desiredWindowFrame.size.width = 0;
    }
}

- (BOOL)windowCanShrink {
    return _holdWindowSizeCount == 0;
}

- (void)setWindowFrame:(NSRect)frame {
    if (self.windowCanShrink || frame.size.height >= self.window.frame.size.height) {
        [self.window setFrame:frame display:NO];
        _desiredWindowFrame = NSZeroRect;
    } else {
        _desiredWindowFrame = frame;
    }
}

- (void)setButtonsEnabled:(BOOL)buttonsEnabled {
    if (buttonsEnabled == _buttonsEnabled) {
        return;
    }
    _buttonsEnabled = buttonsEnabled;
    for (iTermTipCardActionButton *button in _cardViewController.actionButtons) {
        button.enabled = _buttonsEnabled;
    }
}

@end
