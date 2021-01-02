//
//  iTermsStatusBarComposerViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/12/18.
//

#import "iTermsStatusBarComposerViewController.h"

#import "iTermStatusBarLargeComposerViewController.h"
#import "NSImage+iTerm.h"
#import "NSTextField+iTerm.h"

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

- (void)setHost:(VT100RemoteHost *)host {
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
