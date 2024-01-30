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
#import "NSStringITerm.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermStatusBarTextComponent {
    NSTextField *_textField;
    NSTextField *_measuringField;
    NSString *_longestStringValue;
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *textColorKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Text Color:"
                                                          type:iTermStatusBarComponentKnobTypeColor
                                                   placeholder:nil
                                                  defaultValue:nil
                                                           key:iTermStatusBarSharedTextColorKey];
    iTermStatusBarComponentKnob *backgroundColorKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Background Color:"
                                                          type:iTermStatusBarComponentKnobTypeColor
                                                   placeholder:nil
                                                  defaultValue:nil
                                                           key:iTermStatusBarSharedBackgroundColorKey];
    iTermStatusBarComponentKnob *fontKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Custom Font"
                                                          type:iTermStatusBarComponentKnobTypeFont
                                                   placeholder:nil
                                                  defaultValue:nil
                                                           key:iTermStatusBarSharedFontKey];

    return [@[ textColorKnob, backgroundColorKnob, fontKnob, [super statusBarComponentKnobs], [self minMaxWidthKnobs]] flattenedArray];
}

- (NSFont *)font {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    NSString *name = knobValues[iTermStatusBarSharedFontKey];
    NSFont *font = nil;
    if (name.length > 0) {
        font = [name fontValue];
    }
    if (!font) {
        return self.advancedConfiguration.font ?: [iTermStatusBarAdvancedConfiguration defaultFont];
    }
    return font;
}

- (NSTextField *)newTextField {
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    textField.font = [self font];
    textField.drawsBackground = NO;
    textField.bordered = NO;
    textField.editable = NO;
    textField.selectable = NO;
    textField.lineBreakMode = NSLineBreakByTruncatingTail;

    textField.textColor = self.textColor;
    textField.font = self.font;
    textField.backgroundColor = self.backgroundColor;
    textField.drawsBackground = (self.backgroundColor.alphaComponent > 0);

    return textField;
}

- (BOOL)statusBarComponentIsEmpty {
    return [[self longestStringValue] length] == 0;
}

- (NSColor *)textColor {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobValues[iTermStatusBarSharedTextColorKey] colorValue] ?: ([self defaultTextColor] ?: [self.delegate statusBarComponentDefaultTextColor]);
}

- (NSColor *)backgroundColor {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobValues[iTermStatusBarSharedBackgroundColorKey] colorValue] ?: [super statusBarBackgroundColor];
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

    if (textField.alignment == NSTextAlignmentRight && textField.superview) {
        [self statusBarComponentSizeView:textField toFitWidth:textField.superview.bounds.size.width];
    } else {
        [textField sizeToFit];
    }
    return YES;
}

- (void)setDelegate:(id<iTermStatusBarComponentDelegate> _Nullable)delegate {
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
        DLog(@"%@: set longest string value to %@", self, longest);
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
    NSTextField *textField = [NSTextField castFrom:view];
    [textField sizeToFit];
    CGFloat x = 0;
    if (textField.alignment == NSTextAlignmentRight) {
        x = textField.superview.frame.size.width - width;
    }
    DLog(@"Place text view %@ of width %@ at x=%@ in container of width %@", textField, @(width), @(x), @(textField.superview.frame.size.width));
    view.frame = NSMakeRect(x, 0, width, view.frame.size.height);
    if (view == _textField) {
        [self setValueInField:_textField compressed:YES];
    }
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

- (NSColor * _Nullable)statusBarTextColor {
    return [self textColor];
}

- (NSColor *)statusBarBackgroundColor {
    return [self backgroundColor];
}

- (CGFloat)statusBarComponentVerticalOffset {
    const CGFloat containerHeight = _textField.superview.bounds.size.height;
    const CGFloat capHeight = _textField.font.capHeight;
    const CGFloat descender = _textField.font.descender - _textField.font.leading;  // negative (distance from bottom of bounding box to baseline)
    const CGFloat frameY = (containerHeight - _textField.frame.size.height) / 2;
    const CGFloat origin = containerHeight / 2.0 - frameY + descender - capHeight / 2.0;
    return origin;
}

#pragma mark - iTermStatusBarComponent

- (NSView *)statusBarComponentView {
    return self.textField;
}

- (void)statusBarComponentUpdate {
    [self updateTextFieldIfNeeded];
}

- (void)statusBarComponentWidthDidChangeTo:(CGFloat)newWidth {
    [self updateTextFieldIfNeeded];
}

- (void)statusBarDefaultTextColorDidChange {
    [self updateTextFieldIfNeeded];
}

@end

NS_ASSUME_NONNULL_END
