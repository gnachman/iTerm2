//
//  HighlightTrigger.m
//  iTerm2
//
//  Created by George Nachman on 9/23/11.
//

#import "HighlightTrigger.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "ScreenChar.h"

NSString * const kHighlightForegroundColor = @"kHighlightForegroundColor";
NSString * const kHighlightBackgroundColor = @"kHighlightBackgroundColor";


// Preserve these values - they are the tags and are saved in preferences.
enum {
    kYellowOnBlackHighlight,
    kBlackOnYellowHighlight,
    kWhiteOnRedHighlight,
    kRedOnWhiteHighlight,
    kBlackOnOrangeHighlight,
    kOrangeOnBlackHighlight,
    kBlackOnPurpleHighlight,
    kPurpleOnBlackHighlight,

    kBlackHighlight = 1000,
    kDarkGrayHighlight,
    kLightGrayHighlight,
    kWhiteHighlight,
    kGrayHighlight,
    kRedHighlight,
    kGreenHighlight,
    kBlueHighlight,
    kCyanHighlight,
    kYellowHighlight,
    kMagentaHighlight,
    kOrangeHighlight,
    kPurpleHighlight,
    kBrownHighlight,

    kBlackBackgroundHighlight = 2000,
    kDarkGrayBackgroundHighlight,
    kLightGrayBackgroundHighlight,
    kWhiteBackgroundHighlight,
    kGrayBackgroundHighlight,
    kRedBackgroundHighlight,
    kGreenBackgroundHighlight,
    kBlueBackgroundHighlight,
    kCyanBackgroundHighlight,
    kYellowBackgroundHighlight,
    kMagentaBackgroundHighlight,
    kOrangeBackgroundHighlight,
    kPurpleBackgroundHighlight,
    kBrownBackgroundHighlight,


};

