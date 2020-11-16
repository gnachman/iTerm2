//
//  PSMCachedTitle.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/2/20.
//

#import "PSMCachedTitle.h"
#import "NSAttributedString+PSM.h"

@implementation PSMCachedTitleInputs

- (instancetype)initWithTitle:(NSString *)title
              truncationStyle:(NSLineBreakMode)truncationStyle
                        color:(NSColor *)color
                      graphic:(NSImage *)graphic
                  orientation:(PSMTabBarOrientation)orientation
                     fontSize:(CGFloat)fontSize
                    parseHTML:(BOOL)parseHTML {
    self = [super init];
    if (self) {
        _title = title.length < 256 ? [title copy] : [[title substringToIndex:255] stringByAppendingString:@"…"];
        _truncationStyle = truncationStyle;
        _color = color;
        _graphic = graphic;
        _orientation = orientation;
        _fontSize = fontSize;
        _parseHTML = parseHTML;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p title=%@ trunc=%@ color=%@ graphic=%@ orientation=%@ fontSize=%@ parseHTML=%@>",
            NSStringFromClass([self class]), self, self.title, @(self.truncationStyle),
            self.color, self.graphic, @(self.orientation), @(self.fontSize), @(_parseHTML)];
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
    if (other->_parseHTML != _parseHTML) {
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
    NSAttributedString *textAttributedString = nil;
    if (_inputs.parseHTML) {
        textAttributedString = [NSAttributedString newAttributedStringWithHTML:_inputs.title
                                                                    attributes:attributes];
    } else {
        textAttributedString = [[NSAttributedString alloc] initWithString:_inputs.title
                                                               attributes:attributes];
    }
    _attributedString = textAttributedString;
    return _attributedString;
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


