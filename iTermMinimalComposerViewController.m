//
//  iTermMinimalComposerViewController.m
//  iTerm2
//
//  Created by George Nachman on 3/31/20.
//

#import "iTermMinimalComposerViewController.h"

#import "CommandHistoryPopup.h"
#import "iTermDragHandleView.h"
#import "iTermStatusBarLargeComposerViewController.h"
#import "iTerm2SharedARC-Swift.h"

static float kAnimationDuration = 0.25;
static NSString *const iTermMinimalComposerViewHeightUserDefaultsKey = @"ComposerHeight";

@interface iTermMinimalComposerViewController ()<PopupDelegate, iTermComposerTextViewDelegate, iTermDragHandleViewDelegate, iTermPopupWindowPresenter, iTermStatusBarLargeComposerViewControllerDelegate>
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
    CommandHistoryPopupWindowController *_historyWindowController;
    CGFloat _manualHeight;
    CGFloat _desiredHeight;
    NSInteger _fetches;
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
        iTermComposerTextView *textView = _largeComposerViewController.textView;
        const NSUInteger numberOfLines = [self numberOfLinesInTextView:textView];
        const CGFloat lineHeight = [self.delegate minimalComposerLineHeight:self];
        return MAX(1, numberOfLines) * lineHeight;
    }
    return _manualHeight;
}

- (void)updateFrame {
    const NSRect desiredFrame = [self frameForHeight:MAX(MIN(self.maxHeight, [self desiredHeight]), self.minHeight)];
    if (NSEqualRects(desiredFrame, self.view.frame)) {
        return;
    }
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
    [self.delegate minimalComposer:self sendCommand:@"" dismiss:YES];
}

- (NSString *)stringValue {
    return _largeComposerViewController.textView.stringExcludingPrefix;
}

- (void)setStringValue:(NSString *)stringValue {
    _largeComposerViewController.textView.stringExcludingPrefix = stringValue;
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

- (void)composerTextViewDidFinishWithCancel:(BOOL)cancel {
    NSString *string = cancel ? @"" : _largeComposerViewController.textView.stringExcludingPrefix;
    [self.delegate minimalComposer:self sendCommand:string ?: @"" dismiss:YES];
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
    [self.delegate minimalComposer:self sendCommand:string dismiss:NO];
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
    _fetches += 1;
    __weak __typeof(self) weakSelf = self;
    [_largeComposerViewController fetchCompletions:^(NSString *prefix, NSArray<NSString *> *completions) {
        [weakSelf didFetchCompletions:completions forPrefix:prefix];
    }];
}

- (void)didFetchCompletions:(NSArray<NSString *> *)completions forPrefix:(NSString *)prefix {
    _fetches -= 1;
    if (_fetches > 0 || completions.count == 0) {
        return;
    }
    if (!_historyWindowController) {
        _historyWindowController = [[CommandHistoryPopupWindowController alloc] initForAutoComplete:NO];
        _historyWindowController.forwardKeyDown = YES;
    }
    [_historyWindowController popWithDelegate:self inWindow:self.view.window];
    [_historyWindowController loadCommands:completions
                            partialCommand:prefix
                       sortChronologically:NO];
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
                   fetchSuggestions:(iTermSuggestionRequest *)request {
    [self.delegate minimalComposer:self fetchSuggestions:request];
}

#pragma mark - PopupDelegate

- (BOOL)popupWindowShouldAvoidChangingWindowOrderOnClose {
    return NO;
}

- (NSRect)popupScreenVisibleFrame {
    return self.view.window.screen.visibleFrame;
}

- (VT100Screen *)popupVT100Screen {
    return nil;
}

- (id<iTermPopupWindowPresenter>)popupPresenter {
    return self;
}

- (void)popupInsertText:(NSString *)text {
    [_largeComposerViewController.textView insertText:text
                                     replacementRange:_largeComposerViewController.textView.selectedRange];
}

- (void)popupPreview:(NSString *)text {
}

- (void)popupKeyDown:(NSEvent *)event {
    [_largeComposerViewController.textView keyDown:event];
}

- (BOOL)popupHandleSelector:(SEL)selector string:(NSString *)string currentValue:(NSString *)currentValue {
    return NO;
}

- (void)popupWillClose:(iTermPopupWindowController *)popup {
    _historyWindowController = nil;
}

- (BOOL)popupWindowIsInFloatingHotkeyWindow {
    id<iTermWindowController> windowController = (id<iTermWindowController>)self.view.window.delegate;
    if ([windowController conformsToProtocol:@protocol(iTermWindowController)]) {
        return [windowController isFloatingHotKeyWindow];
    }
    return NO;
}

- (void)popupIsSearching:(BOOL)searching {
}

- (BOOL)popupShouldTakePrefixFromScreen {
    return NO;
}

// This is only called by Autocomplete
- (NSArray<NSString *> *)popupWordsBeforeInsertionPoint:(int)count {
    assert(NO);
    return @[];
}

#pragma mark - iTermPopupWindowPresenter

- (void)popupWindowWillPresent:(iTermPopupWindowController *)popupWindowController {
}

- (NSRect)popupWindowOriginRectInScreenCoords {
    NSRange range = [_largeComposerViewController.textView selectedRange];
    range.length = 0;
    return [_largeComposerViewController.textView firstRectForCharacterRange:range actualRange:NULL];
}

@end
