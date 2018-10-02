//
//  iTermStatusBarAttributedTextComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/22/18.
//

#import "iTermStatusBarAttributedTextComponent.h"

#import "DebugLogging.h"
#import "iTermStatusBarSetupKnobsViewController.h"
#import "iTermTuple.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSView+iTerm.h"
#import "PTYWindow.h"

NS_ASSUME_NONNULL_BEGIN

@protocol iTermTextFieldish<NSObject>
@property (nonatomic, copy) NSAttributedString *attributedStringValue;
@property (nonatomic, strong) NSColor *backgroundColor;
@property (nonatomic) BOOL drawsBackground;
- (void)sizeToFit;
@end

// This is a hack to draw attributed strings because NSTextField randomly shifts the baseline up
// one point when using an attributed string. When AppKit is dead and buried I'll revisit this.
@interface iTermAttributedStringView : NSView<iTermTextFieldish>
@property (nonatomic, copy) NSAttributedString *attributedStringValue;
@property (nonatomic, strong) NSColor *backgroundColor;
@property (nonatomic) BOOL drawsBackground;
@property (nonatomic, strong) NSColor *textColor;
@end

@implementation iTermAttributedStringView {
    CGFloat _baselineOffset;
}

- (void)drawString:(NSString *)string
        attributes:(NSDictionary *)attrs
             point:(CGPoint)point
        reallyDraw:(BOOL)reallyDraw
             width:(out CGFloat *)width {
    NSTextAttachment *attachment = attrs[NSAttachmentAttributeName];
    if (attachment) {
        NSImage *image = [attachment.image it_imageWithTintColor:self.textColor];
        if (reallyDraw) {
            [image drawAtPoint:NSMakePoint(point.x, point.y + _baselineOffset)
                      fromRect:NSZeroRect
                     operation:NSCompositingOperationSourceOver
                      fraction:1];
        }
        *width = [self retinaRound:image.size.width];
        return;
    }

    if (reallyDraw) {
        NSColor *textColor = attrs[NSForegroundColorAttributeName];
        if (!textColor) {
            attrs = [attrs dictionaryBySettingObject:self.textColor forKey:NSForegroundColorAttributeName];
        }
        [string drawAtPoint:point withAttributes:attrs];
    }
    *width = [self retinaRound:[string sizeWithAttributes:attrs].width];
}

- (void)sizeToFit {
    CGFloat width = 0;
    [self drawRect:NSZeroRect width:&width];
    CGSize size = CGSizeMake(width, 18);
    NSRect rect = self.frame;
    rect.size = size;
    self.frame = rect;
    [self setNeedsDisplay:YES];
}

- (void)setAttributedStringValue:(NSAttributedString *)attributedStringValue {
    _attributedStringValue = [attributedStringValue copy];
}

- (void)drawRect:(NSRect)dirtyRect {
    [self drawRect:dirtyRect width:nil];
}

- (void)drawRect:(NSRect)dirtyRect width:(out nullable CGFloat *)widthOut {
    const BOOL reallyDraw = (dirtyRect.size.width > 0 && dirtyRect.size.height > 0);
    if (self.drawsBackground && reallyDraw) {
        [self.backgroundColor set];
        NSRectFill(dirtyRect);
    }

    __block CGFloat x = 0;
    [self updateBaselineOffset];
    [_attributedStringValue enumerateAttributesInRange:NSMakeRange(0, _attributedStringValue.length)
                                               options:0
                                            usingBlock:^(NSDictionary<NSAttributedStringKey,id> * _Nonnull attrs, NSRange range, BOOL * _Nonnull stop) {
                                                CGFloat width = 0;
                                                [self drawString:[self->_attributedStringValue.string substringWithRange:range]
                                                      attributes:attrs
                                                           point:CGPointMake(x, 0)
                                                      reallyDraw:reallyDraw
                                                           width:&width];
                                                x += width;
                                       }];
    if (widthOut) {
        *widthOut = x;
    }
}

- (void)updateBaselineOffset {
    [_attributedStringValue enumerateAttributesInRange:NSMakeRange(0, _attributedStringValue.length)
                                               options:0
                                            usingBlock:^(NSDictionary<NSAttributedStringKey,id> * _Nonnull attrs, NSRange range, BOOL * _Nonnull stop) {
                                                NSFont *font = attrs[NSFontAttributeName];
                                                if (font) {
                                                    self->_baselineOffset = -font.descender;
                                                    *stop = YES;
                                                }
                                            }];
}

