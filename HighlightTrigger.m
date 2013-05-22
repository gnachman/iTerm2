//
//  HighlightTrigger.m
//  iTerm2
//
//  Created by George Nachman on 9/23/11.
//

#import "HighlightTrigger.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PseudoTerminal.h"
#import "VT100Screen.h"

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
    kLighGrayHighlight,
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
    kLighGrayBackgroundHighlight,
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

@implementation HighlightTrigger

- (NSString *)title
{
    return @"Highlight Text…";
}

- (NSString *)paramPlaceholder
{
    return @"";
}

- (BOOL)takesParameter
{
    return YES;
}

- (BOOL)paramIsPopupButton
{
    return YES;
}

- (NSDictionary *)menuItemsForPoupupButton
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            @"Yellow on Black", [NSNumber numberWithInt:(int)kYellowOnBlackHighlight],
            @"Black on Yellow", [NSNumber numberWithInt:(int)kBlackOnYellowHighlight],
            @"White on Red",    [NSNumber numberWithInt:(int)kWhiteOnRedHighlight],
            @"Red on White",    [NSNumber numberWithInt:(int)kRedOnWhiteHighlight],
            @"Black on Orange", [NSNumber numberWithInt:(int)kBlackOnOrangeHighlight],
            @"Orange on Black", [NSNumber numberWithInt:(int)kOrangeOnBlackHighlight],
            @"Purple on Black", [NSNumber numberWithInt:(int)kPurpleOnBlackHighlight],
            @"Black on Purple", [NSNumber numberWithInt:(int)kBlackOnPurpleHighlight],

            @"Black Foreground",  [NSNumber numberWithInt:(int)kBlackHighlight],
            @"Blue Foreground",  [NSNumber numberWithInt:(int)kBlueHighlight],
            @"Brown Foreground",  [NSNumber numberWithInt:(int)kBrownHighlight],
            @"Cyan Foreground",  [NSNumber numberWithInt:(int)kCyanHighlight],
            @"Dark Gray Foreground",  [NSNumber numberWithInt:(int)kDarkGrayHighlight],
            @"Gray Foreground",  [NSNumber numberWithInt:(int)kGrayHighlight],
            @"Green Foreground",  [NSNumber numberWithInt:(int)kGreenHighlight],
            @"Light Gray Foreground",  [NSNumber numberWithInt:(int)kLighGrayHighlight],
            @"Magenta Foreground",  [NSNumber numberWithInt:(int)kMagentaHighlight],
            @"Orange Foreground",  [NSNumber numberWithInt:(int)kOrangeHighlight],
            @"Purple Foreground",  [NSNumber numberWithInt:(int)kPurpleHighlight],
            @"Red Foreground",  [NSNumber numberWithInt:(int)kRedHighlight],
            @"White Foreground",  [NSNumber numberWithInt:(int)kWhiteHighlight],
            @"Yellow Foreground",  [NSNumber numberWithInt:(int)kYellowHighlight],

            @"Black Background",  [NSNumber numberWithInt:(int)kBlackBackgroundHighlight],
            @"Blue Background",  [NSNumber numberWithInt:(int)kBlueBackgroundHighlight],
            @"Brown Background",  [NSNumber numberWithInt:(int)kBrownBackgroundHighlight],
            @"Cyan Background",  [NSNumber numberWithInt:(int)kCyanBackgroundHighlight],
            @"Gray Background",  [NSNumber numberWithInt:(int)kDarkGrayBackgroundHighlight],
            @"Gray Background",  [NSNumber numberWithInt:(int)kGrayBackgroundHighlight],
            @"Gren Background",  [NSNumber numberWithInt:(int)kGreenBackgroundHighlight],
            @"Light Gray Background",  [NSNumber numberWithInt:(int)kLighGrayBackgroundHighlight],
            @"Magenta Background",  [NSNumber numberWithInt:(int)kMagentaBackgroundHighlight],
            @"Orange Background",  [NSNumber numberWithInt:(int)kOrangeBackgroundHighlight],
            @"Purple Background",  [NSNumber numberWithInt:(int)kPurpleBackgroundHighlight],
            @"Red Background",  [NSNumber numberWithInt:(int)kRedBackgroundHighlight],
            @"White Background",  [NSNumber numberWithInt:(int)kWhiteBackgroundHighlight],
            @"Yellow Background",  [NSNumber numberWithInt:(int)kYellowBackgroundHighlight],

            nil];
}

