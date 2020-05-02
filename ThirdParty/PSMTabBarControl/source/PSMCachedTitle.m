//
//  PSMCachedTitle.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/2/20.
//

#import "PSMCachedTitle.h"

@interface NSAttributedString(PSM)
- (NSAttributedString *)attributedStringWithTextAlignment:(NSTextAlignment)textAlignment;
@end

@implementation PSMCachedTitleInputs

- (instancetype)initWithTitle:(NSString *)title
              truncationStyle:(NSLineBreakMode)truncationStyle
                        color:(NSColor *)color
                      graphic:(NSImage *)graphic
                  orientation:(PSMTabBarOrientation)orientation
                     fontSize:(CGFloat)fontSize {
    self = [super init];
    if (self) {
        _title = title.length < 256 ? [title copy] : [[title substringToIndex:255] stringByAppendingString:@"…"];
        _truncationStyle = truncationStyle;
        _color = color;
        _graphic = graphic;
        _orientation = orientation;
        _fontSize = fontSize;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p title=%@ trunc=%@ color=%@ graphic=%@ orientation=%@ fontSize=%@>",
            NSStringFromClass([self class]), self, self.title, @(self.truncationStyle),
            self.color, self.graphic, @(self.orientation), @(self.fontSize)];
}

- (BOOL)isEqual:(id)obj {
    if (obj == nil) {
        return NO;
    }
    if (![obj isKindOfClass:[PSMCachedTitleInputs class]]) {
        return NO;
    }
    PSMCachedTitleInputs *other = obj;
    if (other->_title != _title && ![other->_title isEqual:_title]) {
        return NO;
    }
    if (other->_truncationStyle != _truncationStyle) {
        return NO;
    }
    if (other->_color != _color && ![other->_color isEqual:_color]) {
        return NO;
    }
    if (other->_graphic != _graphic && ![other->_graphic isEqual:_graphic]) {
        return NO;
    }
    if (other->_orientation != _orientation) {
        return NO;
    }
    if (other->_fontSize != _fontSize) {
        return NO;
    }
    return YES;
}

@end

@implementation PSMCachedTitle {
    NSAttributedString *_attributedString;
    NSAttributedString *_leftAlignedAttributedString;
    NSAttributedString *_truncatedAttributedString;
    NSAttributedString *_truncatedLeftAlignedAttributedString;
    CGFloat _truncationWidth;
    NSSize _cachedSize;
    BOOL _haveCachedSize;
}

- (instancetype)initWith:(PSMCachedTitleInputs *)inputs {
    self = [super init];
    if (self) {
        _inputs = inputs;
        _truncationWidth = NAN;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p inputs=%@>",
            NSStringFromClass([self class]), self, self.inputs];
}

- (NSAttributedString *)attributedString {
    if (_attributedString) {
        return _attributedString;
    }
    // Paragraph Style for Truncating Long Text
    NSMutableParagraphStyle *truncatingTailParagraphStyle =
        [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    [truncatingTailParagraphStyle setLineBreakMode:_inputs.truncationStyle];
    if (_inputs.orientation == PSMTabBarHorizontalOrientation) {
        [truncatingTailParagraphStyle setAlignment:NSTextAlignmentCenter];
    } else {
        [truncatingTailParagraphStyle setAlignment:NSTextAlignmentLeft];
    }

    NSFont *font = [NSFont systemFontOfSize:_inputs.fontSize];
    NSDictionary *attributes = @{ NSFontAttributeName: font,
                                  NSForegroundColorAttributeName: _inputs.color,
                                  NSParagraphStyleAttributeName: truncatingTailParagraphStyle };
    NSAttributedString *textAttributedString = [[NSAttributedString alloc] initWithString:_inputs.title
                                                                               attributes:attributes];
    if (!_inputs.graphic) {
        _attributedString = textAttributedString;
        return _attributedString;
    }
    _attributedString = [self attributedStringWithGraphicAndText:textAttributedString
                                                       capHeight:font.capHeight
                                                      attributes:attributes
                                    truncatingTailParagraphStyle:truncatingTailParagraphStyle];
    return _attributedString;
}

- (NSAttributedString *)attributedStringWithGraphicAndText:(NSAttributedString *)textAttributedString
                                                 capHeight:(CGFloat)capHeight
                                                attributes:(NSDictionary *)attributes
                              truncatingTailParagraphStyle:(NSParagraphStyle *)truncatingTailParagraphStyle {
    NSTextAttachment *textAttachment = [[NSTextAttachment alloc] init];
    textAttachment.image = _inputs.graphic;
    textAttachment.bounds = NSMakeRect(0,
                                       - (_inputs.graphic.size.height - capHeight) / 2.0,
                                       _inputs.graphic.size.width,
                                       _inputs.graphic.size.height);
    NSAttributedString *graphicAttributedString = [NSAttributedString attributedStringWithAttachment:textAttachment];

    NSAttributedString *space = [[NSAttributedString alloc] initWithString:@"\u2002"
                                                                attributes:attributes];
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result appendAttributedString:graphicAttributedString];
    [result appendAttributedString:space];
    [result appendAttributedString:textAttributedString];
    [result enumerateAttribute:NSAttachmentAttributeName
                       inRange:NSMakeRange(0, result.length)
                       options:0
                    usingBlock:^(id  _Nullable attachment, NSRange range, BOOL * _Nonnull stop) {
                        if ([attachment isKindOfClass:[NSTextAttachment class]]) {
                            [result addAttribute:NSParagraphStyleAttributeName
                                           value:truncatingTailParagraphStyle
                                           range:range];
                        }
                    }];
    return result;
}

