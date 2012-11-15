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
          
      case kBlackHighlight:
          sct.foregroundColor = [self colorCodeForColor:[NSColor blackColor]];
          break;
          
      case kDarkGrayHighlight:
          sct.foregroundColor = [self colorCodeForColor:[NSColor darkGrayColor]];
          break;
          
      case kLighGrayHighlight:
          sct.foregroundColor = [self colorCodeForColor:[NSColor lightGrayColor]];
          break;
          
      case kWhiteHighlight:
          sct.foregroundColor = [self colorCodeForColor:[NSColor whiteColor]];
          break;
          
      case kGrayHighlight:
          sct.foregroundColor = [self colorCodeForColor:[NSColor grayColor]];
          break;
          
      case kRedHighlight:
          sct.foregroundColor = [self colorCodeForColor:[NSColor redColor]];
          break;
          
      case kGreenHighlight:
          sct.foregroundColor = [self colorCodeForColor:[NSColor greenColor]];
          break;
          
      case kBlueHighlight:
          sct.foregroundColor = [self colorCodeForColor:[NSColor blueColor]];
          break;
          
      case kCyanHighlight:
          sct.foregroundColor = [self colorCodeForColor:[NSColor cyanColor]];
          break;
          
      case kYellowHighlight:
          sct.foregroundColor = [self colorCodeForColor:[NSColor yellowColor]];
          break;
          
      case kMagentaHighlight:
          sct.foregroundColor = [self colorCodeForColor:[NSColor magentaColor]];
          break;
          
      case kOrangeHighlight:
          sct.foregroundColor = [self colorCodeForColor:[NSColor orangeColor]];
          break;
          
      case kPurpleHighlight:
          sct.foregroundColor = [self colorCodeForColor:[NSColor purpleColor]];
          break;
          
      case kBrownHighlight:
          sct.foregroundColor = [self colorCodeForColor:[NSColor brownColor]];
          break;
          
          
          // --------------
      case kBlackBackgroundHighlight:
          sct.backgroundColor = [self colorCodeForColor:[NSColor blackColor]];
          break;
          
      case kDarkGrayBackgroundHighlight:
          sct.backgroundColor = [self colorCodeForColor:[NSColor darkGrayColor]];
          break;
          
      case kLighGrayBackgroundHighlight:
          sct.backgroundColor = [self colorCodeForColor:[NSColor lightGrayColor]];
          break;
          
      case kWhiteBackgroundHighlight:
          sct.backgroundColor = [self colorCodeForColor:[NSColor whiteColor]];
          break;
          
      case kGrayBackgroundHighlight:
          sct.backgroundColor = [self colorCodeForColor:[NSColor grayColor]];
          break;
          
      case kRedBackgroundHighlight:
          sct.backgroundColor = [self colorCodeForColor:[NSColor redColor]];
          break;
          
      case kGreenBackgroundHighlight:
          sct.backgroundColor = [self colorCodeForColor:[NSColor greenColor]];
          break;
          
      case kBlueBackgroundHighlight:
          sct.backgroundColor = [self colorCodeForColor:[NSColor blueColor]];
          break;
          
      case kCyanBackgroundHighlight:
          sct.backgroundColor = [self colorCodeForColor:[NSColor cyanColor]];
          break;
          
      case kYellowBackgroundHighlight:
          sct.backgroundColor = [self colorCodeForColor:[NSColor yellowColor]];
          break;
          
      case kMagentaBackgroundHighlight:
          sct.backgroundColor = [self colorCodeForColor:[NSColor magentaColor]];
          break;
          
      case kOrangeBackgroundHighlight:
          sct.backgroundColor = [self colorCodeForColor:[NSColor orangeColor]];
          break;
          
      case kPurpleBackgroundHighlight:
          sct.backgroundColor = [self colorCodeForColor:[NSColor purpleColor]];
          break;
          
      case kBrownBackgroundHighlight:
          sct.backgroundColor = [self colorCodeForColor:[NSColor brownColor]];
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
