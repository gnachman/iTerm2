//
//  iTermStatusBarTextComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import "iTermStatusBarTextComponent.h"

#import "DebugLogging.h"
#import "iTermStatusBarSetupKnobsViewController.h"
#import "iTermTuple.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const iTermStatusBarTextComponentTextColorKey = @"text: text color";

@implementation iTermStatusBarTextComponent {
    NSTextField *_textField;
    NSTextField *_measuringField;
    NSString *_longestStringValue;
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *textColorKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Text Color"
                                                          type:iTermStatusBarComponentKnobTypeColor
                                                   placeholder:nil
                                                  defaultValue:nil
                                                           key:iTermStatusBarTextComponentTextColorKey];
    iTermStatusBarComponentKnob *backgroundColorKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Background Color"
                                                          type:iTermStatusBarComponentKnobTypeColor
                                                   placeholder:nil
                                                  defaultValue:nil
                                                           key:iTermStatusBarSharedBackgroundColorKey];

    return [@[ textColorKnob, backgroundColorKnob ] arrayByAddingObjectsFromArray:[super statusBarComponentKnobs]];
}

- (NSTextField *)newTextField {
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    textField.font = [NSFont fontWithName:@"Menlo" size:12];
    textField.drawsBackground = NO;
    textField.bordered = NO;
    textField.editable = NO;
    textField.selectable = NO;
    textField.lineBreakMode = NSLineBreakByTruncatingTail;
    
    textField.textColor = self.textColor;
    textField.backgroundColor = self.backgroundColor;
    textField.drawsBackground = (self.backgroundColor.alphaComponent > 0);

    return textField;
}

- (NSColor *)textColor {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobValues[iTermStatusBarTextComponentTextColorKey] colorValue] ?: [self.delegate statusBarComponentDefaultTextColor];
}

- (NSColor *)backgroundColor {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobValues[iTermStatusBarSharedBackgroundColorKey] colorValue];
}

- (BOOL)shouldUpdateValue:(NSString *)proposed inField:(NSTextField *)textField {
    const BOOL textFieldHasString = textField.stringValue.length > 0;
    const BOOL iHaveString = proposed.length > 0;

    if (textFieldHasString != iHaveString) {
        DLog(@"%@ updating because nilness changed. textfield=%@ proposed=%@", self, textField.stringValue, proposed);
        return YES;
    }
    if (textFieldHasString || iHaveString) {
        BOOL result = !([NSObject object:textField.stringValue isEqualToObject:proposed] &&
                        [NSObject object:textField.textColor isEqualToObject:self.textColor]);
        if (result) {
            DLog(@"%@ updating because %@ != %@", self, textField.stringValue, proposed);
        }
        return result;
    }
    
    return NO;
}

- (BOOL)setValueInField:(NSTextField *)textField compressed:(BOOL)compressed {
    textField.textColor = self.textColor;

    NSString *proposed;
    if (compressed) {
        proposed = [self stringValueForCurrentWidth];
    } else {
        proposed = [self longestStringValue];
    }

    if (![self shouldUpdateValue:proposed inField:textField]) {
        return NO;
    }

    textField.stringValue = proposed ?: @"";

    [textField sizeToFit];
    return YES;
}

- (void)setDelegate:(id<iTermStatusBarComponentDelegate>)delegate {
    [super setDelegate:delegate];
    _textField.textColor = self.textColor;
}

- (NSTextField *)textField {
    if (!_textField) {
        _textField = [self newTextField];
        [self setValueInField:_textField compressed:YES];
    }
    return _textField;
}

- (void)updateTextFieldIfNeeded {
    [self setValueInField:_textField compressed:YES];

    NSString *longest = self.longestStringValue ?: @"";
    if (![longest isEqual:_longestStringValue]) {
        _longestStringValue = longest;
        [self.delegate statusBarComponentPreferredSizeDidChange:self];
    }
}

- (nullable NSString *)stringValueForCurrentWidth {
    CGFloat currentWidth = _textField.frame.size.width;
    return [self stringForWidth:currentWidth];
}

- (nullable NSString *)longestStringValue {
    return [self stringForWidth:INFINITY];
}

- (NSArray<iTermTuple<NSString *,NSNumber *> *> *)widthStringTuples {
    return [self.stringVariants mapWithBlock:^id(NSString *anObject) {
        CGFloat width = [self widthForString:anObject];
        return [iTermTuple tupleWithObject:anObject andObject:@(width)];
    }];
}

- (nullable NSString *)stringForWidth:(CGFloat)width {
    NSArray<iTermTuple<NSString *,NSNumber *> *> *tuples = [self widthStringTuples];
    tuples = [tuples filteredArrayUsingBlock:^BOOL(iTermTuple<NSString *,NSNumber *> *anObject) {
        return ceil(anObject.secondObject.doubleValue) <= ceil(width);
    }];
    return [tuples maxWithBlock:^NSComparisonResult(iTermTuple<NSString *,NSNumber *> *obj1, iTermTuple<NSString *,NSNumber *> *obj2) {
        return [obj1.secondObject compare:obj2.secondObject];
    }].firstObject ?: @"";
}

- (CGFloat)statusBarComponentPreferredWidth {
    NSString *longest = [self longestStringValue];
    if (!longest) {
        return 0;
    }
    return [self widthForString:longest];
}

- (void)statusBarComponentSizeView:(NSView *)view toFitWidth:(CGFloat)width {
    [[NSTextField castFrom:view] sizeToFit];
    view.frame = NSMakeRect(0, 0, width, view.frame.size.height);
}

- (CGFloat)widthForString:(NSString *)string {
    if (!string) {
        return 0;
    }
    if (!_measuringField) {
        _measuringField = [self newTextField];
    }
    _measuringField.stringValue = string;
    _measuringField.textColor = self.textColor;
    [_measuringField sizeToFit];
    return [_measuringField frame].size.width;
}

- (CGFloat)statusBarComponentMinimumWidth {
    NSArray<iTermTuple<NSString *,NSNumber *> *> *tuples = [self widthStringTuples];
    NSNumber *number = [tuples minWithBlock:^NSComparisonResult(iTermTuple<NSString *,NSNumber *> *obj1, iTermTuple<NSString *,NSNumber *> *obj2) {
        return [obj1.secondObject compare:obj2.secondObject];
    }].secondObject;
    return number.doubleValue;
}

#pragma mark - iTermStatusBarComponent

- (NSView *)statusBarComponentCreateView {
    return self.textField;
}

- (void)statusBarComponentUpdate {
    [self updateTextFieldIfNeeded];
}

- (void)statusBarComponentWidthDidChangeTo:(CGFloat)newWidth {
    [self updateTextFieldIfNeeded];
}

@end

NS_ASSUME_NONNULL_END
