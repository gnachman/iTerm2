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
      nil];
}

- (NSArray *)tagsSortedByValue
{
    return [[self menuItemsForPoupupButton] keysSortedByValueUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (int)indexOfTag:(int)theTag
{
    int i = 0;
    for (NSNumber *n in [self tagsSortedByValue]) {
        if ([n intValue] == theTag) {
            return i;
        }
        i++;
    }
    return -1;
}

- (int)tagAtIndex:(int)theIndex
{
    return [[[self tagsSortedByValue] objectAtIndex:theIndex] intValue];
}

- (int)colorCodeForColor:(NSColor *)theColor
{
    theColor = [theColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    int r = 5 * [theColor redComponent];
    int g = 5 * [theColor greenComponent];
    int b = 5 * [theColor blueComponent];
    return 16 + b + g*6 + r*36;
}

- (screen_char_t)prototypeChar
{
  screen_char_t sct;
  sct.alternateBackgroundSemantics = NO;
  sct.alternateForegroundSemantics = NO;
  sct.bold = NO;
  sct.blink = NO;
  sct.underline = NO;
  switch ([self.param intValue]) {
    case kYellowOnBlackHighlight:
      sct.foregroundColor = [self colorCodeForColor:[NSColor yellowColor]];
      sct.backgroundColor = [self colorCodeForColor:[NSColor blackColor]];
      break;

    case kBlackOnYellowHighlight:
      sct.foregroundColor = [self colorCodeForColor:[NSColor blackColor]];
      sct.backgroundColor = [self colorCodeForColor:[NSColor yellowColor]];
      break;

    case kWhiteOnRedHighlight:
      sct.foregroundColor = [self colorCodeForColor:[NSColor whiteColor]];
      sct.backgroundColor = [self colorCodeForColor:[NSColor redColor]];
      break;

    case kRedOnWhiteHighlight:
      sct.foregroundColor = [self colorCodeForColor:[NSColor redColor]];
      sct.backgroundColor = [self colorCodeForColor:[NSColor whiteColor]];
      break;

    case kBlackOnOrangeHighlight:
      sct.foregroundColor = [self colorCodeForColor:[NSColor blackColor]];
      sct.backgroundColor = [self colorCodeForColor:[NSColor orangeColor]];
      break;

    case kOrangeOnBlackHighlight:
      sct.foregroundColor = [self colorCodeForColor:[NSColor orangeColor]];
      sct.backgroundColor = [self colorCodeForColor:[NSColor blackColor]];
      break;

    case kBlackOnPurpleHighlight:
      sct.foregroundColor = [self colorCodeForColor:[NSColor blackColor]];
      sct.backgroundColor = [self colorCodeForColor:[NSColor purpleColor]];
      break;

    case kPurpleOnBlackHighlight:
      sct.foregroundColor = [self colorCodeForColor:[NSColor purpleColor]];
      sct.backgroundColor = [self colorCodeForColor:[NSColor blackColor]];
      break;
  }
  return sct;
}

- (void)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession
{
  [[aSession SCREEN] highlightTextMatchingRegex:self.regex
                                  prototypeChar:[self prototypeChar]];
}

@end
