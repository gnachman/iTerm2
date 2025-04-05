//
//  iTermHighlightLineTrigger.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/30/21.
//

#import "iTermHighlightLineTrigger.h"

#import "iTermTextExtractor.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "ScreenChar.h"

@implementation iTermHighlightLineTrigger

+ (NSString *)title {
    return @"Highlight Line…";
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Highlight Line with %@ over %@", self.textColor.humanReadableDescription ?: @"(no color)", self.backgroundColor.humanReadableDescription ?: @"(no color)"];
}

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
    return @"";
}

- (BOOL)takesParameter {
    return YES;
}

- (BOOL)paramIsPopupButton {
    return NO;
}

- (BOOL)paramIsTwoColorWells {
    return YES;
}

- (BOOL)instantTriggerCanFireMultipleTimesPerLine {
    return NO;
}

- (BOOL)isIdempotent {
    return YES;
}

- (NSString *)stringValue {
    return [self stringForTextColor:self.textColor backgroundColor:self.backgroundColor];
}

- (void)sanitize {
    NSDictionary *colors = [self colorsPreservingColorSpace:YES];
    self.textColor = colors[kHighlightForegroundColor];
    self.backgroundColor = colors[kHighlightBackgroundColor];
}

- (NSString *)stringForTextColor:(NSColor *)textColor backgroundColor:(NSColor *)backgroundColor {
    return [NSString stringWithFormat:@"{%@,%@}",
            textColor.hexStringPreservingColorSpace ?: @"",
            backgroundColor.hexStringPreservingColorSpace ?: @""];
}

- (NSColor *)textColor {
    NSDictionary *colors = [self colorsPreservingColorSpace:NO];
    return colors[kHighlightForegroundColor];
}

- (NSColor *)backgroundColor {
    NSDictionary *colors = [self colorsPreservingColorSpace:NO];
    return colors[kHighlightBackgroundColor];
}

- (void)setTextColor:(NSColor *)textColor {
    [super setTextColor:textColor];
    NSMutableArray *temp = [[self stringsForColors] mutableCopy];
    temp[0] = textColor ? textColor.hexStringPreservingColorSpace: @"";
    self.param = [NSString stringWithFormat:@"{%@,%@}", temp[0], temp[1]];
}

- (void)setBackgroundColor:(NSColor *)backgroundColor {
    [super setBackgroundColor:backgroundColor];
    NSMutableArray *temp = [[self stringsForColors] mutableCopy];
    temp[1] = backgroundColor ? backgroundColor.hexStringPreservingColorSpace: @"";
    self.param = [NSString stringWithFormat:@"{%@,%@}", temp[0], temp[1]];
}

// Returns a string of the form {text components,background components} from self.param.
- (NSArray *)stringsForColors {
    if (![self.param isKindOfClass:[NSString class]]) {
        return @[ [[NSColor whiteColor] hexString], [[NSColor redColor] hexString] ];
    }
    if ([self.param isKindOfClass:[NSString class]] &&
        [self.param hasPrefix:@"{"] && [self.param hasSuffix:@"}"]) {
        NSString *stringParam = self.param;
        NSString *inner = [self.param substringWithRange:NSMakeRange(1, stringParam.length - 2)];
        NSArray *parts = [inner componentsSeparatedByString:@","];
        if (parts.count == 2) {
            return parts;
        }
        return @[ @"", @"" ];
    }

    return @[ @"", @"" ];
}

// Returns a dictionary with text and background color from the self.param string.
- (NSDictionary<NSString *, NSColor *> *)colorsPreservingColorSpace:(BOOL)preserveColorSpace {
    NSArray *parts = [self stringsForColors];
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    NSColor *textColor = nil;
    NSColor *backgroundColor = nil;
    if (parts.count == 2) {
        if (preserveColorSpace) {
            textColor = [NSColor colorPreservingColorspaceFromString:parts[0]];
            backgroundColor = [NSColor colorPreservingColorspaceFromString:parts[1]];
        } else {
            textColor = [NSColor colorWithString:parts[0]];
            backgroundColor = [NSColor colorWithString:parts[1]];
        }
    }
    if (textColor) {
        dict[kHighlightForegroundColor] = textColor;
    }
    if (backgroundColor) {
        dict[kHighlightBackgroundColor] = backgroundColor;
    }
    return dict;
}

- (BOOL)performActionWithCapturedStrings:(NSArray<NSString *> *)stringArray
                          capturedRanges:(const NSRange *)capturedRanges
                               inSession:(id<iTermTriggerSession>)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    NSRange rangeInString = capturedRanges[0];
    NSRange rangeInScreenChars = [stringLine rangeOfScreenCharsForRangeInString:rangeInString];
    const VT100GridAbsCoord absCoord = VT100GridAbsCoordMake(rangeInScreenChars.location,
                                                             lineNumber);
    [aSession triggerSession:self
             highlightLineAt:absCoord
                      colors:[self colorsPreservingColorSpace:NO]];
    return YES;
}

- (NSAttributedString *)paramAttributedString {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];

    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"Text: "]];

    NSTextAttachment *textColorAttachment = [[NSTextAttachment alloc] init];
    textColorAttachment.image = [self imageForColor:self.textColor];
    NSAttributedString *textAttachmentString = [NSAttributedString attributedStringWithAttachment:textColorAttachment];
    NSMutableAttributedString *mutableTextAttachmentString = [textAttachmentString mutableCopy];
    // Lower the image by adjusting the baseline offset.
    [mutableTextAttachmentString addAttribute:NSBaselineOffsetAttributeName value:@(-2) range:NSMakeRange(0, mutableTextAttachmentString.length)];
    [result appendAttributedString:mutableTextAttachmentString];

    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@" Background: "]];

    NSTextAttachment *backgroundColorAttachment = [[NSTextAttachment alloc] init];
    backgroundColorAttachment.image = [self imageForColor:self.backgroundColor];
    NSAttributedString *backgroundAttachmentString = [NSAttributedString attributedStringWithAttachment:backgroundColorAttachment];
    NSMutableAttributedString *mutableBackgroundAttachmentString = [backgroundAttachmentString mutableCopy];
    // Lower the image by adjusting the baseline offset.
    [mutableBackgroundAttachmentString addAttribute:NSBaselineOffsetAttributeName value:@(-2) range:NSMakeRange(0, mutableBackgroundAttachmentString.length)];
    [result appendAttributedString:mutableBackgroundAttachmentString];

    return result;
}

- (NSImage *)imageForColor:(NSColor *)color {
    return [NSImage it_imageForColorSwatch:color size:NSMakeSize(22, 14)];
}

@end
