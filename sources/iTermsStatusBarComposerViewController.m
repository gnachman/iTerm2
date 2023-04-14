//
//  iTermsStatusBarComposerViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/12/18.
//

#import "iTermsStatusBarComposerViewController.h"

#import "iTermStatusBarLargeComposerViewController.h"
#import "DebugLogging.h"
#import "NSAppearance+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PSMTabBarControl.h"

static NSString *const iTermComposerComboBoxDidBecomeFirstResponder = @"iTermComposerComboBoxDidBecomeFirstResponder";

@interface iTermsStatusBarComposerViewController ()<NSComboBoxDelegate>
@end

@interface iTermComposerComboBox : NSComboBox
@end

@implementation iTermComposerComboBox

- (BOOL)becomeFirstResponder {
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermComposerComboBoxDidBecomeFirstResponder
                                                        object:self];
    return [super becomeFirstResponder];
}

@end

@implementation iTermsStatusBarComposerViewController {
    BOOL _open;
    BOOL _wantsReload;
    IBOutlet NSComboBox *_comboBox;
    IBOutlet NSButton *_button;
}

- (void)awakeFromNib {
    if (PSMShouldExtendTransparencyIntoMinimalTabBar()) {
        NSRect frame = _comboBox.frame;
        frame.origin.y += PSMShouldExtendTransparencyIntoMinimalTabBar() ? 0.5 : 0;
        _comboBox.frame = frame;
    }
}

- (void)setDelegate:(id)delegate {
    _delegate = delegate;
    [self reallyReloadData];
}

- (void)reloadData {
    if (_open) {
        _wantsReload = YES;
        return;
    }
    [self reallyReloadData];
}

- (void)makeFirstResponder {
    if ([_comboBox textFieldIsFirstResponder]) {
        [_delegate statusBarComposerRevealComposer:self];
        return;
    }
    [_comboBox.window makeFirstResponder:_comboBox];
}

- (void)deselect {
    [[_comboBox currentEditor] setSelectedRange:NSMakeRange(_comboBox.stringValue.length, 0)];
}

- (void)setTintColor:(NSColor *)tintColor {
    NSImage *image = [NSImage it_imageNamed:@"StatusBarComposerExpand" forClass:self.class];
    _button.image = [image it_imageWithTintColor:tintColor];
}

- (NSString *)stringValue {
    return _comboBox.stringValue;
}

- (void)setStringValue:(NSString *)stringValue {
    _comboBox.stringValue = stringValue;
}

- (void)insertText:(NSString *)text {
    [_comboBox insertText:text];
}

- (void)setHost:(id<VT100RemoteHostReading>)host {
}

- (NSRect)cursorFrameInScreenCoordinates {
    NSTextView *const textEditor = [_comboBox.currentEditor isKindOfClass:[NSTextView class]] ? (NSTextView *)_comboBox.currentEditor : nil;
    if (!textEditor) {
        DLog(@"No text editor for %@", _comboBox);
        return NSZeroRect;
    }
    return textEditor.cursorFrameInScreenCoordinates;
}

#pragma mark - Private

- (IBAction)send:(id)sender {
}

- (IBAction)revealComposer:(id)sender {
    [self.delegate statusBarComposerRevealComposer:self];
}

- (void)reallyReloadData {
    _wantsReload = NO;
    [_comboBox removeAllItems];
    [_comboBox addItemsWithObjectValues:[self.delegate statusBarComposerSuggestions:self] ?: @[]];
}

- (void)sendCommand {
    [self.delegate statusBarComposer:self sendCommand:_comboBox.stringValue];
    _comboBox.stringValue = @"";
}

#pragma mark - NSComboBoxDelegate

- (void)comboBoxWillPopUp:(NSNotification *)notification {
    _open = YES;
}

