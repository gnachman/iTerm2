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
#import "NSArray+iTerm.h"

static float kAnimationDuration = 0.25;
static NSString *const iTermMinimalComposerViewHeightUserDefaultsKey = @"ComposerHeight";

@class iTermMinimalComposerView;

@protocol iTermMinimalComposerViewDelegate<NSObject>
- (void)minimalComposerViewDidDrag:(iTermMinimalComposerView *)composerView;
@end

@interface iTermMinimalComposerView : NSView
@property (nonatomic, weak) IBOutlet id<iTermMinimalComposerViewDelegate> delegate;
@property (nonatomic) BOOL draggable;
@end

@implementation iTermMinimalComposerView

- (BOOL)it_focusFollowsMouseImmune {
    return YES;
}

// Track mouse movements when it enters the view
- (void)updateTrackingAreas {
    [super updateTrackingAreas];

    // Remove old tracking areas
    for (NSTrackingArea *area in self.trackingAreas) {
        [self removeTrackingArea:area];
    }

    // Create a new tracking area
    NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                                options:(NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveAlways)
                                                                  owner:self
                                                               userInfo:nil];
    [self addTrackingArea:trackingArea];
}

// Called when mouse moves
- (void)mouseMoved:(NSEvent *)event {
    NSPoint mouseLocation = [self.superview convertPoint:event.locationInWindow fromView:nil];
    NSView *hitView = [self hitTest:mouseLocation];

    // Check if the hit view is this view (not a subview)
    if (hitView == self) {
        [[NSCursor openHandCursor] set];
    }

    [super mouseMoved:event];
}

// Reset cursor when mouse exits the view
- (void)mouseExited:(NSEvent *)event {
    [[NSCursor arrowCursor] set];
    [super mouseExited:event];
}

- (void)mouseDown:(NSEvent *)event {
    NSView *superview = self.superview;
    if (!superview || !self.draggable) {
        return;
    }

    const NSPoint mouseDownLocation = event.locationInWindow;
    const NSPoint originalOrigin = [superview convertPoint:self.frame.origin toView:nil];

    [[self window] trackEventsMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)
                                  timeout:NSEventDurationForever
                                     mode:NSEventTrackingRunLoopMode
                                handler:^(NSEvent *trackingEvent, BOOL *stop) {
        switch (trackingEvent.type) {
            case NSEventTypeLeftMouseDragged: {
                // Calculate the drag offset
                const NSPoint currentLocation = trackingEvent.locationInWindow;
                const CGFloat deltaY = currentLocation.y - mouseDownLocation.y;
                const NSPoint newOrigin = NSMakePoint(originalOrigin.x, originalOrigin.y + deltaY);

                NSPoint frameOrigin = [superview convertPoint:newOrigin fromView:nil];
                frameOrigin.y = MAX(0, MIN(frameOrigin.y, superview.bounds.size.height - self.frame.size.height));

                [self setFrameOrigin:frameOrigin];
                break;
            }
            case NSEventTypeLeftMouseUp:
                *stop = YES;
                break;

            default:
                break;
        }
    }];
    [self.delegate minimalComposerViewDidDrag:self];
}

- (void)setDelegate:(id<iTermMinimalComposerViewDelegate>)delegate {
    _delegate = delegate;
}

@end

@interface iTermMinimalComposerViewController ()<iTermComposerTextViewDelegate, iTermDragHandleViewDelegate, iTermStatusBarLargeComposerViewControllerDelegate, iTermMinimalComposerViewDelegate>
@end

@implementation iTermMinimalComposerViewController {
    IBOutlet iTermStatusBarLargeComposerViewController *_largeComposerViewController;
    IBOutlet NSView *_containerView;
    IBOutlet NSVisualEffectView *_vev;
    IBOutlet iTermDragHandleView *_bottomDragHandle;
    IBOutlet iTermDragHandleView *_topDragHandle;
    IBOutlet NSButton *_closeButton;
    IBOutlet NSView *_wrapper;
    IBOutlet NSView *_separator;
    iTermCompletionsWindow *_completionsWindow;
    CGFloat _manualHeight;
    CGFloat _desiredHeight;
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

    _separator.wantsLayer = YES;
    _separator.layer = [[CALayer alloc] init];

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
    if (isAutoComposer) {
        [_topDragHandle removeFromSuperview];
        [_bottomDragHandle removeFromSuperview];
    } else if (_bottomDragHandle.superview == nil) {
        // Insert them prior to _closeButton.
        [self.view insertSubview:_topDragHandle atIndex:self.view.subviews.count - 1];
        [self.view insertSubview:_bottomDragHandle atIndex:self.view.subviews.count - 1];
    }
    _vev.hidden = isAutoComposer;
}

