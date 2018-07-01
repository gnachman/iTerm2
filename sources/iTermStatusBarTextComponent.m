//
//  iTermStatusBarTextComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import "iTermStatusBarTextComponent.h"

#import "iTermStatusBarSetupKnobsViewController.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermStatusBarTextComponent {
    NSTextField *_textField;
}

- (NSTextField *)textField {
    if (!_textField) {
        _textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _textField.drawsBackground = NO;
        _textField.bordered = NO;
        _textField.editable = NO;
        _textField.selectable = NO;
        if (self.attributedStringValue) {
            _textField.attributedStringValue = self.attributedStringValue;
        } else if (self.stringValue) {
            _textField.stringValue = self.stringValue;
            _textField.alignment = NSLeftTextAlignment;
            _textField.textColor = [NSColor textColor];
        }
        [_textField sizeToFit];
    }
    return _textField;
}

#pragma mark - iTermStatusBarComponent

- (NSView *)statusBarComponentCreateView {
    return self.textField;
}

@end

NS_ASSUME_NONNULL_END