// Localized display name for a highlight color popup option. The dictionary keys
// (the integer tags) are the persisted values and stay stable; only these display
// strings are localized.
static NSString *iTermHighlightTriggerLocalizedColorName(int tag) {
    switch (tag) {
        case kYellowOnBlackHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.YellowOnBlack", nil, [NSBundle mainBundle], @"Yellow on Black", @"Highlight trigger color option: yellow text on a black background");
        case kBlackOnYellowHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.BlackOnYellow", nil, [NSBundle mainBundle], @"Black on Yellow", @"Highlight trigger color option: black text on a yellow background");
        case kWhiteOnRedHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.WhiteOnRed", nil, [NSBundle mainBundle], @"White on Red", @"Highlight trigger color option: white text on a red background");
        case kRedOnWhiteHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.RedOnWhite", nil, [NSBundle mainBundle], @"Red on White", @"Highlight trigger color option: red text on a white background");
        case kBlackOnOrangeHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.BlackOnOrange", nil, [NSBundle mainBundle], @"Black on Orange", @"Highlight trigger color option: black text on an orange background");
        case kOrangeOnBlackHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.OrangeOnBlack", nil, [NSBundle mainBundle], @"Orange on Black", @"Highlight trigger color option: orange text on a black background");
        case kPurpleOnBlackHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.PurpleOnBlack", nil, [NSBundle mainBundle], @"Purple on Black", @"Highlight trigger color option: purple text on a black background");
        case kBlackOnPurpleHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.BlackOnPurple", nil, [NSBundle mainBundle], @"Black on Purple", @"Highlight trigger color option: black text on a purple background");

        case kBlackHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.BlackForeground", nil, [NSBundle mainBundle], @"Black Foreground", @"Highlight trigger color option: black text color");
        case kBlueHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.BlueForeground", nil, [NSBundle mainBundle], @"Blue Foreground", @"Highlight trigger color option: blue text color");
        case kBrownHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.BrownForeground", nil, [NSBundle mainBundle], @"Brown Foreground", @"Highlight trigger color option: brown text color");
        case kCyanHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.CyanForeground", nil, [NSBundle mainBundle], @"Cyan Foreground", @"Highlight trigger color option: cyan text color");
        case kDarkGrayHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.DarkGrayForeground", nil, [NSBundle mainBundle], @"Dark Gray Foreground", @"Highlight trigger color option: dark gray text color");
        case kGrayHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.GrayForeground", nil, [NSBundle mainBundle], @"Gray Foreground", @"Highlight trigger color option: gray text color");
        case kGreenHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.GreenForeground", nil, [NSBundle mainBundle], @"Green Foreground", @"Highlight trigger color option: green text color");
        case kLightGrayHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.LightGrayForeground", nil, [NSBundle mainBundle], @"Light Gray Foreground", @"Highlight trigger color option: light gray text color");
        case kMagentaHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.MagentaForeground", nil, [NSBundle mainBundle], @"Magenta Foreground", @"Highlight trigger color option: magenta text color");
        case kOrangeHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.OrangeForeground", nil, [NSBundle mainBundle], @"Orange Foreground", @"Highlight trigger color option: orange text color");
        case kPurpleHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.PurpleForeground", nil, [NSBundle mainBundle], @"Purple Foreground", @"Highlight trigger color option: purple text color");
        case kRedHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.RedForeground", nil, [NSBundle mainBundle], @"Red Foreground", @"Highlight trigger color option: red text color");
        case kWhiteHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.WhiteForeground", nil, [NSBundle mainBundle], @"White Foreground", @"Highlight trigger color option: white text color");
        case kYellowHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.YellowForeground", nil, [NSBundle mainBundle], @"Yellow Foreground", @"Highlight trigger color option: yellow text color");

        case kBlackBackgroundHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.BlackBackground", nil, [NSBundle mainBundle], @"Black Background", @"Highlight trigger color option: black background color");
        case kBlueBackgroundHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.BlueBackground", nil, [NSBundle mainBundle], @"Blue Background", @"Highlight trigger color option: blue background color");
        case kBrownBackgroundHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.BrownBackground", nil, [NSBundle mainBundle], @"Brown Background", @"Highlight trigger color option: brown background color");
        case kCyanBackgroundHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.CyanBackground", nil, [NSBundle mainBundle], @"Cyan Background", @"Highlight trigger color option: cyan background color");
        case kDarkGrayBackgroundHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.DarkGrayBackground", nil, [NSBundle mainBundle], @"Dark Gray Background", @"Highlight trigger color option: dark gray background color");
        case kGrayBackgroundHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.GrayBackground", nil, [NSBundle mainBundle], @"Gray Background", @"Highlight trigger color option: gray background color");
        case kGreenBackgroundHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.GreenBackground", nil, [NSBundle mainBundle], @"Green Background", @"Highlight trigger color option: green background color");
        case kLightGrayBackgroundHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.LightGrayBackground", nil, [NSBundle mainBundle], @"Light Gray Background", @"Highlight trigger color option: light gray background color");
        case kMagentaBackgroundHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.MagentaBackground", nil, [NSBundle mainBundle], @"Magenta Background", @"Highlight trigger color option: magenta background color");
        case kOrangeBackgroundHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.OrangeBackground", nil, [NSBundle mainBundle], @"Orange Background", @"Highlight trigger color option: orange background color");
        case kPurpleBackgroundHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.PurpleBackground", nil, [NSBundle mainBundle], @"Purple Background", @"Highlight trigger color option: purple background color");
        case kRedBackgroundHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.RedBackground", nil, [NSBundle mainBundle], @"Red Background", @"Highlight trigger color option: red background color");
        case kWhiteBackgroundHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.WhiteBackground", nil, [NSBundle mainBundle], @"White Background", @"Highlight trigger color option: white background color");
        case kYellowBackgroundHighlight:
            return NSLocalizedStringWithDefaultValue(@"Trigger.Highlight.Color.YellowBackground", nil, [NSBundle mainBundle], @"Yellow Background", @"Highlight trigger color option: yellow background color");
    }
    return @"";
}

