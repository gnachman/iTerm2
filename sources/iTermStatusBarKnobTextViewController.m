//
//  iTermStatusBarKnobTextViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import "iTermStatusBarKnobTextViewController.h"

#import "NSObject+iTerm.h"

@interface iTermStatusBarKnobTextViewController ()

@end

@implementation iTermStatusBarKnobTextViewController {
    NSString *_value;
}

- (void)viewDidLoad {
    self.view.autoresizesSubviews = NO;
}

- (void)setValue:(NSString *)value {
    if (value == nil) {
        [self setValue:@""];
        return;
    }
    _textField.stringValue = value;
}

- (NSString *)value {
    return _value ?: _textField.stringValue;
}

- (void)setDescription:(NSString *)description placeholder:(nonnull NSString *)placeholder {
    _label.stringValue = description;
    _textField.placeholderString = placeholder;
    [self sizeToFit];
}

- (void)sizeToFit {
    const CGFloat marginBetweenLabelAndField = NSMinX(_textField.frame) - NSMaxX(_label.frame);

    [_label sizeToFit];
    NSRect rect = _label.frame;
    rect.origin.x = 0;
    _label.frame = rect;

    rect = _textField.frame;
    rect.origin.x = NSMaxX(_label.frame) + marginBetweenLabelAndField;
    _textField.frame = rect;

    rect = self.view.frame;
    rect.size.width = NSMaxX(_textField.frame);
    self.view.frame = rect;
}

- (CGFloat)controlOffset {
    return NSMinX(_textField.frame);
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)fieldEditor doCommandBySelector:(SEL)commandSelector {
    if ([self respondsToSelector:commandSelector]) {
        [self it_performNonObjectReturningSelector:commandSelector withObject:control];
        return YES;
    } else {
        return NO;
    }
}

- (void)insertNewline:(id)sender {
    // Mysteriously, calling parentViewController nukes the text field's value.
    _value = self.textField.stringValue;
    [self.view.window.sheetParent endSheet:self.view.window returnCode:NSModalResponseOK];
}

@end