- (void)comboBoxWillDismiss:(NSNotification *)notification {
    _open = NO;
    if (_wantsReload) {
        [self reloadData];
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    [self.delegate statusBarComposerDidEndEditing:self];
}

- (void)cancelOperation:(id)sender {
    [self.delegate statusBarComposerDidEndEditing:self];
}

- (BOOL)control:(NSControl *)control
       textView:(NSTextView *)textView
doCommandBySelector:(SEL)commandSelector {
    if (control != _comboBox) {
        return NO;
    }

    if (commandSelector == @selector(insertNewline:)) {
        if (!_open) {
            [self sendCommand];
        }
        return YES;
    } else {
        return NO;
    }
}

@end

@interface iTermComposerComboBoxCell: NSComboBoxCell
@end

@implementation iTermComposerComboBoxCell

- (void)drawWithFrame:(NSRect)originalFrame inView:(NSView *)controlView {
    if (PSMShouldExtendTransparencyIntoMinimalTabBar()) {
        if (@available(macOS 10.16, *)) {
            [self drawModernWithFrame:originalFrame inView:controlView];
        } else {
            assert(NO);
        }
    } else {
        [self drawLegacyWithFrame:originalFrame inView:controlView];
    }
}

- (void)drawLegacyWithFrame:(NSRect)originalFrame inView:(NSView *)controlView {
    [super drawWithFrame:originalFrame inView:controlView];
}

- (void)drawModernWithFrame:(NSRect)originalFrame inView:(NSView *)controlView NS_AVAILABLE_MAC(10_16) {
    NSRect cellFrame = originalFrame;
    cellFrame.origin.y -= 1;
    [self.backgroundColor set];

    CGFloat xInset, yInset;
    xInset = 0.25;
    yInset = 2.75;
    cellFrame = NSInsetRect(cellFrame, xInset, yInset);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:cellFrame
                                                         xRadius:4
                                                         yRadius:4];

    [[NSColor colorWithCalibratedWhite:1 alpha:0.05] set];
    [path fill];

    if ([controlView.effectiveAppearance it_isDark]) {
        [[NSColor colorWithCalibratedWhite:0.5 alpha:.25] set];
    } else {
        [[NSColor colorWithCalibratedWhite:0.2 alpha:.5] set];
    }
    [path setLineWidth:0.5];
    [path stroke];

    cellFrame = NSInsetRect(cellFrame, 0.5, 0.5);
    path = [NSBezierPath bezierPathWithRoundedRect:cellFrame
                                           xRadius:4
                                           yRadius:4];
    [path setLineWidth:0.5];
    if ([controlView.effectiveAppearance it_isDark]) {
        [[NSColor colorWithCalibratedWhite:0.7 alpha:.25] set];
    } else {
        [[NSColor colorWithCalibratedWhite:0.8 alpha:.5] set];
    }
    [path stroke];

    {
        static NSImage *lightImage;
        static NSImage *darkImage;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            lightImage = [NSImage imageWithSystemSymbolName:@"chevron.down" accessibilityDescription:@"Show History"];
            darkImage = [lightImage it_imageWithTintColor:[NSColor whiteColor]];
        });
        NSImage *image = controlView.effectiveAppearance.it_isDark ? darkImage : lightImage;
        const CGFloat imageHeight = NSHeight(cellFrame) * 0.6;
        const NSSize size = [self sizeWithAspectRatio:image.size.width / image.size.height
                                         height:imageHeight];
        const CGFloat topOffset = (NSHeight(cellFrame) - imageHeight) / 2.0;
        const CGFloat rightMargin = 1;
        NSRect buttonRect = NSMakeRect(NSMaxX(cellFrame) - size.width - rightMargin,
                                       NSMinY(cellFrame) + topOffset,
                                       size.width,
                                       size.height);
        [image drawInRect:buttonRect
                 fromRect:NSZeroRect
                operation:NSCompositingOperationSourceOver
                 fraction:0.5
           respectFlipped:YES
                    hints:nil];
    }

    [self updateKeyboardClipViewIfNeeded];
    [self drawInteriorWithFrame:originalFrame inView:controlView];
}

- (NSSize)sizeWithAspectRatio:(CGFloat)widthOverHeight height:(CGFloat)height {
    return NSMakeSize(widthOverHeight * height, height);
}

// Work around a macOS bug that prevents updating the text rect while the search field has keyboard focus.
- (void)updateKeyboardClipViewIfNeeded {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSTextField *textField = [NSTextField castFrom:self.controlView];
        id cell = textField.cell;
        if ([cell isKindOfClass:[iTermsStatusBarComposerViewController class]]) {
            [cell reallyUpdateKeyboardClipView:textField];
        };
    });
}

- (void)reallyUpdateKeyboardClipView:(NSTextField *)textField {
    NSView *keyboardClipView = [self.controlView.subviews objectPassingTest:^BOOL(__kindof NSView *element, NSUInteger index, BOOL *stop) {
        return [NSStringFromClass([element class]) isEqualToString:@"_NSKeyboardFocusClipView"];
    }];
    if (!keyboardClipView) {
        return;
    }
    NSRect desiredFrame = [self drawingRectForBounds:textField.bounds];
    NSRect frame = keyboardClipView.frame;
    if (frame.size.width != desiredFrame.size.width) {
        frame.size.width = desiredFrame.size.width;
        keyboardClipView.frame = frame;

        NSTextView *textView = [NSTextView castFrom:[textField.window fieldEditor:YES forObject:textField]];
        [textView scrollRangeToVisible:[[[textView selectedRanges] firstObject] rangeValue]];
        DLog(@"Update keyboard clip view's frame to %@", NSStringFromRect(frame));
    }
}

@end
