//
//  iTermsStatusBarComposerViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/12/18.
//

#import "iTermsStatusBarComposerViewController.h"

#import "iTermStatusBarLargeComposerViewController.h"

@interface iTermsStatusBarComposerViewController ()<NSComboBoxDelegate, NSPopoverDelegate>

@end

@implementation iTermsStatusBarComposerViewController {
    BOOL _open;
    BOOL _wantsReload;
    IBOutlet NSComboBox *_comboBox;
    IBOutlet iTermStatusBarLargeComposerViewController *_popoverVC;
    IBOutlet NSPopover *_popover;
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

#pragma mark - Private

- (IBAction)send:(id)sender {
}

- (IBAction)showPopover:(id)sender {
    _popover.behavior = NSPopoverBehaviorSemitransient;
    _popover.delegate = self;
    [_popover showRelativeToRect:_comboBox.frame
                          ofView:self.view
                   preferredEdge:NSRectEdgeMaxY];

}
- (void)reallyReloadData {
    _wantsReload = NO;
    [_comboBox removeAllItems];
    [_comboBox addItemsWithObjectValues:[self.delegate statusBarComposerSuggestions:self] ?: @[]];
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

#pragma mark - NSPopoverDelegate

- (void)popoverDidClose:(NSNotification *)notification {
    _comboBox.stringValue = _popoverVC.stringValue;

}

- (BOOL)control:(NSControl *)control
       textView:(NSTextView *)textView
doCommandBySelector:(SEL)commandSelector {
    if (control != _comboBox) {
        return NO;
    }

    if (commandSelector == @selector(insertNewline:)) {
        [self.delegate statusBarComposer:self sendCommand:_comboBox.stringValue];
        return YES;
    } else {
        return NO;
    }
}

@end
