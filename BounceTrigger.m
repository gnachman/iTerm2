//
//  BounceTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "BounceTrigger.h"

enum {
    kBounceUntilFocus,
    kBounceOnce,
};

@implementation BounceTrigger

- (NSString *)title
{
    return @"Bounce Dock Icon";
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

- (int)indexOfTag:(int)theTag
{
    int i = 0;
    for (NSNumber *n in [self tagsSortedByValueInDict:[self menuItemsForPoupupButton]]) {
        if ([n intValue] == theTag) {
            return i;
        }
        i++;
    }
    return -1;
}

- (int)tagAtIndex:(int)index
{
    int i = 0;

    for (NSNumber *n in [self tagsSortedByValueInDict:[self menuItemsForPoupupButton]]) {
        if (i == index) {
            return [n intValue];
        }
        i++;
    }
    return -1;
}

- (NSDictionary *)menuItemsForPoupupButton
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            @"Bounce until focus", [NSNumber numberWithInt:(int)kBounceUntilFocus],
            @"Bounce once", [NSNumber numberWithInt:(int)kBounceOnce],

            nil];
}

- (NSRequestUserAttentionType)bounceType
{
    switch ([self.param intValue]) {
        case kBounceUntilFocus:
            return NSCriticalRequest;

        case kBounceOnce:
            return NSInformationalRequest;

        default:
            break;
    }
    return NSCriticalRequest;
}

- (void)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession
{
    [NSApp requestUserAttention:[self bounceType]];
}

@end
