//
//  PasteViewController.m
//  iTerm
//
//  Created by George Nachman on 3/12/13.
//
//

#import "PasteViewController.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTerm2SharedARC-Swift.h"
#import "NSColor+iTerm.h"
#import "NSImage+iTerm.h"
#import "PasteContext.h"
#import "PasteView.h"
#import "PseudoTerminal.h"
#import "PreferencePanel.h"
#import "SFSymbolEnum/SFSymbolEnum.h"

static float kAnimationDuration = 0.25;

// Horizontal gap between the passthrough button and the Cancel button.
static const CGFloat kKeystrokePassthroughButtonGap = 2;

static NSString *iTermPasteViewControllerNibName(BOOL mini) {
    if (mini) {
        return @"MiniPasteView";
    }
    if ([iTermAdvancedSettingsModel useOldStyleDropDownViews]) {
        return @"PasteView";
    }
    return @"MinimalPasteView";
}

@implementation PasteViewController {
    IBOutlet NSTextField *_label;
    IBOutlet NSProgressIndicator *progressIndicator_;
    // Created programmatically (not in the nib) so it adapts to both nib
    // geometries. Shown only while a wait-for-prompt paste is paused.
    NSButton *_keystrokePassthroughButton;
    // Transient callout that points at the button when typing gets queued. Owned
    // by us (retained) for the controller's lifetime; added to the window's
    // content view while visible.
    iTermPasteQueuedHintView *_queuedHintView;
    NSTimer *_queuedHintDismissTimer;
    // YES between a completed present and the start of a dismissal. Distinct from
    // "is a subview" because the view lingers in the hierarchy while fading out.
    BOOL _hintPresented;
    // Bumped on every show so a pending dismissal's deferred removal can tell
    // whether the hint was re-shown in the meantime.
    NSInteger _hintGeneration;
    int totalLength_;
    PasteContext *pasteContext_;
}

@synthesize delegate = delegate_;
@synthesize remainingLength = remainingLength_;

- (instancetype)initWithContext:(PasteContext *)pasteContext
                         length:(int)length
                           mini:(BOOL)mini {
    self = [super initWithNibName:iTermPasteViewControllerNibName(mini)
                           bundle:[NSBundle bundleForClass:self.class]];
    if (self) {
        [self view];
        _mini = mini;

        if (self.view.flipped) {
            // Fix up frames because the view is flipped.
            for (NSView *view in [self.view subviews]) {
                NSRect frame = [view frame];
                frame.origin.y = NSMaxY([self.view bounds]) - NSMaxY([view frame]);
                [view setFrame:frame];
            }
        }
        pasteContext_ = [pasteContext retain];
        totalLength_ = remainingLength_ = length;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(themeDidChange:)
                                                     name:kRefreshTerminalNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self removeKeystrokeQueuedHintImmediately];
    [_queuedHintView release];
    [pasteContext_ release];
    [super dealloc];
}

- (void)awakeFromNib {
    if (pasteContext_.isUpload) {
        _label.stringValue = NSLocalizedStringWithDefaultValue(@"PasteView.Sending", nil, [NSBundle mainBundle], @"Sending…", @"Label shown while an upload is in progress");
    }
    [self createKeystrokePassthroughButton];
}

// Find the nib's Cancel button so we can match its size/appearance and sit just
// to its left.
- (NSButton *)cancelButton {
    for (NSView *subview in self.view.subviews) {
        if ([subview isKindOfClass:[NSButton class]] &&
            ((NSButton *)subview).action == @selector(cancel:)) {
            return (NSButton *)subview;
        }
    }
    return nil;
}

