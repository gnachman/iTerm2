//
//  iTermMinimalComposerViewController.m
//  iTerm2
//
//  Created by George Nachman on 3/31/20.
//

#import "iTermMinimalComposerViewController.h"

#import "iTermDragHandleView.h"
#import "iTermStatusBarLargeComposerViewController.h"
#import "iTerm2SharedARC-Swift.h"

static float kAnimationDuration = 0.25;
static NSString *const iTermMinimalComposerViewHeightUserDefaultsKey = @"ComposerHeight";

@interface iTermMinimalComposerViewController ()<iTermComposerTextViewDelegate, iTermDragHandleViewDelegate>
@end

@implementation iTermMinimalComposerViewController {
    IBOutlet iTermStatusBarLargeComposerViewController *_largeComposerViewController;
    IBOutlet NSView *_containerView;
    IBOutlet NSVisualEffectView *_vev;
    CGFloat _desiredHeight;
}

- (instancetype)init {
    self = [super initWithNibName:NSStringFromClass(self.class) bundle:[NSBundle bundleForClass:self.class]];
    if (self) {
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{ iTermMinimalComposerViewHeightUserDefaultsKey: @135 }];
        _desiredHeight = [[NSUserDefaults standardUserDefaults] doubleForKey:iTermMinimalComposerViewHeightUserDefaultsKey];
    }
    return self;
}

- (void)awakeFromNib {
    [_containerView addSubview:_largeComposerViewController.view];
    _containerView.autoresizesSubviews = YES;

    _largeComposerViewController.view.frame = _containerView.bounds;
    _largeComposerViewController.textView.composerDelegate = self;
    _largeComposerViewController.view.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
    _vev.layer.cornerRadius = 6;
    _vev.layer.borderColor = [[NSColor grayColor] CGColor];
    _vev.layer.borderWidth = 1;
}

- (void)setFont:(NSFont *)font {
    _largeComposerViewController.textView.font = font;
}

- (void)setHost:(id<VT100RemoteHostReading>)host workingDirectory:(NSString *)pwd shell:(NSString *)shell tmuxController:(nonnull TmuxController *)tmuxController {
    [self view];
    _largeComposerViewController.host = host;
    _largeComposerViewController.workingDirectory = pwd;
    _largeComposerViewController.shell = shell;
    _largeComposerViewController.tmuxController = tmuxController;
}

- (NSRect)frameForHeight:(CGFloat)desiredHeight {
    NSRect newFrame = self.view.frame;
    newFrame.origin.y = self.view.superview.frame.size.height;

    newFrame.origin.y += newFrame.size.height;
    const CGFloat maxWidth = self.view.superview.bounds.size.width - newFrame.origin.x - 19;
    newFrame = NSMakeRect(newFrame.origin.x,
                          self.view.superview.frame.size.height - desiredHeight,
                          MAX(217, maxWidth),
                          desiredHeight);
    return newFrame;
}

- (CGFloat)minHeight {
    return 62;
}

- (CGFloat)maxHeight {
    return MAX(self.minHeight, NSHeight(self.view.superview.bounds) - 8);
}

- (void)updateFrame {
    self.view.frame = [self frameForHeight:MAX(MIN(self.maxHeight, _desiredHeight), self.minHeight)];
    [[NSAnimationContext currentContext] setDuration:kAnimationDuration];
    self.view.animator.alphaValue = 1;
}

- (void)makeFirstResponder {
    [_largeComposerViewController.textView.window makeFirstResponder:_largeComposerViewController.textView];
}

- (IBAction)performClose:(id)sender {
    [self.delegate minimalComposer:self sendCommand:@"" dismiss:YES];
}

- (NSString *)stringValue {
    return _largeComposerViewController.textView.string;
}

- (void)setStringValue:(NSString *)stringValue {
    _largeComposerViewController.textView.string = stringValue;
    [_largeComposerViewController.textView it_scrollCursorToVisible];
}

#pragma mark - iTermComposerTextViewDelegate

- (void)composerTextViewDidFinishWithCancel:(BOOL)cancel {
    NSString *string = cancel ? @"" : _largeComposerViewController.textView.string;
    [self.delegate minimalComposer:self sendCommand:string ?: @"" dismiss:YES];
}

- (void)composerTextViewDidResignFirstResponder {
}

- (void)composerTextViewSendToAdvancedPaste:(NSString *)content {
    [self.delegate minimalComposer:self sendToAdvancedPaste:content];
}

- (void)composerTextViewSend:(NSString *)string {
    [self.delegate minimalComposer:self sendCommand:string dismiss:NO];
}

#pragma mark - iTermDragHandleViewDelegate

- (CGFloat)dragHandleView:(iTermDragHandleView *)dragHandle didMoveBy:(CGFloat)delta {
    const CGFloat originalHeight = NSHeight(self.view.frame);
    _desiredHeight -= delta;
    const CGFloat proposedHeight = NSHeight([self frameForHeight:_desiredHeight]);

    if (proposedHeight < self.minHeight) {
        const CGFloat error = self.minHeight - proposedHeight;
        delta -= error;
        _desiredHeight += error;
    } else if (proposedHeight > self.maxHeight) {
        const CGFloat error = proposedHeight - self.maxHeight;
        delta += error;
        _desiredHeight -= error;
    }
    [[NSUserDefaults standardUserDefaults] setDouble:_desiredHeight
                                              forKey:iTermMinimalComposerViewHeightUserDefaultsKey];
    [self updateFrame];
    return originalHeight - NSHeight(self.view.frame);
}

@end
