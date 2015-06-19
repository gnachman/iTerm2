
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
#import "iTermTipLayerBackedView.h"
#import "NSView+iTerm.h"
#import "SolidColorView.h"

#import <QuartzCore/QuartzCore.h>

static NSString *const kLearnMoreTitle = @"Learn More";
static NSString *const kDismissTipTitle = @"Dismiss Tip";
static NSString *const kFewerOptionsTitle = @"Fewer Options";
static NSString *const kMoreOptionsTitle = @"More Options";
static NSString *const kRemindMeLaterTitle = @"Remind Me Later";
static NSString *const kDisableTipsTitle = @"Disable Tips";
static NSString *const kShowNextTipTitle = @"Show Next Tip";

static const CGFloat kWindowWidth = 400;

@interface iTermTipWindowController()
@property(nonatomic, retain) iTermTipCardViewController *cardViewController;
@property(nonatomic, retain) iTermTip *tip;
@property(nonatomic, retain) NSView *intermediateView;
@property(nonatomic, assign) BOOL windowCanShrink;
@property(nonatomic, assign) BOOL buttonsEnabled;
@end

@implementation iTermTipWindowController {
    NSRect _desiredWindowFrame;
    NSInteger _holdWindowSizeCount;
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

- (void)addButtonsToCard:(iTermTipCardViewController *)card expanded:(BOOL)expanded {
    [card addActionWithTitle:kLearnMoreTitle
                        icon:[NSImage imageNamed:@"Navigate"]
                       block:^(id sendingCard) {
                           [self openURL];
                       }];
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
        [card addActionWithTitle:kRemindMeLaterTitle
                            icon:[NSImage imageNamed:@"Later"]
                           block:^(id sendingCard) {
                               [self remindMeLater];
                           }];
    if (!expanded) {
        [button setCollapsed:YES];
    }
    button =
        [card addActionWithTitle:kDisableTipsTitle
                            icon:[NSImage imageNamed:@"DisableTips"]
                           block:^(id sendingCard) {
                               [self disableTips];
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

- (NSArray *)collapsingTitles {
    return @[ kRemindMeLaterTitle,
              kDisableTipsTitle,
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
    [self present];
}

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
    [card layoutWithWidth:kWindowWidth animated:NO origin:NSZeroPoint];

    if (animated) {
        const CGFloat duration = 0.25;
        [CATransaction begin];

        self.buttonsEnabled = NO;
        [card retain];
        [self retain];
        [CATransaction setCompletionBlock:^{
            self.buttonsEnabled = YES;
            card.showFakeBottomDivider = NO;
            [card hideCollapsedButtons];
            NSRect finalWindowFrame = NSMakeRect(NSMinX(screenFrame) + 8,
                                                 NSMaxY(screenFrame) - NSHeight(postAnimationFrame) - 8,
                                                 postAnimationFrame.size.width,
                                                 postAnimationFrame.size.height);
            [self setWindowFrame:finalWindowFrame];
            card.view.frame = postAnimationFrame;
            [card release];
            [self release];
        }];

        CGFloat heightChange = card.postAnimationFrame.size.height - card.view.frame.size.height;

        {
            CABasicAnimation* fadeAnim = [CABasicAnimation animationWithKeyPath:@"bounds"];
            NSRect startBounds = originalCardFrame;
            startBounds.origin = NSMakePoint(0, 0);
            fadeAnim.fromValue = [NSValue valueWithRect:startBounds];

            NSRect endBounds = startBounds;
            endBounds.size.height += heightChange;
            frame.origin = NSZeroPoint;
            fadeAnim.toValue = [NSValue valueWithRect:endBounds];
            fadeAnim.duration = duration;

            [card.view.layer addAnimation:fadeAnim forKey:@"bounds"];
        }

        {
            CABasicAnimation* containerAnimation = [CABasicAnimation animationWithKeyPath:@"bounds"];
            NSRect startBounds = card.containerView.layer.bounds;
            containerAnimation.fromValue = [NSValue valueWithRect:startBounds];

            NSRect endBounds = startBounds;
            endBounds.size.height += heightChange;
            containerAnimation.toValue = [NSValue valueWithRect:endBounds];
            containerAnimation.duration = duration;
            [card.containerView.layer addAnimation:containerAnimation forKey:@"bounds"];
        }

        NSMutableArray *buttonsToCollapse = [NSMutableArray array];
        {
            for (iTermTipCardActionButton *button in card.actionButtons) {
                if (button.animationState != kTipCardButtonNotAnimating) {
                    // Animate the button's position
                    card.showFakeBottomDivider = YES;
                    CABasicAnimation* fadeAnim = [CABasicAnimation animationWithKeyPath:@"position"];
                    NSPoint position = button.layer.position;
                    fadeAnim.fromValue = [NSValue valueWithPoint:position];
                    fadeAnim.toValue = [NSValue valueWithPoint:NSMakePoint(position.x, position.y + heightChange)];
                    fadeAnim.duration = duration;
                    [button.layer addAnimation:fadeAnim forKey:@"position"];
                    if (button.animationState == kTipCardButtonAnimatingOut) {
                        [buttonsToCollapse addObject:button];
                        button.animationState = kTipCardButtonAnimatingOutCurrently;
                    } else {
                        button.animationState = kTipCardButtonNotAnimating;
                    }
                }
            }
        }

        [card layoutWithWidth:kWindowWidth animated:NO origin:NSZeroPoint];
        [CATransaction commit];

        for (iTermTipCardActionButton *button in buttonsToCollapse) {
            [button setCollapsed:YES];
        }
    }
}

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
        [[card actionWithTitle:kRemindMeLaterTitle] setAnimationState:kTipCardButtonAnimatingIn];
        [[card actionWithTitle:kDisableTipsTitle] setAnimationState:kTipCardButtonAnimatingIn];
        [[card actionWithTitle:kShowNextTipTitle] setAnimationState:kTipCardButtonAnimatingIn];
    } else {
        // Collapsing
        action = [card actionWithTitle:kFewerOptionsTitle];
        [action setIconFlipped:NO];
        [action setTitle:kMoreOptionsTitle];
        [[card actionWithTitle:kRemindMeLaterTitle] setAnimationState:kTipCardButtonAnimatingOut];
        [[card actionWithTitle:kDisableTipsTitle] setAnimationState:kTipCardButtonAnimatingOut];
        [[card actionWithTitle:kShowNextTipTitle] setAnimationState:kTipCardButtonAnimatingOut];
    }
    [self layoutCard:card animated:YES];
}

- (void)remindMeLater {
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
        const NSTimeInterval duration = 0.5;
        self.buttonsEnabled = NO;
        [[NSAnimationContext currentContext] setDuration:duration];
        [self retain];
        iTermTipCardViewController *exitingCardViewController = _cardViewController;
        [[NSAnimationContext currentContext] setCompletionHandler:^{
            [exitingCardViewController.view removeFromSuperview];
            [_exitingCardViewControllers removeObject:exitingCardViewController];
            self.buttonsEnabled = YES;
            self.windowCanShrink = YES;
            [self release];
        }];
        NSRect frame = _cardViewController.view.frame;
        frame.origin.x = -frame.size.width;
        _cardViewController.view.autoresizingMask = 0;

        [_cardViewController.view.animator setFrame:frame];

        [_delegate tipWindowWillShowTipWithIdentifier:nextTip.identifier];
        self.tip = nextTip;
        BOOL expanded = ([_cardViewController actionWithTitle:kMoreOptionsTitle] == nil);
        // Card moved to exitingCardViewControllers while buttons are disabled so buttons will
        // never be enabled in this card again.
        [_exitingCardViewControllers addObject:_cardViewController];
        _cardViewController = nil;
        [self loadCardExpanded:expanded];

        frame = _cardViewController.view.frame;
        frame.origin.x += self.window.frame.size.width;
        [_cardViewController.view setFrame:frame];

        frame.origin.x -= self.window.frame.size.width;
        [_cardViewController.view.animator setFrame:frame];
    }
}

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
