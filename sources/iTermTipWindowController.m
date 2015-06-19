
//
//  iTermWelcomeWindowController.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermTipWindowController.h"

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
static NSString *const kReallyDisableTipsTitle = @"Click Again to Disable Tips";
static NSString *const kShowNextTipTitle = @"Show Next Tip";

static const CGFloat kWindowWidth = 400;

@interface iTermTipWindowController()
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
    button =
        [card addActionWithTitle:kDisableTipsTitle
                            icon:[NSImage imageNamed:@"DisableTips"]
                           block:^(id sendingCard) {
                               iTermTipCardActionButton *theButton = [card actionWithTitle:kDisableTipsTitle];
                               if (theButton) {
                                   [theButton setTitle:kReallyDisableTipsTitle];
                               } else {
                                   [self disableTips];
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
              kShowNextTipTitle ];
}

- (void)windowDidLoad {
    [super windowDidLoad];
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
}

// Update the card's size.
- (void)layoutCard:(iTermTipCardViewController *)card animated:(BOOL)animated {
    NSRect originalCardFrame = card.view.frame;
    [card sizeThatFits:NSMakeSize(kWindowWidth, CGFLOAT_MAX)];
    NSRect postAnimationFrame = card.postAnimationFrame;
    NSRect frame = postAnimationFrame;
    frame.size.height = MAX(frame.size.height, card.view.frame.size.height);
    frame.origin = NSZeroPoint;

    NSRect screenFrame = self.window.screen.visibleFrame;
    NSRect windowFrame = NSMakeRect(NSMinX(screenFrame) + 8,
                                    NSMaxY(screenFrame) - NSHeight(frame) - 8,
                                    frame.size.width,
                                    frame.size.height);
    [self setWindowFrame:windowFrame];
    [card layoutWithWidth:kWindowWidth origin:NSZeroPoint];

    if (animated) {
        // Disable buttons until animation is done.
        self.buttonsEnabled = NO;
        CGFloat heightChange = card.postAnimationFrame.size.height - card.view.frame.size.height;
        NSRect finalWindowFrame = NSMakeRect(NSMinX(screenFrame) + 8,
                                             NSMaxY(screenFrame) - NSHeight(postAnimationFrame) - 8,
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
        [[card actionWithTitle:kShowNextTipTitle] setAnimationState:kTipCardButtonAnimatingIn];
    } else {
        // Collapsing
        action = [card actionWithTitle:kFewerOptionsTitle];
        [action setIconFlipped:NO];
        [action setTitle:kMoreOptionsTitle];
        [[card actionWithTitle:kShowThisLaterTitle] setAnimationState:kTipCardButtonAnimatingOut];
        [[card actionWithTitle:kDisableTipsTitle] setAnimationState:kTipCardButtonAnimatingOut];
        [[card actionWithTitle:kReallyDisableTipsTitle] setAnimationState:kTipCardButtonAnimatingOut];
        [[card actionWithTitle:kShowNextTipTitle] setAnimationState:kTipCardButtonAnimatingOut];
    }
    [self layoutCard:card animated:YES];
}

- (void)showThisLater {
    [self animateOut];
    [_delegate tipWindowPostponed];
}

- (void)disableTips {
    [self animateOut];
    [_delegate tipWindowRequestsDisable];
}

- (void)showNextTip {
    iTermTip *nextTip = [_delegate tipWindowTipAfterTipWithIdentifier:_tip.identifier];
    if (nextTip) {
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

        // Move old card to the left, out of the window.
        NSRect frame = _cardViewController.view.frame;
        frame.origin.x = -frame.size.width;
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
        frame.origin.x += self.window.frame.size.width;
        [_cardViewController.view setFrame:frame];

        frame.origin.x -= self.window.frame.size.width;
        [_cardViewController.view.animator setFrame:frame];
    }
}

// Animate the window in the first time. Use an old-school-cool API.
// TODO: Just animate the card frame in, no need for NSViewAnimation.
- (void)present {
    NSDictionary *dict = @{ NSViewAnimationTargetKey: self.window,
                            NSViewAnimationEffectKey: NSViewAnimationFadeInEffect };
    NSViewAnimation *viewAnimation = [[[NSViewAnimation alloc] initWithViewAnimations:@[ dict ]] autorelease];

    // Set some additional attributes for the animation.
    [viewAnimation setDuration:0.5];

    // Run the animation.
    [viewAnimation startAnimation];
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