- (NSArray *)groupedMenuItemsForPopupButton {
    NSDictionary *fgbg = [NSDictionary dictionaryWithObjectsAndKeys:
                          @"Yellow on Black", [NSNumber numberWithInt:(int)kYellowOnBlackHighlight],
                          @"Black on Yellow", [NSNumber numberWithInt:(int)kBlackOnYellowHighlight],
                          @"White on Red",    [NSNumber numberWithInt:(int)kWhiteOnRedHighlight],
                          @"Red on White",    [NSNumber numberWithInt:(int)kRedOnWhiteHighlight],
                          @"Black on Orange", [NSNumber numberWithInt:(int)kBlackOnOrangeHighlight],
                          @"Orange on Black", [NSNumber numberWithInt:(int)kOrangeOnBlackHighlight],
                          @"Purple on Black", [NSNumber numberWithInt:(int)kPurpleOnBlackHighlight],
                          @"Black on Purple", [NSNumber numberWithInt:(int)kBlackOnPurpleHighlight],
                          nil];
    NSDictionary *fg = [NSDictionary dictionaryWithObjectsAndKeys:
                        @"Black Foreground",  [NSNumber numberWithInt:(int)kBlackHighlight],
                        @"Blue Foreground",  [NSNumber numberWithInt:(int)kBlueHighlight],
                        @"Brown Foreground",  [NSNumber numberWithInt:(int)kBrownHighlight],
                        @"Cyan Foreground",  [NSNumber numberWithInt:(int)kCyanHighlight],
                        @"Dark Gray Foreground",  [NSNumber numberWithInt:(int)kDarkGrayHighlight],
                        @"Gray Foreground",  [NSNumber numberWithInt:(int)kGrayHighlight],
                        @"Green Foreground",  [NSNumber numberWithInt:(int)kGreenHighlight],
                        @"Light Gray Foreground",  [NSNumber numberWithInt:(int)kLighGrayHighlight],
                        @"Magenta Foreground",  [NSNumber numberWithInt:(int)kMagentaHighlight],
                        @"Orange Foreground",  [NSNumber numberWithInt:(int)kOrangeHighlight],
                        @"Purple Foreground",  [NSNumber numberWithInt:(int)kPurpleHighlight],
                        @"Red Foreground",  [NSNumber numberWithInt:(int)kRedHighlight],
                        @"White Foreground",  [NSNumber numberWithInt:(int)kWhiteHighlight],
                        @"Yellow Foreground",  [NSNumber numberWithInt:(int)kYellowHighlight],
                        nil];

    NSDictionary *bg = [NSDictionary dictionaryWithObjectsAndKeys:
                        @"Black Background",  [NSNumber numberWithInt:(int)kBlackBackgroundHighlight],
                        @"Blue Background",  [NSNumber numberWithInt:(int)kBlueBackgroundHighlight],
                        @"Brown Background",  [NSNumber numberWithInt:(int)kBrownBackgroundHighlight],
                        @"Cyan Background",  [NSNumber numberWithInt:(int)kCyanBackgroundHighlight],
                        @"Gray Background",  [NSNumber numberWithInt:(int)kDarkGrayBackgroundHighlight],
                        @"Gray Background",  [NSNumber numberWithInt:(int)kGrayBackgroundHighlight],
                        @"Gren Background",  [NSNumber numberWithInt:(int)kGreenBackgroundHighlight],
                        @"Light Gray Background",  [NSNumber numberWithInt:(int)kLighGrayBackgroundHighlight],
                        @"Magenta Background",  [NSNumber numberWithInt:(int)kMagentaBackgroundHighlight],
                        @"Orange Background",  [NSNumber numberWithInt:(int)kOrangeBackgroundHighlight],
                        @"Purple Background",  [NSNumber numberWithInt:(int)kPurpleBackgroundHighlight],
                        @"Red Background",  [NSNumber numberWithInt:(int)kRedBackgroundHighlight],
                        @"White Background",  [NSNumber numberWithInt:(int)kWhiteBackgroundHighlight],
                        @"Yellow Background",  [NSNumber numberWithInt:(int)kYellowBackgroundHighlight],
                        nil];
    return [NSArray arrayWithObjects:fgbg, fg, bg, nil];
}

- (int)indexOfTag:(int)theTag
{
    int i = 0;
    BOOL isFirst = YES;
    for (NSDictionary *dict in [self groupedMenuItemsForPopupButton]) {
        if (!isFirst) {
            ++i;
        }
        isFirst = NO;
        for (NSNumber *n in [self tagsSortedByValueInDict:dict]) {
            if ([n intValue] == theTag) {
                return i;
            }
            i++;
        }
    }
    return -1;
}

- (int)tagAtIndex:(int)theIndex
{
    int i = 0;
    BOOL isFirst = YES;
    for (NSDictionary *dict in [self groupedMenuItemsForPopupButton]) {
        if (!isFirst) {
            ++i;
        }
        isFirst = NO;
        for (NSNumber *n in [self tagsSortedByValueInDict:dict]) {
            if (i == theIndex) {
                return [n intValue];
            }
            i++;
        }
    }
    return -1;
}

- (NSDictionary *)dictionaryWithForegroundColor:(NSColor *)foreground
                                backgroundColor:(NSColor *)background
{
    return [NSDictionary dictionaryWithObjectsAndKeys:foreground, kHighlightForegroundColor, background, kHighlightBackgroundColor, nil];
}

- (NSDictionary *)dictionaryWithForegroundColor:(NSColor *)foreground
{
    return [NSDictionary dictionaryWithObjectsAndKeys:foreground, kHighlightForegroundColor, nil];
}

- (NSDictionary *)dictionaryWithBackgroundColor:(NSColor *)background
{
    return [NSDictionary dictionaryWithObjectsAndKeys:background, kHighlightBackgroundColor, nil];
}

- (NSDictionary *)colors
{
    switch ([self.param intValue]) {
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

        case kLighGrayHighlight:
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

        case kLighGrayBackgroundHighlight:
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

- (void)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession
{
    [[aSession SCREEN] highlightTextMatchingRegex:self.regex
                                           colors:[self colors]];
}

@end