- (void)createKeystrokePassthroughButton {
    if (_keystrokePassthroughButton) {
        return;
    }
    NSButton *cancel = [self cancelButton];
    if (!cancel) {
        return;
    }
    const NSRect cancelFrame = cancel.frame;
    const NSRect frame = NSMakeRect(NSMinX(cancelFrame) - NSWidth(cancelFrame) - kKeystrokePassthroughButtonGap,
                                    NSMinY(cancelFrame),
                                    NSWidth(cancelFrame),
                                    NSHeight(cancelFrame));
    // Autoreleased: it lives as a permanent subview of self.view (never removed,
    // only shown/hidden), so the superview's retain is the only ownership we need
    // and the bare ivar is a weak-style back-reference.
    NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];
    button.autoresizingMask = cancel.autoresizingMask;
    button.bezelStyle = cancel.bezelStyle;
    button.bordered = cancel.bordered;
    button.controlSize = cancel.controlSize;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    [button setButtonType:NSButtonTypePushOnPushOff];
    button.image = [NSImage it_imageForSymbolName:SFSymbolGetString(SFSymbolKeyboard)
                             accessibilityDescription:NSLocalizedStringWithDefaultValue(@"PasteView.SendKeystrokesAccessibility", nil, [NSBundle mainBundle], @"Send keystrokes to terminal", @"Accessibility label for the button that sends keystrokes directly to the terminal")];
    button.target = self;
    button.action = @selector(toggleKeystrokePassthrough:);
    button.toolTip =
        NSLocalizedStringWithDefaultValue(@"PasteView.KeystrokeToolTip", nil, [NSBundle mainBundle], @"Type directly to the terminal (for example to answer a password prompt) "
        @"instead of queueing your keystrokes until the paste finishes.", @"Tooltip for the button that sends keystrokes directly to the terminal during a paste");
    button.hidden = YES;
    [self.view addSubview:button];
    _keystrokePassthroughButton = button;
    [self updateKeystrokePassthroughButtonAppearance];
}

// Tint the keyboard icon with the accent color while passthrough is on, so its
// state is obvious in addition to the push-on/push-off bezel.
- (void)updateKeystrokePassthroughButtonAppearance {
    const BOOL on = (_keystrokePassthroughButton.state == NSControlStateValueOn);
    _keystrokePassthroughButton.contentTintColor = on ? [NSColor controlAccentColor] : nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    if (_mini) {
        return;
    }
    if ([iTermAdvancedSettingsModel useOldStyleDropDownViews]) {
        return;
    }

    NSShadow *shadow = [[[NSShadow alloc] init] autorelease];
    shadow.shadowOffset = NSMakeSize(2, -2);
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.3];
    shadow.shadowBlurRadius = 2;

    self.view.wantsLayer = YES;
    [self.view makeBackingLayer];
    self.view.shadow = shadow;
}

- (void)viewDidAppear {
    [self updateLabelColor];
}

- (void)updateLabelColor {
    PseudoTerminal* term = [[self.view window] windowController];
    if ([term isKindOfClass:[PseudoTerminal class]]) {
        _label.textColor = [term accessoryTextColorForMini:self.mini];
    }
    if (!self.mini) {
        return;
    }
    if (_label.textColor.perceivedBrightness > 0.5) {
        progressIndicator_.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    } else {
        progressIndicator_.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    }
}

- (IBAction)cancel:(id)sender {
    [delegate_ pasteViewControllerDidCancel];
}

- (IBAction)toggleKeystrokePassthrough:(id)sender {
    // The user engaged the control, so the hint has served its purpose.
    [self hideKeystrokeQueuedHint];
    [self updateKeystrokePassthroughButtonAppearance];
    [delegate_ pasteViewControllerDidSetKeystrokePassthrough:(_keystrokePassthroughButton.state == NSControlStateValueOn)];
}

- (void)showKeystrokeQueuedHint {
    if (!_keystrokePassthroughButton || _keystrokePassthroughButton.hidden) {
        return;
    }
    NSView *content = self.view.window.contentView;
    if (!content) {
        return;
    }
    if (!_queuedHintView) {
        _queuedHintView = [[iTermPasteQueuedHintView alloc] initWithFrame:NSZeroRect];
        _queuedHintView.message = NSLocalizedStringWithDefaultValue(@"PasteView.QueuedHint", nil, [NSBundle mainBundle], @"Typing is queued while pasting. Click the keyboard to toggle queueing.", @"Hint shown while pasting explaining that keystrokes are queued");
    }
    const NSRect buttonFrame = [_keystrokePassthroughButton convertRect:_keystrokePassthroughButton.bounds
                                                                 toView:content];
    const NSSize size = [_queuedHintView sizeThatFitsMaxWidth:220];
    // If the button is in the top half of the window, drop the callout below it
    // (pointer up); otherwise (e.g. a bottom status bar) float it above.
    const BOOL below = NSMidY(buttonFrame) > NSMidY(content.bounds);
    _queuedHintView.pointerOnTopEdge = below;

    CGFloat originX = NSMidX(buttonFrame) - size.width / 2;
    originX = MAX(2, MIN(NSWidth(content.bounds) - size.width - 2, originX));
    const CGFloat gap = 1;
    const CGFloat originY = below ? (NSMinY(buttonFrame) - size.height - gap)
                                  : (NSMaxY(buttonFrame) + gap);
    _queuedHintView.frame = NSMakeRect(originX, originY, size.width, size.height);
    _queuedHintView.pointerX = NSMidX(buttonFrame) - originX;
    [_queuedHintView setNeedsDisplay:YES];

    // Invalidate any pending dismissal removal (see the generation check in hide).
    _hintGeneration++;
    if (!_hintPresented) {
        // Either brand new or interrupting a fade-out; (re)present with a spring.
        _hintPresented = YES;
        if (_queuedHintView.superview != content) {
            [content addSubview:_queuedHintView];
        }
        [_queuedHintView animateIn];
    }
    // If already presented, leave it in place (don't re-bounce on every key) and
    // just re-arm the dismiss timer below.

    [_queuedHintDismissTimer invalidate];
    _queuedHintDismissTimer = [NSTimer scheduledTimerWithTimeInterval:4.0
                                                               target:self
                                                             selector:@selector(hideKeystrokeQueuedHint)
                                                             userInfo:nil
                                                              repeats:NO];
}

