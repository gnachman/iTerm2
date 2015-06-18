
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

static const CGFloat kWindowWidth = 400;
static NSString *const kDismissCurrentTipNotification = @"kDismissCurrentTipNotification";
static NSString *const kOpenURLTipNotification = @"kOpenURLTipNotification";
static NSString *const kRemindMeLaterTipNotification = @"kRemindMeLaterTipNotification";
static NSString *const kDisableTipsTipNotification = @"kDisableTipsTipNotification";
static NSString *const kShowNextTipNotification = @"kShowNextTipNotification";

@interface iTermTipWindowController()<NSAnimationDelegate>
@property(nonatomic, retain) iTermTipCardViewController *cardViewController;
@property(nonatomic, retain) iTermTip *tip;
@property(nonatomic, retain) NSView *intermediateView;
@property(nonatomic, assign) BOOL windowCanShrink;
@end

@implementation iTermTipWindowController {
    NSRect _desiredWindowFrame;
    NSInteger _holdWindowSizeCount;
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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(dismiss)
                                                     name:kDismissCurrentTipNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(open)
                                                     name:kOpenURLTipNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(remindMeLater)
                                                     name:kRemindMeLaterTipNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(disableTips)
                                                     name:kDisableTipsTipNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(showNextTip)
                                                     name:kShowNextTipNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [_tip release];
    [_cardViewController release];
    [_intermediateView release];
    [super dealloc];
}

