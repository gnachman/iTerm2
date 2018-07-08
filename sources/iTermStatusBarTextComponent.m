//
//  iTermStatusBarTextComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import "iTermStatusBarTextComponent.h"

#import "iTermStatusBarSetupKnobsViewController.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const iTermStatusBarTextComponentTextColorKey = @"text: text color";

@implementation iTermStatusBarTextComponent {
    NSTextField *_textField;
    NSTextField *_measuringField;
}

+ (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *textColorKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Text Color"
                                                          type:iTermStatusBarComponentKnobTypeColor
                                                   placeholder:nil
                                                  defaultValue:[[NSColor blackColor] dictionaryValue]
                                                           key:iTermStatusBarTextComponentTextColorKey];
    iTermStatusBarComponentKnob *backgroundColorKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Background Color"
                                                          type:iTermStatusBarComponentKnobTypeColor
                                                   placeholder:nil
                                                  defaultValue:[[NSColor clearColor] dictionaryValue]
                                                           key:iTermStatusBarSharedBackgroundColorKey];

    return @[ textColorKnob, backgroundColorKnob ];
}

- (NSTextField *)newTextField {
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    textField.drawsBackground = NO;
    textField.bordered = NO;
    textField.editable = NO;
    textField.selectable = NO;
    textField.lineBreakMode = NSLineBreakByTruncatingTail;
    
    textField.textColor = self.textColor;
    textField.backgroundColor = self.backgroundColor;
    textField.drawsBackground = (self.backgroundColor.alphaComponent > 0);

    [self setValueInField:textField compressed:YES];
    return textField;
}

- (NSColor *)textColor {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobValues[iTermStatusBarTextComponentTextColorKey] colorValue];
}

- (NSColor *)backgroundColor {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobValues[iTermStatusBarSharedBackgroundColorKey] colorValue];
}

- (BOOL)shouldUpdateValue:(NSString *)proposed inField:(NSTextField *)textField {
    const BOOL textFieldHasString = textField.stringValue.length > 0;
    const BOOL iHaveString = proposed != nil;

    if (textFieldHasString != iHaveString) {
        return YES;
    }
    if (textFieldHasString || iHaveString) {
        return !([NSObject object:textField.stringValue isEqualToObject:proposed] &&
                 [NSObject object:textField.textColor isEqualToObject:self.textColor]);
    }
    
    return NO;
}

- (BOOL)setValueInField:(NSTextField *)textField compressed:(BOOL)compressed {
    NSString *string = compressed ? [self stringValueForCurrentWidth] : self.stringValue;

    if (![self shouldUpdateValue:string inField:textField]) {
        return NO;
    }

    textField.stringValue = string ?: @"";
    textField.alignment = NSLeftTextAlignment;
    textField.textColor = self.textColor;

    [textField sizeToFit];
    return YES;
}

- (NSTextField *)textField {
    if (!_textField) {
        _textField = [self newTextField];
    }
    return _textField;
}

- (void)setStringValue:(NSString *)stringValue {
    _stringValue = stringValue;
    [self updateTextFieldIfNeeded];
}

- (void)updateTextFieldIfNeeded {
    if (![self setValueInField:_textField compressed:YES]) {
        return;
    }
    [self.delegate statusBarComponentPreferredSizeDidChange:self];
}

- (nullable NSString *)stringValueForCurrentWidth {
    return _stringValue;
}

- (nullable NSString *)maximallyCompressedStringValue {
    return _stringValue;
}

- (CGFloat)statusBarComponentPreferredWidth {
    if (!_measuringField) {
        _measuringField = [self newTextField];
    } else {
        [self setValueInField:_measuringField compressed:NO];
    }
    return [_measuringField frame].size.width;
}

- (void)statusBarComponentSizeView:(NSView *)view toFitWidth:(CGFloat)width {
    [[NSTextField castFrom:view] sizeToFit];
    view.frame = NSMakeRect(0, 0, width, view.frame.size.height);
}

- (CGFloat)widthForString:(NSString *)string {
    if (!_measuringField) {
        _measuringField = [self newTextField];
    }
    _measuringField.stringValue = string;
    _measuringField.alignment = NSLeftTextAlignment;
    _measuringField.textColor = self.textColor;
    [_measuringField sizeToFit];
    return [_measuringField frame].size.width;
}

- (CGFloat)statusBarComponentMinimumWidth {
    NSString *compressed = self.maximallyCompressedStringValue;
    if (compressed) {
        return [self widthForString:compressed];
    } else {
        return [super statusBarComponentMinimumWidth];
    }
}

#pragma mark - iTermStatusBarComponent

- (NSView *)statusBarComponentCreateView {
    return self.textField;
}

@end

NS_ASSUME_NONNULL_END