@end

@implementation iTermStatusBarAttributedTextComponent {
    iTermAttributedStringView *_attributedStringView;
    NSAttributedString *_attributedStringUsedForLayout;
    iTermAttributedStringView *_measuringField;
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *backgroundColorKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Background Color"
                                                          type:iTermStatusBarComponentKnobTypeColor
                                                   placeholder:nil
                                                  defaultValue:nil
                                                           key:iTermStatusBarSharedBackgroundColorKey];

    iTermStatusBarComponentKnob *textColorKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Text Color"
                                                          type:iTermStatusBarComponentKnobTypeColor
                                                   placeholder:nil
                                                  defaultValue:nil
                                                           key:iTermStatusBarSharedTextColorKey];
    return [@[ backgroundColorKnob, textColorKnob ] arrayByAddingObjectsFromArray:[super statusBarComponentKnobs]];
}

- (NSColor *)textColor {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    NSColor *configuredColor = [knobValues[iTermStatusBarSharedTextColorKey] colorValue];
    if (configuredColor) {
        return configuredColor;
    }

    NSColor *defaultTextColor = [self defaultTextColor];
    if (defaultTextColor) {
        return defaultTextColor;
    }

    NSColor *provided = [self.delegate statusBarComponentDefaultTextColor];
    if (provided) {
        return provided;
    } else {
        return [NSColor labelColor];
    }
}

- (NSTextField *)newTextField {
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    textField.drawsBackground = NO;
    textField.bordered = NO;
    textField.editable = NO;
    textField.selectable = NO;
    textField.lineBreakMode = NSLineBreakByTruncatingTail;

    textField.backgroundColor = self.backgroundColor;
    textField.drawsBackground = (self.backgroundColor.alphaComponent > 0);

    return textField;
}

- (NSColor *)backgroundColor {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobValues[iTermStatusBarSharedBackgroundColorKey] colorValue] ?: [self statusBarBackgroundColor];
}

- (BOOL)shouldUpdateValue:(NSAttributedString *)proposed inField:(id<iTermTextFieldish>)textField {
    const BOOL textFieldHasString = textField.attributedStringValue.length > 0;
    const BOOL iHaveString = proposed.length > 0;

    if (textFieldHasString != iHaveString) {
        DLog(@"%@ updating because nilness changed. textfield=%@ proposed=%@", self, textField.attributedStringValue, proposed);
        return YES;
    }
    if (textFieldHasString || iHaveString) {
        BOOL result = ![NSObject object:textField.attributedStringValue isEqualToObject:proposed];
        if (result) {
            DLog(@"%@ updating because %@ != %@", self, textField.attributedStringValue, proposed);
        }
        return result;
    }

    return NO;
}

- (BOOL)setValueInField:(id<iTermTextFieldish>)textField compressed:(BOOL)compressed {
    NSAttributedString *proposed;
    if (compressed) {
        proposed = [self attributedStringValueForCurrentWidth];
    } else {
        proposed = [self longestAttributedStringValue];
    }

    if (![self shouldUpdateValue:proposed inField:textField]) {
        return NO;
    }

    textField.attributedStringValue = proposed ?: [[NSAttributedString alloc] initWithString:@"" attributes:@{}];
    [textField sizeToFit];

    return YES;
}

- (void)updateTextFieldIfNeeded {
    [self setValueInField:_attributedStringView compressed:YES];
    NSAttributedString *longest = [self longestAttributedStringValue];
    if (![longest isEqualToAttributedString:_attributedStringUsedForLayout]) {
        _attributedStringUsedForLayout = [longest copy];
        [self.delegate statusBarComponentPreferredSizeDidChange:self];
    }
}

- (nullable NSAttributedString *)attributedStringValueForCurrentWidth {
    CGFloat currentWidth = _attributedStringView.frame.size.width;
    return [self attributedStringForWidth:currentWidth];
}

- (nullable NSAttributedString *)longestAttributedStringValue {
    return [self attributedStringForWidth:INFINITY];
}

- (NSArray<iTermTuple<NSAttributedString *,NSNumber *> *> *)widthAttributedStringTuples {
    return [self.attributedStringVariants mapWithBlock:^id(NSAttributedString *anObject) {
        CGFloat width = [self widthForAttributedString:anObject];
        return [iTermTuple tupleWithObject:anObject andObject:@(width)];
    }];
}

