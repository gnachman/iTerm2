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

@interface iTermMinimalComposerViewController ()<iTermComposerTextViewDelegate, iTermDragHandleViewDelegate, iTermStatusBarLargeComposerViewControllerDelegate>
@end

@implementation iTermMinimalComposerViewController {
    IBOutlet iTermStatusBarLargeComposerViewController *_largeComposerViewController;
    IBOutlet NSView *_containerView;
    IBOutlet NSVisualEffectView *_vev;
    IBOutlet iTermDragHandleView *_bottomDragHandle;
    IBOutlet iTermDragHandleView *_topDragHandle;
    IBOutlet NSButton *_closeButton;
    IBOutlet NSView *_wrapper;
    CGFloat _manualHeight;
}

- (instancetype)init {
    self = [super initWithNibName:NSStringFromClass(self.class) bundle:[NSBundle bundleForClass:self.class]];
    if (self) {
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{ iTermMinimalComposerViewHeightUserDefaultsKey: @135 }];
        _manualHeight = [[NSUserDefaults standardUserDefaults] doubleForKey:iTermMinimalComposerViewHeightUserDefaultsKey];
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

    [self setIsAutoComposer:_isAutoComposer];
}

- (void)setIsAutoComposer:(BOOL)isAutoComposer {
    _isAutoComposer = isAutoComposer;
    _largeComposerViewController.hideAccessories = isAutoComposer;
    _closeButton.hidden = isAutoComposer;
    const NSRect bounds = self.view.bounds;
    if (isAutoComposer) {
        const CGFloat margin = 0;
        _wrapper.frame = NSMakeRect(margin,
                                    margin,
                                    bounds.size.width - margin * 2,
                                    bounds.size.height - margin * 2);
    } else {
        const CGFloat margin = 9;
        _wrapper.frame = NSMakeRect(margin,
                                    margin,
                                    bounds.size.width - margin * 2,
                                    bounds.size.height - margin * 2);
    }
    _topDragHandle.hidden = isAutoComposer;
    _bottomDragHandle.hidden = isAutoComposer;
    _vev.hidden = isAutoComposer;
}

- (void)setFont:(NSFont *)font {
    _largeComposerViewController.textView.font = font;
}

- (void)setHost:(id<VT100RemoteHostReading>)host
workingDirectory:(NSString *)pwd
          scope:(iTermVariableScope *)scope
 tmuxController:(nonnull TmuxController *)tmuxController {
    [self view];
    _largeComposerViewController.host = host;
    _largeComposerViewController.workingDirectory = pwd;
    _largeComposerViewController.scope = scope;
    _largeComposerViewController.tmuxController = tmuxController;
}

- (NSRect)frameForHeight:(CGFloat)desiredHeight {
    return [self.delegate minimalComposer:self frameForHeight:desiredHeight];
}

- (CGFloat)lineHeight {
    return [@" " sizeWithAttributes:@{ NSFontAttributeName: _largeComposerViewController.textView.font } ].height;
}

- (CGFloat)minHeight {
    if (self.isAutoComposer) {
        return self.lineHeight;
    }
    return 62;
}

- (CGFloat)maxHeight {
    const CGFloat maximumHeight = [self.delegate minimalComposerMaximumHeight:self];
    return MAX(self.minHeight, maximumHeight);
}

- (NSUInteger)numberOfLinesInTextView:(NSTextView *)textView {
    NSLayoutManager *layoutManager = [textView layoutManager];
    const NSUInteger numberOfGlyphs = [layoutManager numberOfGlyphs];
    const NSRange glyphRange = NSMakeRange(0, numberOfGlyphs);
    NSUInteger numberOfLines = 0;
    NSUInteger index = 0;
    while (index < numberOfGlyphs) {
        NSRange lineRange = { 0 };
        [layoutManager lineFragmentRectForGlyphAtIndex:index effectiveRange:&lineRange];
        index = NSMaxRange(lineRange);
        numberOfLines++;
        if (NSMaxRange(lineRange) == NSMaxRange(glyphRange)) {
            break;
        }
    }
    return numberOfLines;
}

- (CGFloat)desiredHeight {
    if (self.isAutoComposer) {
        NSTextView *textView = _largeComposerViewController.textView;
        const NSUInteger numberOfLines = [self numberOfLinesInTextView:textView];
        const CGFloat lineHeight = [self.delegate minimalComposerLineHeight:self];
        return MAX(1, numberOfLines) * lineHeight;
    }
    return _manualHeight;
}

- (void)updateFrame {
    self.view.frame = [self frameForHeight:MAX(MIN(self.maxHeight, [self desiredHeight]), self.minHeight)];
    [[NSAnimationContext currentContext] setDuration:kAnimationDuration];
    self.view.animator.alphaValue = 1;
    [self.delegate minimalComposer:self frameDidChangeTo:self.view.frame];

    const BOOL onBottom = (self.view.frame.origin.y == 0);
    _topDragHandle.hidden = !onBottom;
    _bottomDragHandle.hidden = onBottom;
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

- (void)composerTextViewEnqueue:(NSString *)string {
    [self.delegate minimalComposer:self enqueueCommand:string dismiss:NO];
}

#pragma mark - iTermDragHandleViewDelegate

- (CGFloat)dragHandleView:(iTermDragHandleView *)dragHandle didMoveBy:(CGFloat)movement {
    CGFloat delta = movement;
    if (dragHandle == _topDragHandle) {
        delta = -delta;
    }
    const CGFloat originalHeight = NSHeight(self.view.frame);
    _manualHeight -= delta;
    const CGFloat proposedHeight = NSHeight([self frameForHeight:_manualHeight]);

    if (proposedHeight < self.minHeight) {
        const CGFloat error = self.minHeight - proposedHeight;
        delta -= error;
        _manualHeight += error;
    } else if (proposedHeight > self.maxHeight) {
        const CGFloat error = proposedHeight - self.maxHeight;
        delta += error;
        _manualHeight -= error;
    }
    [[NSUserDefaults standardUserDefaults] setDouble:_manualHeight
                                              forKey:iTermMinimalComposerViewHeightUserDefaultsKey];
    [self updateFrame];
    CGFloat actual = originalHeight - NSHeight(self.view.frame);
    if (dragHandle == _topDragHandle) {
        actual = -actual;
    }
    return actual;
}

- (void)largeComposerViewControllerTextDidChange:(nonnull iTermStatusBarLargeComposerViewController *)controller {
    if (!self.isAutoComposer) {
        return;
    }
    [self updateFrame];
}

@end
