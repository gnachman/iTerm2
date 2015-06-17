
//
//  iTermWelcomeWindowController.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermTipWindowController.h"
#import "iTermTipCardViewController.h"
#import "NSView+iTerm.h"
#import "SolidColorView.h"

static NSString *const kDismissCurrentTipNotification = @"kDismissCurrentTipNotification";
static NSString *const kOpenURLTipNotification = @"kOpenURLTipNotification";
static NSString *const kRemindMeLaterTipNotification = @"kRemindMeLaterTipNotification";

@interface iTermTipWindowController()<NSAnimationDelegate>
@property(nonatomic, retain) iTermTipCardViewController *cardViewController;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *body;
@property(nonatomic, copy) NSString *url;
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
    }
    return self;
}

- (void)dealloc {
    [_title release];
    [_body release];
    [_url release];
    [_cardViewController release];
    [super dealloc];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.window.level = NSModalPanelWindowLevel;
    self.window.opaque = NO;
    self.window.alphaValue = 0;

    iTermTipCardViewController *card =
        [[[iTermTipCardViewController alloc] initWithNibName:@"iTermWelcomeCardViewController"
                                                      bundle:nil] autorelease];
    self.cardViewController = card;
    [card view];
    card.titleString = self.title;
    card.color = [NSColor colorWithCalibratedRed:120/255.0 green:178/255.0 blue:1.0 alpha:1];
    card.bodyText = self.body;
    [card addActionWithTitle:@"Learn More"
                        icon:[NSImage imageNamed:@"Navigate"]
                       block:^() {
                           [[NSNotificationCenter defaultCenter] postNotificationName:kOpenURLTipNotification
                                                                               object:nil];
                       }];
    [card addActionWithTitle:@"Dismiss Tip"
                        icon:[NSImage imageNamed:@"Dismiss"]
                       block:^() {
                           [[NSNotificationCenter defaultCenter] postNotificationName:kDismissCurrentTipNotification
                                                                               object:nil];
                       }];
    [card addActionWithTitle:@"Remind Me Later"
                        icon:[NSImage imageNamed:@"Later"]
                       block:^() {
                           [[NSNotificationCenter defaultCenter] postNotificationName:kRemindMeLaterTipNotification
                                                                               object:nil];
                       }];
    [card layoutWithWidth:400];

    NSRect frame = card.view.frame;
    frame.origin = NSZeroPoint;
    [self.window.contentView addSubview:card.view];
    NSRect screenFrame = self.window.screen.visibleFrame;
    NSRect windowFrame = NSMakeRect(NSMinX(screenFrame) + 8,
                                    NSMaxY(screenFrame) - NSHeight(frame) - 8,
                                    frame.size.width,
                                    frame.size.height);
    [self.window setFrame:windowFrame display:YES];
    card.view.frame = frame;

    [self present];
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