- (nullable NSAttributedString *)attributedStringForWidth:(CGFloat)width {
    NSArray<iTermTuple<NSAttributedString *,NSNumber *> *> *tuples = [self widthAttributedStringTuples];
    tuples = [tuples filteredArrayUsingBlock:^BOOL(iTermTuple<NSAttributedString *,NSNumber *> *anObject) {
        return ceil(anObject.secondObject.doubleValue) <= ceil(width);
    }];
    return [tuples maxWithBlock:^NSComparisonResult(iTermTuple<NSAttributedString *,NSNumber *> *obj1, iTermTuple<NSAttributedString *,NSNumber *> *obj2) {
        return [obj1.secondObject compare:obj2.secondObject];
    }].firstObject ?: [[NSAttributedString alloc] initWithString:@"" attributes:@{}];
}

- (CGFloat)statusBarComponentVerticalOffset {
    NSFont *font = self.advancedConfiguration.font ?: [iTermStatusBarAdvancedConfiguration defaultFont];
    const CGFloat containerHeight = _textField.superview.bounds.size.height;
    const CGFloat capHeight = font.capHeight;
    const CGFloat descender = font.descender - font.leading;  // negative (distance from bottom of bounding box to baseline)
    const CGFloat frameY = (containerHeight - _attributedStringView.frame.size.height) / 2;
    const CGFloat origin = containerHeight / 2.0 - frameY + descender - capHeight / 2.0;
    return origin;
}

- (CGFloat)statusBarComponentPreferredWidth {
    NSAttributedString *longest = [self longestAttributedStringValue];
    if (!longest) {
        return 0;
    }
    return [self widthForAttributedString:longest];
}

- (void)statusBarComponentSizeView:(NSView *)view toFitWidth:(CGFloat)width {
    id<iTermTextFieldish> textFieldish = (id<iTermTextFieldish>)view;
    [textFieldish sizeToFit];
    view.frame = NSMakeRect(0, 0, width, view.frame.size.height);
}

- (NSColor *)statusBarTextColor {
    return [self textColor];
}

- (void)save {
    NSAttributedString *attributedString = _measuringField.attributedStringValue;
    NSSize boxSize = [attributedString size];
    NSRect rect = NSMakeRect(0.0, 0.0, boxSize.width, boxSize.height);
    NSImage *image = [[NSImage alloc] initWithSize:boxSize];

    [image lockFocus];

    [[NSColor whiteColor] set];
    NSRectFill(rect);

    [attributedString drawInRect:rect];

    [image unlockFocus];

    [image saveAsPNGTo:@"/tmp/wtf2.png"];
}

- (CGFloat)widthForAttributedString:(NSAttributedString *)attributedString {
    if (!attributedString) {
        return 0;
    }
    if (!_measuringField) {
        _measuringField = [[iTermAttributedStringView alloc] init];
        _measuringField.textColor = self.textColor;
    }
    _measuringField.attributedStringValue = attributedString;
    [_measuringField sizeToFit];
    return [_measuringField frame].size.width;
}

- (CGFloat)statusBarComponentMinimumWidth {
    NSArray<iTermTuple<NSAttributedString *,NSNumber *> *> *tuples = [self widthAttributedStringTuples];
    NSNumber *number = [tuples minWithBlock:^NSComparisonResult(iTermTuple<NSAttributedString *,NSNumber *> *obj1, iTermTuple<NSAttributedString *,NSNumber *> *obj2) {
        return [obj1.secondObject compare:obj2.secondObject];
    }].secondObject;
    return number.doubleValue;
}

#pragma mark - iTermStatusBarComponent

- (NSView *)statusBarComponentCreateView {
    if (!_attributedStringView) {
        _attributedStringView = [[iTermAttributedStringView alloc] init];
        _attributedStringView.textColor = self.textColor;
        _attributedStringView.backgroundColor = self.backgroundColor;
        _attributedStringView.drawsBackground = (self.backgroundColor.alphaComponent > 0);
    }
    return _attributedStringView;
}

- (void)statusBarComponentUpdate {
    [self updateTextFieldIfNeeded];
}

- (void)statusBarComponentWidthDidChangeTo:(CGFloat)newWidth {
    [self updateTextFieldIfNeeded];
}

@end

NS_ASSUME_NONNULL_END