// Tag constants for each menu section, in display order. Both the flat and the
// grouped menu builders derive their dictionaries from these arrays so a tag and
// its localized name can never drift apart.
static const int iTermHighlightForegroundBackgroundTags[] = {
    kYellowOnBlackHighlight,
    kBlackOnYellowHighlight,
    kWhiteOnRedHighlight,
    kRedOnWhiteHighlight,
    kBlackOnOrangeHighlight,
    kOrangeOnBlackHighlight,
    kPurpleOnBlackHighlight,
    kBlackOnPurpleHighlight,
};
static const int iTermHighlightForegroundTags[] = {
    kBlackHighlight,
    kBlueHighlight,
    kBrownHighlight,
    kCyanHighlight,
    kDarkGrayHighlight,
    kGrayHighlight,
    kGreenHighlight,
    kLightGrayHighlight,
    kMagentaHighlight,
    kOrangeHighlight,
    kPurpleHighlight,
    kRedHighlight,
    kWhiteHighlight,
    kYellowHighlight,
};
static const int iTermHighlightBackgroundTags[] = {
    kBlackBackgroundHighlight,
    kBlueBackgroundHighlight,
    kBrownBackgroundHighlight,
    kCyanBackgroundHighlight,
    kDarkGrayBackgroundHighlight,
    kGrayBackgroundHighlight,
    kGreenBackgroundHighlight,
    kLightGrayBackgroundHighlight,
    kMagentaBackgroundHighlight,
    kOrangeBackgroundHighlight,
    kPurpleBackgroundHighlight,
    kRedBackgroundHighlight,
    kWhiteBackgroundHighlight,
    kYellowBackgroundHighlight,
};

#define ITHighlightTagCount(a) (sizeof(a) / sizeof((a)[0]))

// Builds a {NSNumber(tag): localized name} dictionary for the given tag array.
static NSMutableDictionary *iTermHighlightTriggerColorMenuDict(const int *tags, size_t count) {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:count];
    for (size_t i = 0; i < count; i++) {
        dict[@(tags[i])] = iTermHighlightTriggerLocalizedColorName(tags[i]);
    }
    return dict;
}

@implementation HighlightTrigger {
    NSDictionary *_cachedColors;
}

+ (NSString *)title {
    return NSLocalizedStringWithDefaultValue(@"HighlightTrigger.Title", nil, [NSBundle mainBundle], @"Highlight Text…", @"Title of the highlight text trigger");
}

- (NSString *)description {
    NSString *noColor = NSLocalizedStringWithDefaultValue(@"HighlightTrigger.NoColor", nil, [NSBundle mainBundle], @"(no color)", @"Shown in a highlight trigger description when no color is set");
    return [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"HighlightTrigger.DescriptionFormat", nil, [NSBundle mainBundle], @"Highlight text %1$@ over %2$@", @"Description of a highlight trigger; first %@ is the text color, second %@ is the background color"), self.textColor.humanReadableDescription ?: noColor, self.backgroundColor.humanReadableDescription ?: noColor];
}

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
    return @"";
}

- (BOOL)takesParameter
{
    return YES;
}

- (BOOL)paramIsPopupButton {
    return NO;
}

- (BOOL)paramIsTwoColorWells {
    return YES;
}

- (BOOL)isIdempotent {
    return YES;
}

- (void)sanitize {
    NSDictionary *colors = [self colorsPreservingColorSpace:YES];
    self.textColor = colors[kHighlightForegroundColor];
    self.backgroundColor = colors[kHighlightBackgroundColor];
}

- (NSColor *)textColorInParam:(id)param {
    NSDictionary *colors = [HighlightTrigger colorsPreservingColorSpace:NO param:param];
    return colors[kHighlightForegroundColor];
}

- (NSColor *)backgroundColorInParam:(id)param {
    NSDictionary *colors = [HighlightTrigger colorsPreservingColorSpace:NO param:param];
    return colors[kHighlightBackgroundColor];
}

- (NSDictionary *)menuItemsForPoupupButton {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [result addEntriesFromDictionary:iTermHighlightTriggerColorMenuDict(iTermHighlightForegroundBackgroundTags, ITHighlightTagCount(iTermHighlightForegroundBackgroundTags))];
    [result addEntriesFromDictionary:iTermHighlightTriggerColorMenuDict(iTermHighlightForegroundTags, ITHighlightTagCount(iTermHighlightForegroundTags))];
    [result addEntriesFromDictionary:iTermHighlightTriggerColorMenuDict(iTermHighlightBackgroundTags, ITHighlightTagCount(iTermHighlightBackgroundTags))];
    return result;
}