- (void)hideKeystrokeQueuedHint {
    [_queuedHintDismissTimer invalidate];
    _queuedHintDismissTimer = nil;
    if (!_hintPresented) {
        return;
    }
    _hintPresented = NO;
    if (!_queuedHintView.superview) {
        return;
    }
    // Retained by the block copy (and by our ivar) for the animation's duration.
    // Only actually remove it if no show happened in the meantime (a re-show
    // bumps the generation and re-presents the same view).
    const NSInteger generation = _hintGeneration;
    iTermPasteQueuedHintView *hint = _queuedHintView;
    __typeof(self) controller = self;
    [hint animateOutWithCompletion:^{
        if (controller->_hintGeneration == generation) {
            [hint removeFromSuperview];
        }
    }];
}

// Used when the whole paste indicator is going away: the hint must disappear at
// once, not fade out over the closing panel.
- (void)removeKeystrokeQueuedHintImmediately {
    [_queuedHintDismissTimer invalidate];
    _queuedHintDismissTimer = nil;
    _hintPresented = NO;
    _hintGeneration++;  // invalidate any pending deferred removal
    [_queuedHintView.layer removeAllAnimations];
    [_queuedHintView removeFromSuperview];
}

- (void)setWaitingForPrompt:(BOOL)waitingForPrompt {
    if (!_keystrokePassthroughButton) {
        return;
    }
    if (_keystrokePassthroughButton.hidden != waitingForPrompt) {
        // No change; avoid double-applying the progress-bar resize below.
        return;
    }
    _keystrokePassthroughButton.hidden = !waitingForPrompt;
    // Make room for (or reclaim room from) the button so it doesn't overlap the
    // progress bar.
    const CGFloat dx = NSWidth(_keystrokePassthroughButton.frame) + kKeystrokePassthroughButtonGap;
    NSRect progressFrame = progressIndicator_.frame;
    progressFrame.size.width += waitingForPrompt ? -dx : dx;
    progressIndicator_.frame = progressFrame;

    if (!waitingForPrompt) {
        // The button is gone; the hint has nothing to point at.
        [self hideKeystrokeQueuedHint];
    }
}

- (void)setRemainingLength:(int)remainingLength {
    remainingLength_ = remainingLength;
    double ratio = remainingLength;
    ratio /= (double)totalLength_;
    [progressIndicator_ setDoubleValue:1.0 - ratio];
    [progressIndicator_ displayIfNeeded];
}

- (void)updateFrame {
    NSRect newFrame = self.view.frame;
    newFrame.origin.y = self.view.superview.frame.size.height;
    self.view.frame = newFrame;

    newFrame.origin.y += self.view.frame.size.height;
    newFrame = NSMakeRect(self.view.frame.origin.x,
                          self.view.superview.frame.size.height - self.view.frame.size.height,
                          self.view.frame.size.width,
                          self.view.frame.size.height);
    [[NSAnimationContext currentContext] setDuration:kAnimationDuration];
    self.view.frame = newFrame;
    self.view.animator.alphaValue = 1;
}

- (void)closeWithCompletion:(void (^)(void))completion {
    [self removeKeystrokeQueuedHintImmediately];
    NSRect newFrame = self.view.frame;
    newFrame.origin.y = self.view.superview.frame.size.height;
    [[NSAnimationContext currentContext] setDuration:kAnimationDuration];
    self.view.animator.alphaValue = 0;
    [self.view performSelector:@selector(removeFromSuperview) withObject:nil afterDelay:kAnimationDuration];
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        completion();
    }];
}

- (void)themeDidChange:(id)sender {
    [self updateLabelColor];
}

@end
