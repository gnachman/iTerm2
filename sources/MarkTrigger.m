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
#import "SessionView.h"

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

- (NSInteger)indexForObject:(id)object {
    int i = 0;
    for (NSNumber *n in [self objectsSortedByValueInDict:[self menuItemsForPoupupButton]]) {
        if ([n isEqual:object]) {
            return i;
        }
        i++;
    }
    return -1;
}

- (id)objectAtIndex:(NSInteger)index {
    int i = 0;

    for (NSNumber *n in [self objectsSortedByValueInDict:[self menuItemsForPoupupButton]]) {
        if (i == index) {
            return n;
        }
        i++;
    }
    return nil;
}

- (NSDictionary *)menuItemsForPoupupButton
{
    return @{ @(kMarkTriggerParamTagKeepScrolling): @"Keep Scrolling",
              @(kMarkTriggerParamTagStopScrolling): @"Stop Scrolling" };
}

- (BOOL)shouldStopScrolling {
    return [self.param intValue] == kMarkTriggerParamTagStopScrolling;
}

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                                    stop:(BOOL *)stop {
    [aSession.screen terminalSaveScrollPositionWithArgument:@"saveCursorLine"];
    if ([self shouldStopScrolling]) {
        [[aSession.view.scrollview verticalScroller] setUserScroll:YES];
    }
    return YES;
}

- (int)defaultIndex {
    return [self indexForObject:@(kMarkTriggerParamTagKeepScrolling)];
}

@end