- (void)viewWillLayout {
    [super viewWillLayout];
    [self layoutSubviews];
}

- (void)setFont:(NSFont *)font {
    _largeComposerViewController.textView.font = font;
    [self layoutSubviews];
}

- (void)setTextColor:(NSColor *)textColor cursorColor:(nonnull NSColor *)cursorColor {
    _largeComposerViewController.textView.textColor = textColor;
    _largeComposerViewController.textView.prefixColor = textColor;
    _largeComposerViewController.textView.insertionPointColor = cursorColor;
}

- (void)setPrefix:(NSMutableAttributedString *)prefix {
    _largeComposerViewController.textView.prefix = prefix;
}

- (BOOL)composerIsFirstResponder {
    NSWindow *window = _largeComposerViewController.textView.window;
    if (!window) {
        return NO;
    }
    return window.firstResponder == _largeComposerViewController.textView;
}

- (void)setIsSeparatorVisible:(BOOL)isSeparatorVisible {
    _separator.hidden = !isSeparatorVisible;
    _isSeparatorVisible = isSeparatorVisible;
    ((iTermMinimalComposerView *)self.view).draggable = !isSeparatorVisible;
    [self layoutSubviews];
}

- (void)layoutSubviews {
    if (self.isSeparatorVisible) {
        const CGFloat offset = self.lineHeight / 2.0;
        _largeComposerViewController.view.frame = NSMakeRect(0, 0, self.view.bounds.size.width, self.view.bounds.size.height - offset);
    } else {
        _largeComposerViewController.view.frame = _containerView.bounds;
    }
}

