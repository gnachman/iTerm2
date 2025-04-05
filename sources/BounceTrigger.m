//
//  BounceTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "BounceTrigger.h"

// How to bounce. The parameter takes an integer value equal to one of these. This is the tag.
typedef NS_ENUM(int, BounceTriggerParamTag) {
    kBounceTriggerParamTagBounceUntilFocus,
    kBounceTriggerParamTagBounceOnce,
};

@implementation BounceTrigger

+ (NSString *)title
{
    return @"Bounce Dock Icon";
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Bounce dock icon %@", self.bounceType == NSCriticalRequest ? @"until focused" : @"once"];
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

- (BOOL)isIdempotent {
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

+ (NSString *)stringForParameter:(BounceTriggerParamTag)parameter {
    switch (parameter) {
        case kBounceTriggerParamTagBounceUntilFocus:
            return @"Bounce Until Activated";
        case kBounceTriggerParamTagBounceOnce:
            return @"Bounce Once";
    }
    return @"Bounce Until Activated";
}

- (NSDictionary *)menuItemsForPoupupButton
{
    return @{ @(kBounceTriggerParamTagBounceUntilFocus): [BounceTrigger stringForParameter:kBounceTriggerParamTagBounceUntilFocus],
              @(kBounceTriggerParamTagBounceOnce): [BounceTrigger stringForParameter:kBounceTriggerParamTagBounceOnce] };
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

- (BOOL)performActionWithCapturedStrings:(NSArray<NSString *> *)stringArray
                          capturedRanges:(const NSRange *)capturedRanges
                               inSession:(id<iTermTriggerSession>)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    const NSRequestUserAttentionType bounceType = [self bounceType];
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSApp requestUserAttention:bounceType];
    });
    return YES;
}

- (int)defaultIndex {
    return [self indexForObject:@(kBounceTriggerParamTagBounceUntilFocus)];
}

- (NSAttributedString *)paramAttributedString {
    return [[NSAttributedString alloc] initWithString:[BounceTrigger stringForParameter:[[NSNumber castFrom:self.param] intValue]]
                                           attributes:self.regularAttributes];
}

@end
