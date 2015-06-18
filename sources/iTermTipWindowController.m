
//
//  iTermWelcomeWindowController.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermTipWindowController.h"

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

@interface iTermTipWindowController()<NSAnimationDelegate>
@property(nonatomic, retain) iTermTipCardViewController *cardViewController;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *body;
@property(nonatomic, copy) NSString *url;
@property(nonatomic, retain) NSView *intermediateView;
@end

@implementation iTermTipWindowController

- (instancetype)initWithTitle:(NSString *)title body:(NSString *)body url:(NSString *)url {
    self = [self init];
    if (self) {
        self.title = title;
        self.body = body;
        self.url = url;
        [self window];
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
    }
    return self;
}

- (void)dealloc {
    [_title release];
    [_body release];
    [_url release];
    [_cardViewController release];
    [_intermediateView release];
    [super dealloc];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.window.level = NSModalPanelWindowLevel;
    self.window.opaque = NO;
    self.window.alphaValue = 0;

    NSView *contentView = self.window.contentView;
    contentView.autoresizesSubviews = NO;

    iTermTipCardViewController *card =
        [[[iTermTipCardViewController alloc] initWithNibName:@"iTermTipCardViewController"
                                                      bundle:nil] autorelease];
    self.cardViewController = card;
    [card view];
    card.titleString = self.title;
    card.color = [NSColor colorWithCalibratedRed:120/255.0 green:178/255.0 blue:1.0 alpha:1];
    card.bodyText = self.body;
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

    [card addActionWithTitle:@"More Options"
                        icon:[NSImage imageNamed:@"ChevronDown"]
                       block:^(id sendingCard) {
        iTermTipCardActionButton *action = [card actionWithTitle:@"More Options"];
        if (action) {
            // Expanding
            [action setTitle:@"Fewer Options"];
            [action setIcon:[NSImage imageNamed:@"ChevronUp"]];
            [[card actionWithTitle:@"Remind Me Later"] setAnimationState:kTipCardButtonAnimatingIn];
            [[card actionWithTitle:@"Disable Tips"] setAnimationState:kTipCardButtonAnimatingIn];
        } else {
            // Collapsing
            action = [card actionWithTitle:@"Fewer Options"];
            [action setTitle:@"More Options"];
            [action setIcon:[NSImage imageNamed:@"ChevronDown"]];
            [[card actionWithTitle:@"Remind Me Later"] setAnimationState:kTipCardButtonAnimatingOut];
            [[card actionWithTitle:@"Disable Tips"] setAnimationState:kTipCardButtonAnimatingOut];
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
    [button setCollapsed:YES];
    button =
        [card addActionWithTitle:@"Disable Tips"
                            icon:[NSImage imageNamed:@"DisableTips"]
                           block:^(id sendingCard) {
                               [[NSNotificationCenter defaultCenter] postNotificationName:kDisableTipsTipNotification
                                                                                   object:nil];
                           }];
    [button setCollapsed:YES];

    self.intermediateView = [[[iTermFlippedView alloc] initWithFrame:[self.window.contentView bounds]] autorelease];
    [_intermediateView setWantsLayer:YES];
    _intermediateView.layer.opaque = NO;
    _intermediateView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _intermediateView.autoresizesSubviews = YES;

    [self.window.contentView addSubview:_intermediateView];
    [_intermediateView addSubview:card.view];
    

    [self layoutCard:card animated:NO];

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
    [self.window setFrame:windowFrame display:NO];
    [card layoutWithWidth:kWindowWidth animated:NO origin:NSZeroPoint];

    if (animated) {
        const CGFloat duration = 0.25;
        [CATransaction begin];

        [card retain];
        [self retain];
        [CATransaction setCompletionBlock:^{
            card.showFakeBottomDivider = NO;
            NSRect finalWindowFrame = NSMakeRect(NSMinX(screenFrame) + 8,
                                                 NSMaxY(screenFrame) - NSHeight(frame) - 8,
                                                 frame.size.width,
                                                 frame.size.height);
            [self.window setFrame:finalWindowFrame display:NO];
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
                        [button setCollapsed:YES];
                    }
                    button.animationState = kTipCardButtonNotAnimating;
                }
            }
        }

        [card layoutWithWidth:kWindowWidth animated:NO origin:NSZeroPoint];
        [CATransaction commit];
    }
}

- (void)dismiss {
    [self animateOut];
    [_delegate tipWindowDismissed];
}

- (void)animateOut {
    SolidColorView *container = [[[SolidColorView alloc] initWithFrame:[self.window.contentView frame]] autorelease];
    container.color = [NSColor clearColor];
    container.autoresizesSubviews = NO;
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
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:_url]];
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

- (void)present {
    NSDictionary *dict = @{ NSViewAnimationTargetKey: self.window,
                            NSViewAnimationEffectKey: NSViewAnimationFadeInEffect };
    NSViewAnimation *viewAnimation = [[[NSViewAnimation alloc] initWithViewAnimations:@[ dict ]] autorelease];

    // Set some additional attributes for the animation.
    [viewAnimation setDuration:0.5];

    // Run the animation.
    [viewAnimation startAnimation];
}

#pragma mark - NSAnimationDelegate

- (void)animationDidEnd:(NSAnimation *)animation {
    [self close];
}

@end