- (NSArray *)groupedMenuItemsForPopupButton {
    NSDictionary *fgbg = iTermHighlightTriggerColorMenuDict(iTermHighlightForegroundBackgroundTags, ITHighlightTagCount(iTermHighlightForegroundBackgroundTags));
    NSDictionary *fg = iTermHighlightTriggerColorMenuDict(iTermHighlightForegroundTags, ITHighlightTagCount(iTermHighlightForegroundTags));
    NSMutableDictionary *bg = iTermHighlightTriggerColorMenuDict(iTermHighlightBackgroundTags, ITHighlightTagCount(iTermHighlightBackgroundTags));

    // Note: the dark gray background slot historically displays the same label as
    // the plain gray background ("Gray Background"). Preserve that by localizing
    // with the gray-background name so the visible order and text are unchanged.
    bg[@(kDarkGrayBackgroundHighlight)] = iTermHighlightTriggerLocalizedColorName(kGrayBackgroundHighlight);
    return @[fgbg, fg, bg];
}

- (BOOL)instantTriggerCanFireMultipleTimesPerLine {
    return YES;
}

- (NSInteger)indexForObject:(id)object {
    int i = 0;
    BOOL isFirst = YES;
    for (NSDictionary *dict in [self groupedMenuItemsForPopupButton]) {
        if (!isFirst) {
            ++i;
        }
        isFirst = NO;
        for (NSNumber *n in [self objectsSortedByValueInDict:dict]) {
            if ([n isEqual:object]) {
                return i;
            }
            i++;
        }
    }
    return -1;
}

- (id)objectAtIndex:(NSInteger)theIndex {
    int i = 0;
    BOOL isFirst = YES;
    for (NSDictionary *dict in [self groupedMenuItemsForPopupButton]) {
        if (!isFirst) {
            ++i;
        }
        isFirst = NO;
        for (NSNumber *n in [self objectsSortedByValueInDict:dict]) {
            if (i == theIndex) {
                return n;
            }
            i++;
        }
    }
    return nil;
}

- (NSDictionary *)dictionaryWithForegroundColor:(NSColor *)foreground
                                backgroundColor:(NSColor *)background {
    return [HighlightTrigger dictionaryWithForegroundColor:foreground
                                           backgroundColor:background];
}

+ (NSDictionary *)dictionaryWithForegroundColor:(NSColor *)foreground
                                backgroundColor:(NSColor *)background {
    return [NSDictionary dictionaryWithObjectsAndKeys:foreground, kHighlightForegroundColor, background, kHighlightBackgroundColor, nil];
}

- (NSDictionary *)dictionaryWithForegroundColor:(NSColor *)foreground {
    return [HighlightTrigger dictionaryWithForegroundColor:foreground];
}

+ (NSDictionary *)dictionaryWithForegroundColor:(NSColor *)foreground {
    return [NSDictionary dictionaryWithObjectsAndKeys:foreground, kHighlightForegroundColor, nil];
}

- (NSDictionary *)dictionaryWithBackgroundColor:(NSColor *)background {
    return [HighlightTrigger dictionaryWithBackgroundColor:background];
}

+ (NSDictionary *)dictionaryWithBackgroundColor:(NSColor *)background {
    return [NSDictionary dictionaryWithObjectsAndKeys:background, kHighlightBackgroundColor, nil];
}

