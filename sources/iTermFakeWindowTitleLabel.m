//
//  iTermFakeWindowTitleLabel.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/11/19.
//

#import "iTermFakeWindowTitleLabel.h"

#import "DebugLogging.h"
#import "iTermPreferences.h"
#import "NSAttributedString+PSM.h"
#import "NSTextField+iTerm.h"

@implementation iTermFakeWindowTitleLabel {
    NSTextField *_scratch;
}

+ (NSParagraphStyle *)paragraphStyleWithAlignment:(NSTextAlignment)textAlignment {
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = textAlignment;
    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
    return paragraphStyle;
}

+ (NSDictionary *)attributesWithParagraphStyle:(NSParagraphStyle *)paragraphStyle
                                          font:(NSFont *)font
                                     textColor:(NSColor *)textColor {
    return @{ NSFontAttributeName: font,
              NSForegroundColorAttributeName: textColor,
              NSParagraphStyleAttributeName: paragraphStyle };
}

+ (NSAttributedString *)attributedStringForWindowTitleLabelWithString:(NSString *)title
                                                           attributes:(NSDictionary *)attributes {
    if ([iTermPreferences boolForKey:kPreferenceKeyHTMLTabTitles]) {
        return [NSAttributedString newAttributedStringWithHTML:title ?: @""
                                                    attributes:attributes];

    } else {
        return [[NSAttributedString alloc] initWithString:title ?: @""
                                               attributes:attributes];
    }
}

+ (NSTextAttachment *)iconTextAttachmentForWindowTitleLabelWithImage:(NSImage *)icon
                                                                font:(NSFont *)font {
    NSTextAttachment *textAttachment = [[NSTextAttachment alloc] init];
    textAttachment.image = icon;
    const CGFloat lineHeight = ceilf(font.capHeight);
    textAttachment.bounds = NSMakeRect(0,
                                       - (icon.size.height - lineHeight) / 2.0,
                                       icon.size.width,
                                       icon.size.height);
    return textAttachment;
}

+ (NSAttributedString *)attributedStringForWindowTitleLabelWithString:(NSString *)title
                                                             subtitle:(NSString *)subtitle
                                                                 icon:(NSImage *)icon
                                                                 font:(NSFont *)font
                                                            textColor:(NSColor *)textColor
                                                            alignment:(NSTextAlignment)textAlignment {
    NSParagraphStyle *paragraphStyle = [self paragraphStyleWithAlignment:textAlignment];
    NSDictionary *attributes = [self attributesWithParagraphStyle:paragraphStyle
                                                             font:font
                                                        textColor:textColor];
    NSString *amendedTitle = (subtitle.length == 0) ? title : [title stringByAppendingString:@"\n"];
    NSAttributedString *attributedString = [self attributedStringForWindowTitleLabelWithString:amendedTitle
                                                                                    attributes:attributes];
    NSMutableAttributedString *result;
    if (icon) {
        NSTextAttachment *textAttachment = [self iconTextAttachmentForWindowTitleLabelWithImage:icon
                                                                                           font:font];
        result = [[NSAttributedString attributedStringWithAttachment:textAttachment] mutableCopy];
    } else {
        result = [[NSMutableAttributedString alloc] init];
    }
    [result addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:NSMakeRange(0, result.length)];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:attributes]];
    [result appendAttributedString:attributedString];

    if (subtitle) {
        NSDictionary *subtitleAttributes =
            [self attributesWithParagraphStyle:paragraphStyle
                                          font:[NSFont fontWithName:font.fontName size:font.pointSize * 0.7]
                                     textColor:[textColor colorWithAlphaComponent:textColor.alphaComponent * 0.7]];
        NSAttributedString *subtitleAttributedString = [self attributedStringForWindowTitleLabelWithString:subtitle
                                                                                                attributes:subtitleAttributes];
        [result appendAttributedString:subtitleAttributedString];
    }
    return result;
}

+ (void)setTextField:(NSTextField *)label
            toString:(NSString *)title
            subtitle:(NSString *)subtitle
                icon:(NSImage *)icon
                font:(NSFont *)font
           textColor:(NSColor *)textColor
           alignment:(NSTextAlignment)textAlignment {
    if (icon) {
        label.attributedStringValue = [self attributedStringForWindowTitleLabelWithString:title
                                                                                 subtitle:subtitle
                                                                                     icon:icon
                                                                                     font:font
                                                                                textColor:textColor
                                                                                alignment:textAlignment];
    } else if (subtitle.length == 0) {
        label.stringValue = title ?: @"";
        label.lineBreakMode = NSLineBreakByTruncatingTail;
    } else {
        label.attributedStringValue = [self attributedStringForWindowTitleLabelWithString:title
                                                                                 subtitle:subtitle
                                                                                     icon:nil
                                                                                     font:font
                                                                                textColor:textColor
                                                                                alignment:textAlignment];
    }
    if (subtitle.length == 0) {
        label.maximumNumberOfLines = 1;
        label.usesSingleLineMode = YES;
    } else {
        label.maximumNumberOfLines = 2;
        label.usesSingleLineMode = NO;
    }
    label.alignment = textAlignment;
    label.allowsDefaultTighteningForTruncation = YES;
}

#pragma mark - NSObject

- (instancetype)init {
    self = [super init];
    if (self) {
        _scratch = [iTermFakeWindowTitleLabel newLabelStyledTextField];
        _scratch.alignment = NSTextAlignmentCenter;
    }
    return self;
}

#pragma mark - NSTextField

- (void)setAlignment:(NSTextAlignment)alignment {
    _scratch.alignment = alignment;
    [super setAlignment:alignment];
}

- (void)setFont:(NSFont *)font {
    _scratch.font = font;
    [super setFont:font];
}

#pragma mark - API

- (void)setTitle:(NSString *)title
        subtitle:(NSString *)subtitle
            icon:(NSImage *)icon
alignmentProvider:(NSTextAlignment (^NS_NOESCAPE)(NSTextField *scratch))alignmentProvider {
    [self setWorkingTitle:title subtitle:subtitle icon:icon];
    [self setTitleWithAlignment:alignmentProvider(_scratch)];
}

#pragma mark - Private

- (void)setWorkingTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(NSImage *)icon {
    _windowTitle = [title copy];
    _subtitle = [subtitle copy];
    _windowIcon = icon;
    [iTermFakeWindowTitleLabel setTextField:_scratch
                                   toString:title
                                   subtitle:subtitle
                                       icon:icon
                                       font:self.font
                                  textColor:self.textColor
                                  alignment:NSTextAlignmentLeft];
}

- (void)setTitleWithAlignment:(NSTextAlignment)textAlignment {
    DLog(@"Set title to %@ with alignment=%@", self.windowTitle, @(textAlignment));
    [iTermFakeWindowTitleLabel setTextField:self
                                   toString:self.windowTitle
                                   subtitle:self.subtitle
                                       icon:self.windowIcon
                                       font:self.font
                                  textColor:self.textColor
                                  alignment:textAlignment];
}

@end
