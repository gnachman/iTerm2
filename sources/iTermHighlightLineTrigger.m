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
#import "PTYSession.h"
#import "ScreenChar.h"
#import "VT100Screen.h"

@implementation iTermHighlightLineTrigger

+ (NSString *)title {
    return @"Highlight Line…";
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

- (NSString *)stringValue {
    return [self stringForTextColor:self.textColor backgroundColor:self.backgroundColor];
}

- (NSString *)stringForTextColor:(NSColor *)textColor backgroundColor:(NSColor *)backgroundColor {
    return [NSString stringWithFormat:@"{%@,%@}",
            textColor.stringValue ?: @"",
            backgroundColor.stringValue ?: @""];
}

- (NSColor *)textColor {
    NSDictionary *colors = [self colors];
    return colors[kHighlightForegroundColor];
}

- (NSColor *)backgroundColor {
    NSDictionary *colors = [self colors];
    return colors[kHighlightBackgroundColor];
}

- (void)setTextColor:(NSColor *)textColor {
    [super setTextColor:textColor];
    NSMutableArray *temp = [[self stringsForColors] mutableCopy];
    temp[0] = textColor ? textColor.stringValue: @"";
    self.param = [NSString stringWithFormat:@"{%@,%@}", temp[0], temp[1]];
}

- (void)setBackgroundColor:(NSColor *)backgroundColor {
    [super setBackgroundColor:backgroundColor];
    NSMutableArray *temp = [[self stringsForColors] mutableCopy];
    temp[1] = backgroundColor ? backgroundColor.stringValue: @"";
    self.param = [NSString stringWithFormat:@"{%@,%@}", temp[0], temp[1]];
}

// Returns a string of the form {text components,background components} from self.param.
- (NSArray *)stringsForColors {
    if (![self.param isKindOfClass:[NSString class]]) {
        return @[ [[NSColor whiteColor] stringValue], [[NSColor redColor] stringValue] ];
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
- (NSDictionary *)colors {
    NSArray *parts = [self stringsForColors];
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    NSColor *textColor = nil;
    NSColor *backgroundColor = nil;
    if (parts.count == 2) {
        textColor = [NSColor colorWithString:parts[0]];
        backgroundColor = [NSColor colorWithString:parts[1]];
    }
    if (textColor) {
        dict[kHighlightForegroundColor] = textColor;
    }
    if (backgroundColor) {
        dict[kHighlightBackgroundColor] = backgroundColor;
    }
    return dict;
}

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    NSRange rangeInString = capturedRanges[0];
    NSRange rangeInScreenChars = [stringLine rangeOfScreenCharsForRangeInString:rangeInString];
    iTermTextExtractor *extractor = [[iTermTextExtractor alloc] initWithDataSource:aSession.screen];
    const VT100GridAbsCoord absCoord = VT100GridAbsCoordMake(rangeInScreenChars.location,
                                                             lineNumber);
    BOOL ok = NO;
    const VT100GridCoord coord = VT100GridCoordFromAbsCoord(absCoord, aSession.screen.totalScrollbackOverflow, &ok);
    if (!ok) {
        return YES;
    }
    const VT100GridWindowedRange wrappedRange =
    [extractor rangeForWrappedLineEncompassing:coord
                          respectContinuations:NO
                                      maxChars:aSession.screen.width * 10];

    const long long lineLength = VT100GridCoordRangeLength(wrappedRange.coordRange,
                                                           aSession.screen.width);
    const int width = aSession.screen.width;
    const long long lengthToHighlight = ceil((double)lineLength / (double)width);
    const NSRange range = NSMakeRange(0, lengthToHighlight * width);
    [[aSession screen] highlightTextInRange:range
                  basedAtAbsoluteLineNumber:lineNumber
                                     colors:[self colors]];
    return YES;
}

@end