- (NSString *)stringValue {
    return [self stringForTextColor:self.textColor backgroundColor:self.backgroundColor];
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

- (void)setParam:(id)param {
    _cachedColors = nil;
    [super setParam:param];
}

// Returns a string of the form {text components,background components} from self.param.
- (NSArray<NSString *> *)stringsForColors {
    return [HighlightTrigger stringsForColorsInParam:self.param];
}

+ (NSArray<NSString *> *)stringsForColorsInParam:(id)param {
    if (param == nil) {
        return @[ [[NSColor whiteColor] hexString], [[NSColor redColor] hexString] ];
    }
    if ([param isKindOfClass:[NSString class]] &&
        [param hasPrefix:@"{"] && [param hasSuffix:@"}"]) {
        NSString *stringParam = param;
        NSString *inner = [param substringWithRange:NSMakeRange(1, stringParam.length - 2)];
        NSArray *parts = [inner componentsSeparatedByString:@","];
        if (parts.count == 2) {
            return parts;
        }
        return @[ @"", @"" ];
    }

    if ([param isKindOfClass:[NSNumber class]]) {
        NSNumber *numberParam = param;
        NSDictionary *dict = [self colorDictionaryForInteger:numberParam.intValue];
        NSColor *text = dict[kHighlightForegroundColor];
        NSColor *background = dict[kHighlightBackgroundColor];
        return @[ text ? text.hexString : @"",
                  background ? background.hexString : @"" ];
    }

    return @[ @"", @"" ];
}

// Returns a dictionary with text and background color from the self.param string.
- (NSDictionary<NSString *, NSColor *> *)colorsPreservingColorSpace:(BOOL)preserveColorSpace {
    if (_cachedColors) {
        return _cachedColors;
    }
    NSDictionary *dict = [HighlightTrigger colorsPreservingColorSpace:preserveColorSpace param:self.param];
    _cachedColors = [dict copy];
    return dict;
}

+ (NSDictionary<NSString *, NSColor *> *)colorsPreservingColorSpace:(BOOL)preserveColorSpace
                                                              param:(id)param {
    NSArray *parts = [HighlightTrigger stringsForColorsInParam:param];
    NSMutableDictionary<NSString *, NSColor *> *dict = [NSMutableDictionary dictionary];
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

- (NSDictionary *)colorDictionaryForInteger:(int)param {
    return [HighlightTrigger colorDictionaryForInteger:param];
}

+ (NSDictionary *)colorDictionaryForInteger:(int)param {
    switch (param) {
        case kYellowOnBlackHighlight:
            return [self dictionaryWithForegroundColor:[NSColor yellowColor] backgroundColor:[NSColor blackColor]];

        case kBlackOnYellowHighlight:
            return [self dictionaryWithForegroundColor:[NSColor blackColor] backgroundColor:[NSColor yellowColor]];

        case kWhiteOnRedHighlight:
            return [self dictionaryWithForegroundColor:[NSColor whiteColor] backgroundColor:[NSColor redColor]];

        case kRedOnWhiteHighlight:
            return [self dictionaryWithForegroundColor:[NSColor redColor] backgroundColor:[NSColor whiteColor]];

        case kBlackOnOrangeHighlight:
            return [self dictionaryWithForegroundColor:[NSColor blackColor] backgroundColor:[NSColor orangeColor]];

        case kOrangeOnBlackHighlight:
            return [self dictionaryWithForegroundColor:[NSColor orangeColor] backgroundColor:[NSColor blackColor]];

        case kBlackOnPurpleHighlight:
            return [self dictionaryWithForegroundColor:[NSColor blackColor] backgroundColor:[NSColor purpleColor]];

        case kPurpleOnBlackHighlight:
            return [self dictionaryWithForegroundColor:[NSColor purpleColor] backgroundColor:[NSColor blackColor]];

        case kBlackHighlight:
            return [self dictionaryWithForegroundColor:[NSColor blackColor]];

        case kDarkGrayHighlight:
            return [self dictionaryWithForegroundColor:[NSColor darkGrayColor]];

        case kLightGrayHighlight:
            return [self dictionaryWithForegroundColor:[NSColor lightGrayColor]];

        case kWhiteHighlight:
            return [self dictionaryWithForegroundColor:[NSColor whiteColor]];

        case kGrayHighlight:
            return [self dictionaryWithForegroundColor:[NSColor grayColor]];

        case kRedHighlight:
            return [self dictionaryWithForegroundColor:[NSColor redColor]];

        case kGreenHighlight:
            return [self dictionaryWithForegroundColor:[NSColor greenColor]];

        case kBlueHighlight:
            return [self dictionaryWithForegroundColor:[NSColor blueColor]];

        case kCyanHighlight:
            return [self dictionaryWithForegroundColor:[NSColor cyanColor]];

        case kYellowHighlight:
            return [self dictionaryWithForegroundColor:[NSColor yellowColor]];

        case kMagentaHighlight:
            return [self dictionaryWithForegroundColor:[NSColor magentaColor]];

        case kOrangeHighlight:
            return [self dictionaryWithForegroundColor:[NSColor orangeColor]];

        case kPurpleHighlight:
            return [self dictionaryWithForegroundColor:[NSColor purpleColor]];

        case kBrownHighlight:
            return [self dictionaryWithForegroundColor:[NSColor brownColor]];

        case kBlackBackgroundHighlight:
            return [self dictionaryWithBackgroundColor:[NSColor blackColor]];

        case kDarkGrayBackgroundHighlight:
            return [self dictionaryWithBackgroundColor:[NSColor darkGrayColor]];

        case kLightGrayBackgroundHighlight:
            return [self dictionaryWithBackgroundColor:[NSColor lightGrayColor]];

        case kWhiteBackgroundHighlight:
            return [self dictionaryWithBackgroundColor:[NSColor whiteColor]];

        case kGrayBackgroundHighlight:
            return [self dictionaryWithBackgroundColor:[NSColor grayColor]];

        case kRedBackgroundHighlight:
            return [self dictionaryWithBackgroundColor:[NSColor redColor]];

        case kGreenBackgroundHighlight:
            return [self dictionaryWithBackgroundColor:[NSColor greenColor]];

        case kBlueBackgroundHighlight:
            return [self dictionaryWithBackgroundColor:[NSColor blueColor]];

        case kCyanBackgroundHighlight:
            return [self dictionaryWithBackgroundColor:[NSColor cyanColor]];

        case kYellowBackgroundHighlight:
            return [self dictionaryWithBackgroundColor:[NSColor yellowColor]];

        case kMagentaBackgroundHighlight:
            return [self dictionaryWithBackgroundColor:[NSColor magentaColor]];

        case kOrangeBackgroundHighlight:
            return [self dictionaryWithBackgroundColor:[NSColor orangeColor]];

        case kPurpleBackgroundHighlight:
            return [self dictionaryWithBackgroundColor:[NSColor purpleColor]];

        case kBrownBackgroundHighlight:
            return [self dictionaryWithBackgroundColor:[NSColor brownColor]];
    }
    return nil;
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

    [aSession triggerSession:self
        highlightTextInRange:rangeInScreenChars
                absoluteLine:lineNumber
                      colors:[self colorsPreservingColorSpace:NO]];
    return YES;
}

- (NSAttributedString *)paramAttributedString {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];

    [result appendAttributedString:[[NSAttributedString alloc] initWithString:NSLocalizedStringWithDefaultValue(@"HighlightTrigger.TextLabel", nil, [NSBundle mainBundle], @"Text: ", @"Label preceding the text color swatch")]];

    NSTextAttachment *textColorAttachment = [[NSTextAttachment alloc] init];
    textColorAttachment.image = [self imageForColor:self.textColor];
    NSAttributedString *textAttachmentString = [NSAttributedString attributedStringWithAttachment:textColorAttachment];
    NSMutableAttributedString *mutableTextAttachmentString = [textAttachmentString mutableCopy];
    // Lower the image by adjusting the baseline offset.
    [mutableTextAttachmentString addAttribute:NSBaselineOffsetAttributeName value:@(-2) range:NSMakeRange(0, mutableTextAttachmentString.length)];
    [result appendAttributedString:mutableTextAttachmentString];

    [result appendAttributedString:[[NSAttributedString alloc] initWithString:NSLocalizedStringWithDefaultValue(@"HighlightTrigger.BackgroundLabel", nil, [NSBundle mainBundle], @" Background: ", @"Label preceding the background color swatch")]];

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
