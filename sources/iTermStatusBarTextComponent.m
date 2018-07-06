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

    [self setValueInField:textField];
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

- (void)setValueInField:(NSTextField *)textField {
    if (self.attributedStringValue) {
        textField.attributedStringValue = self.attributedStringValue;
    } else if (self.stringValue) {
        textField.stringValue = self.stringValue;
        textField.alignment = NSLeftTextAlignment;
        textField.textColor = self.textColor;
    }
    [textField sizeToFit];
}

- (NSTextField *)textField {
    if (!_textField) {
        _textField = [self newTextField];
    }
    return _textField;
}

- (void)setStringValue:(NSString *)stringValue {
    _stringValue = stringValue;
    [self setValueInField:_textField];
    [self.delegate statusBarComponentPreferredSizeDidChange:self];
}

- (CGFloat)statusBarComponentPreferredWidth {
    if (!_measuringField) {
        _measuringField = [self newTextField];
    } else {
        [self setValueInField:_measuringField];
    }
    return [_measuringField frame].size.width;
}

- (void)statusBarComponentSizeView:(NSView *)view toFitWidth:(CGFloat)width {
    [[NSTextField castFrom:view] sizeToFit];
    view.frame = NSMakeRect(0, 0, width, view.frame.size.height);
}

#pragma mark - iTermStatusBarComponent

- (NSView *)statusBarComponentCreateView {
    return self.textField;
}

@end

NS_ASSUME_NONNULL_END
