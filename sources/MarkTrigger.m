//
//  MarkTrigger.m
//  iTerm
//
//  Created by George Nachman on 4/22/14.
//
//

#import "MarkTrigger.h"
#import "PTYScrollView.h"
#import "PTYSession.h"

// Whether to stop scrolling.
typedef enum {
    kMarkTriggerParamTagKeepScrolling,
    kMarkTriggerParamTagStopScrolling,
} MarkTriggerParam;

@implementation MarkTrigger

+ (NSString *)title {
    return @"Set Mark";
}

- (NSString *)paramPlaceholder {
    return @"";
}

- (BOOL)takesParameter {
    return YES;
}

- (BOOL)paramIsPopupButton {
    return YES;
}

- (int)indexOfTag:(int)theTag {
    int i = 0;
    for (NSNumber *n in [self objectsSortedByValueInDict:[self menuItemsForPoupupButton]]) {
        if ([n intValue] == theTag) {
            return i;
        }
        i++;
    }
    return -1;
}

- (int)tagAtIndex:(int)index {
    int i = 0;

    for (NSNumber *n in [self objectsSortedByValueInDict:[self menuItemsForPoupupButton]]) {
        if (i == index) {
            return [n intValue];
        }
        i++;
    }
    return -1;
}

- (NSDictionary *)menuItemsForPoupupButton
{
    return @{ @(kMarkTriggerParamTagKeepScrolling): @"Keep Scrolling",
              @(kMarkTriggerParamTagStopScrolling): @"Stop Scrolling" };
}

- (BOOL)shouldStopScrolling {
    return [self.param intValue] == kMarkTriggerParamTagStopScrolling;
}

- (BOOL)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession onString:(NSString *)string atAbsoluteLineNumber:(long long)absoluteLineNumber stop:(BOOL *)stop {
    [aSession.screen terminalSaveScrollPositionWithArgument:@"saveCursorLine"];
    if ([self shouldStopScrolling]) {
        [(PTYScroller *)[aSession.scrollview verticalScroller] setUserScroll:YES];
    }
    return YES;
}

- (int)defaultIndex {
    return [self indexOfTag:kMarkTriggerParamTagKeepScrolling];
}

@end