- (void)setSeparatorColor:(NSColor *)separatorColor {
    _separator.layer.backgroundColor = separatorColor.CGColor;
    _separatorColor = separatorColor;
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
    if (self.delegate) {
        const CGFloat height = [self.delegate minimalComposerLineHeight:self];
        DLog(@"Using delegate-provided line height of %@", @(height));
        return height;
    }
    const CGFloat height = [@" " sizeWithAttributes:@{ NSFontAttributeName: _largeComposerViewController.textView.font } ].height;
    DLog(@"Using fallback line height of %@", @(height));
    return height;
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

- (NSUInteger)numberOfLinesInTextView:(iTermComposerTextView *)textView {
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
    if ([textView.stringExcludingPrefix hasSuffix:@"\n"]) {
        numberOfLines += 1;
    }
    return numberOfLines;
}

- (CGFloat)desiredHeight {
    if (self.isAutoComposer) {
        DLog(@"Computing desired height for autocomposer");
        iTermComposerTextView *textView = _largeComposerViewController.textView;
        const NSUInteger numberOfLines = [self numberOfLinesInTextView:textView];
        DLog(@"textView has %@ lines. Its contents are:\n%@",
             @(numberOfLines), textView.textStorage.string);
        const CGFloat lineHeight = [self.delegate minimalComposerLineHeight:self];
        DLog(@"Line height is %@", @(lineHeight));
        const CGFloat height = MAX(1, numberOfLines) * lineHeight;
        DLog(@"Desired height is %@", @(height));
        return height;
    }
    return _manualHeight;
}

- (void)updateFrame {
    const NSRect desiredFrame = [self frameForHeight:MAX(MIN(self.maxHeight, [self desiredHeight]), self.minHeight)];
    if (NSEqualRects(desiredFrame, self.view.frame)) {
        return;
    }
    DLog(@"desiredFrame=%@", NSStringFromRect(desiredFrame));
    self.view.frame = desiredFrame;
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
    [self.delegate minimalComposer:self
                       sendCommand:@""
                        addNewline:YES
                           dismiss:YES];
}

- (NSString *)stringValue {
    return _largeComposerViewController.textView.stringExcludingPrefix;
}

- (void)setString:(NSString *)stringValue includingPrefix:(BOOL)includingPrefix {
    if (includingPrefix) {
        [_largeComposerViewController.textView setStringIncludingPrefix:stringValue];
    } else {
        [_largeComposerViewController.textView setStringExcludingPrefix:stringValue];
    }
    [_largeComposerViewController.textView it_scrollCursorToVisible];
}

- (void)insertText:(NSString *)text {
    [_largeComposerViewController.textView insertText:text];
}

- (void)deleteLastCharacter {
    NSTextView *textView = _largeComposerViewController.textView;
    [textView setSelectedRange:NSMakeRange(textView.string.length, 0)];
    [textView deleteBackward:nil];
}

- (void)paste:(id)sender {
    [_largeComposerViewController.textView paste:sender];
}

- (NSRect)cursorFrameInScreenCoordinates {
    return _largeComposerViewController.textView.cursorFrameInScreenCoordinates;
}

- (NSResponder *)nextResponder {
    NSResponder *custom = [self.delegate minimalComposerNextResponder];
    if (custom) {
        return custom;
    }
    return [super nextResponder];
}

#pragma mark - iTermComposerTextViewDelegate

- (void)composerTextViewSendSubstring:(NSString*)string {
    [self.delegate minimalComposer:self
                       sendCommand:string
                        addNewline:NO
                           dismiss:NO];
}

- (void)composerTextViewDidFinishWithCancel:(BOOL)cancel {
    NSString *string = cancel ? @"" : _largeComposerViewController.textView.stringExcludingPrefix;
    [self.delegate minimalComposer:self 
                       sendCommand:string ?: @""
                        addNewline:YES
                           dismiss:YES];
}

- (BOOL)composerHandleKeyDownWithEvent:(NSEvent *)event {
    return [self.delegate minimalComposerHandleKeyDown:event];
}

- (void)composerTextViewDidResignFirstResponder {
}

- (void)composerTextViewDidBecomeFirstResponder {
    [self.delegate minimalComposerDidBecomeFirstResponder:self];
}

- (void)composerTextViewSendToAdvancedPaste:(NSString *)content {
    [self.delegate minimalComposer:self sendToAdvancedPaste:content];
}

- (void)composerTextViewSend:(NSString *)string {
    [self.delegate minimalComposer:self 
                       sendCommand:string
                        addNewline:YES
                           dismiss:NO];
}

- (void)composerTextViewEnqueue:(NSString *)string {
    [self.delegate minimalComposer:self enqueueCommand:string dismiss:NO];
}

- (void)composerTextViewSendControl:(NSString *)control {
    [self.delegate minimalComposer:self sendControl:control];
}

- (void)composerTextViewOpenHistoryWithPrefix:(NSString *)prefix forSearch:(BOOL)forSearch {
    [self.delegate minimalComposerOpenHistory:self prefix:prefix forSearch:forSearch];
}

- (void)composerTextViewShowCompletions {
    [_largeComposerViewController fetchCompletions];
}

- (BOOL)composerTextViewWantsKeyEquivalent:(NSEvent *)event {
    return [self.delegate minimalComposer:self wantsKeyEquivalent:event];
}

- (void)composerTextViewPerformFindPanelAction:(id)sender {
    [self.delegate minimalComposer:self performFindPanelAction:sender];
}

- (void)composerTextViewClear {
    [self.delegate minimalComposerClear:self];
}

- (id<iTermSyntaxHighlighting>)composerSyntaxHighlighterForAttributedString:(NSMutableAttributedString *)textStorage {
    return [self.delegate minimalComposer:self syntaxHighlighterForAttributedString:textStorage];
}

- (BOOL)composerTextViewShouldForwardCopy {
    return [self.delegate minimalComposerShouldForwardCopy:self];
}

- (void)composerForwardMenuItem:(NSMenuItem *)menuItem {
    [self.delegate minimalComposerForwardMenuItem:menuItem];
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
    [self.delegate minimalComposerAutoComposerTextDidChange:self];
    const CGFloat desiredHeight = [self desiredHeight];
    if (desiredHeight == _desiredHeight) {
        return;
    }
    _desiredHeight = desiredHeight;
    [self.delegate minimalComposer:self desiredHeightDidChange:desiredHeight];
}

- (BOOL)largeComposerViewControllerShouldFetchSuggestions:(iTermStatusBarLargeComposerViewController *)controller
                                                  forHost:(id<VT100RemoteHostReading>)remoteHost
                                           tmuxController:(TmuxController *)tmuxController {
    return [self.delegate minimalComposerShouldFetchSuggestions:self forHost:remoteHost tmuxController:tmuxController];
}

- (void)largeComposerViewController:(iTermStatusBarLargeComposerViewController *)controller
                   fetchSuggestions:(iTermSuggestionRequest *)request
                      byUserRequest:(BOOL)byUserRequest {
    [self.delegate minimalComposer:self
                  fetchSuggestions:request
                     byUserRequest:byUserRequest];
}

- (NSString *)largeComposerViewController:(iTermStatusBarLargeComposerViewController *)controller
               valueOfEnvironmentVariable:(NSString *)name {
    return [self.delegate minimalComposer:self valueOfEnvironmentVariable:name];
}

#pragma mark - iTermMinimalComposerViewDelegate

- (void)minimalComposerViewDidDrag:(iTermMinimalComposerView *)composerView {
    _preferredOffsetFromTop = NSHeight(composerView.superview.bounds) - NSMaxY(composerView.frame);
    [self.delegate minimalComposerPreferredOffsetFromTopDidChange:self];
}

@end