- (void)loadCardExpanded:(BOOL)expanded {
    iTermTipCardViewController *card =
        [[[iTermTipCardViewController alloc] initWithNibName:@"iTermTipCardViewController"
                                                      bundle:nil] autorelease];
    self.cardViewController = card;
    [card view];
    card.titleString = self.tip.title;
    card.color = [NSColor colorWithCalibratedRed:120/255.0 green:178/255.0 blue:1.0 alpha:1];
    card.bodyText = self.tip.body;
    [card addActionWithTitle:@"Learn More"
                        icon:[NSImage imageNamed:@"Navigate"]
                       block:^(id sendingCard) {
                           [[NSNotificationCenter defaultCenter] postNotificationName:kOpenURLTipNotification
                                                                               object:nil];
                       }];
    [card addActionWithTitle:@"Dismiss Tip"
                        icon:[NSImage imageNamed:@"Dismiss"]
                       block:^(id sendingCard) {
                           [[NSNotificationCenter defaultCenter] postNotificationName:kDismissCurrentTipNotification
                                                                               object:nil];
                       }];

    NSString *toggleTitle = expanded ? @"Fewer Options" : @"More Options";
    NSImage *toggleImage = expanded ? [NSImage imageNamed:@"ChevronUp"] : [NSImage imageNamed:@"ChevronDown"];
    [card addActionWithTitle:toggleTitle
                        icon:toggleImage
                       block:^(id sendingCard) {
        iTermTipCardActionButton *action = [card actionWithTitle:@"More Options"];
        if (action) {
            // Expanding
            [action setTitle:@"Fewer Options"];
            [action setIcon:[NSImage imageNamed:@"ChevronUp"]];
            [[card actionWithTitle:@"Remind Me Later"] setAnimationState:kTipCardButtonAnimatingIn];
            [[card actionWithTitle:@"Disable Tips"] setAnimationState:kTipCardButtonAnimatingIn];
            [[card actionWithTitle:@"Show Next Tip"] setAnimationState:kTipCardButtonAnimatingIn];
        } else {
            // Collapsing
            action = [card actionWithTitle:@"Fewer Options"];
            [action setTitle:@"More Options"];
            [action setIcon:[NSImage imageNamed:@"ChevronDown"]];
            [[card actionWithTitle:@"Remind Me Later"] setAnimationState:kTipCardButtonAnimatingOut];
            [[card actionWithTitle:@"Disable Tips"] setAnimationState:kTipCardButtonAnimatingOut];
            [[card actionWithTitle:@"Show Next Tip"] setAnimationState:kTipCardButtonAnimatingOut];
        }
        [self layoutCard:card animated:YES];
    }];
    iTermTipCardActionButton *button =
        [card addActionWithTitle:@"Remind Me Later"
                            icon:[NSImage imageNamed:@"Later"]
                           block:^(id sendingCard) {
                               [[NSNotificationCenter defaultCenter] postNotificationName:kRemindMeLaterTipNotification
                                                                                   object:nil];
                           }];
    if (!expanded) {
        [button setCollapsed:YES];
    }
    button =
        [card addActionWithTitle:@"Disable Tips"
                            icon:[NSImage imageNamed:@"DisableTips"]
                           block:^(id sendingCard) {
                               [[NSNotificationCenter defaultCenter] postNotificationName:kDisableTipsTipNotification
                                                                                   object:nil];
                           }];
    if (!expanded) {
        [button setCollapsed:YES];
    }

    if ([_delegate tipWindowTipAfterTipWithIdentifier:self.tip.identifier]) {
        button =
            [card addActionWithTitle:@"Show Next Tip"
                                icon:[NSImage imageNamed:@"DisableTips"]
                               block:^(id sendingCard) {
                                   [[NSNotificationCenter defaultCenter] postNotificationName:kShowNextTipNotification
                                                                                       object:nil];
                               }];
        if (!expanded) {
            [button setCollapsed:YES];
        }
    }

    [_intermediateView addSubview:_cardViewController.view];
    [self layoutCard:card animated:NO];
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

        [card retain];
        [self retain];
        [CATransaction setCompletionBlock:^{
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
    SolidColorView *container = [[[SolidColorView alloc] initWithFrame:[self.window.contentView frame]] autorelease];
    container.color = [NSColor clearColor];
    container.autoresizesSubviews = YES;

    NSImageView *imageView = [[[NSImageView alloc] initWithFrame:[self.window.contentView bounds]] autorelease];
    imageView.autoresizingMask = 0;
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.image = [self.window.contentView snapshot];
    [self.window setContentView:container];
    [container addSubview:imageView];

    self.window.contentView = container;

    NSRect startFrame = imageView.frame;
    NSRect endFrame = startFrame;
    endFrame.origin.y += endFrame.size.height;

    NSDictionary *dict = @{ NSViewAnimationTargetKey: imageView,
                            NSViewAnimationStartFrameKey: [NSValue valueWithRect:startFrame],
                            NSViewAnimationEndFrameKey: [NSValue valueWithRect:endFrame],
                            NSViewAnimationEffectKey: NSViewAnimationFadeOutEffect };
    NSViewAnimation *viewAnimation = [[[NSViewAnimation alloc] initWithViewAnimations:@[ dict ]] autorelease];

    // Set some additional attributes for the animation.
    [viewAnimation setDuration:0.5];

    [viewAnimation setDelegate:self];

    // Run the animation.
    [viewAnimation startAnimation];
}

- (void)open {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:self.tip.url]];
    [self dismiss];
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
        const NSTimeInterval duration = 2;
        [[NSAnimationContext currentContext] setDuration:duration];
        NSRect frame = _cardViewController.view.frame;
        frame.origin.x = -frame.size.width;
        _cardViewController.view.autoresizingMask = 0;

        [_cardViewController.view.animator setFrame:frame];
        // TODO: remove old vc from view hierarchy when animation completes

        [_delegate tipWindowWillShowTipWithIdentifier:nextTip.identifier];
        self.tip = nextTip;
        BOOL expanded = ([_cardViewController actionWithTitle:@"More Options"] == nil);
        [self loadCardExpanded:expanded];

        frame = _cardViewController.view.frame;
        frame.origin.x += self.window.frame.size.width;
        [_cardViewController.view setFrame:frame];

        frame.origin.x -= self.window.frame.size.width;
        [_cardViewController.view.animator setFrame:frame];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.windowCanShrink = YES;
        });
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

#pragma mark - NSAnimationDelegate

- (void)animationDidEnd:(NSAnimation *)animation {
    [self close];
}

@end
