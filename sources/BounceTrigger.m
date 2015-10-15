//
//  BounceTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "BounceTrigger.h"

// How to bounce. The parameter takes an integer value equal to one of these. This is the tag.
enum {
    kBounceTriggerParamTagBounceUntilFocus,
    kBounceTriggerParamTagBounceOnce,
};

@implementation BounceTrigger

+ (NSString *)title
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

- (NSInteger)indexOfTag:(NSInteger)theTag {
    int i = 0;
    for (NSNumber *n in [self objectsSortedByValueInDict:[self menuItemsForPoupupButton]]) {
        if ([n intValue] == theTag) {
            return i;
        }
        i++;
    }
    return -1;
}

- (NSInteger)tagAtIndex:(NSInteger)index {
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
    return @{ @(kBounceTriggerParamTagBounceUntilFocus): @"Bounce Until Activated",
              @(kBounceTriggerParamTagBounceOnce): @"Bounce Once" };
}

- (NSRequestUserAttentionType)bounceType
{
    switch ([self.param intValue]) {
        case kBounceTriggerParamTagBounceUntilFocus:
            return NSCriticalRequest;

        case kBounceTriggerParamTagBounceOnce:
            return NSInformationalRequest;

        default:
            return NSCriticalRequest;
    }
}

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                                    stop:(BOOL *)stop {
    [NSApp requestUserAttention:[self bounceType]];
    return YES;
}

- (int)defaultIndex {
    return [self indexOfTag:kBounceTriggerParamTagBounceUntilFocus];
}

@end