- (NSRect)boundingRectWithSize:(NSSize)size {
    return [self.attributedString boundingRectWithSize:size options:0];
}

- (BOOL)isEmpty {
    return self.attributedString.length == 0;
}

- (NSSize)size {
    if (!_haveCachedSize) {
        _cachedSize = [self.attributedString size];
        _haveCachedSize = YES;
    }
    return _cachedSize;
}

#pragma mark - Private

- (NSAttributedString *)attributedStringForcingLeftAlignment:(BOOL)forceLeft
                                           truncatedForWidth:(CGFloat)truncatingWidth {
    BOOL needsComputed = NO;
    if (truncatingWidth != _truncationWidth) {
        needsComputed = YES;
    } else if (forceLeft && _truncatedLeftAlignedAttributedString == nil) {
        needsComputed = YES;
    } else if (!forceLeft && _truncatedAttributedString == nil) {
        needsComputed = YES;
    }
    if (needsComputed) {
        NSAttributedString *value = [self truncatedAttributedStringForWidth:truncatingWidth
                                                                leftAligned:forceLeft];
        if (forceLeft) {
            _truncatedLeftAlignedAttributedString = value;
        } else {
            _truncatedAttributedString = value;
        }
    }
    if (forceLeft) {
        return _truncatedLeftAlignedAttributedString;
    }
    return _truncatedAttributedString;
}

- (NSAttributedString *)leftAlignedAttributedString {
    if (!_leftAlignedAttributedString) {
        _leftAlignedAttributedString = [self.attributedString attributedStringWithTextAlignment:NSTextAlignmentLeft];
    }
    return _leftAlignedAttributedString;
}

// In the neverending saga of Cocoa embarassing itself, if there isn't enough space for a text
// attachment and the text that follows it, they are drawn overlapping.
- (NSAttributedString *)truncatedAttributedStringForWidth:(CGFloat)width
                                              leftAligned:(BOOL)forceLeft {
    NSAttributedString *attributedString = forceLeft ? self.leftAlignedAttributedString : self.attributedString;
    __block BOOL truncate = NO;
    [attributedString enumerateAttribute:NSAttachmentAttributeName
                                 inRange:NSMakeRange(0, 1)
                                 options:0
                              usingBlock:^(id  _Nullable value, NSRange range, BOOL * _Nonnull stop) {
                                  if (![value isKindOfClass:[NSTextAttachment class]]) {
                                      return;
                                  }
                                  NSTextAttachment *attachment = value;
                                  truncate = (attachment.image.size.width * 2 > width);
                              }];
    if (truncate) {
        return [attributedString attributedSubstringFromRange:NSMakeRange(0, 1)];
    }
    return attributedString;
}


@end

@implementation NSAttributedString(PSM)

- (NSAttributedString *)attributedStringWithTextAlignment:(NSTextAlignment)textAlignment {
    if (self.length == 0) {
        return self;
    }
    NSInteger representativeIndex = self.length;
    representativeIndex = MAX(0, representativeIndex - 1);
    NSDictionary *immutableAttributes = [self attributesAtIndex:representativeIndex effectiveRange:nil];
    if (!immutableAttributes) {
        return self;
    }

    NSMutableAttributedString *mutableCopy = [self mutableCopy];
    [self enumerateAttributesInRange:NSMakeRange(0, self.length)
                             options:0
                          usingBlock:^(NSDictionary<NSAttributedStringKey,id> * _Nonnull attrs, NSRange range, BOOL * _Nonnull stop) {
        NSMutableParagraphStyle *paragraphStyle = [attrs[NSParagraphStyleAttributeName] mutableCopy];
        if (!paragraphStyle) {
            paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
        }
        paragraphStyle.alignment = textAlignment;
        NSMutableDictionary *updatedAttrs = [attrs mutableCopy];
        updatedAttrs[NSParagraphStyleAttributeName] = paragraphStyle;
        [mutableCopy setAttributes:updatedAttrs range:range];
    }];
    return mutableCopy;
}

@end

