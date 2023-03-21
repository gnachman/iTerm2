//
//  iTermHyperlinkTrigger.m
//  iTerm2
//
//  Created by leppich on 09.05.18.
//

#import "NSURL+iTerm.h"
#import "iTermHyperlinkTrigger.h"
#import "ScreenChar.h"

#import <CoreServices/CoreServices.h>
#import <QuartzCore/QuartzCore.h>

@implementation iTermHyperlinkTrigger

+ (NSString *)title {
    return @"Make Hyperlink…";
}

- (BOOL)takesParameter {
    return YES;
}

- (BOOL)isIdempotent {
    return YES;
}

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
    return [self triggerOptionalDefaultParameterValueWithInterpolation:interpolation];
}

- (NSString *)triggerOptionalDefaultParameterValueWithInterpolation:(BOOL)interpolation {
    if (interpolation) {
        return @"https://\\(match0)";
    }
    return @"https://\\0";
}

- (BOOL)performActionWithCapturedStrings:(NSArray<NSString *> *)stringArray
                          capturedRanges:(const NSRange *)capturedRanges
                               inSession:(id<iTermTriggerSession>)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    const NSRange rangeInString = capturedRanges[0];
    const NSRange rangeOnScreen = [stringLine rangeOfScreenCharsForRangeInString:rangeInString];

    // Need to stop the world to get scope, provided it is needed. This is potentially going to be a performance problem for a small number of users.
    id<iTermTriggerScopeProvider> scopeProvider = [aSession triggerSessionVariableScopeProvider:self];
    id<iTermTriggerCallbackScheduler> scheduler = [scopeProvider triggerCallbackScheduler];
    [[self paramWithBackreferencesReplacedWithValues:stringArray
                                             absLine:lineNumber
                                               scope:scopeProvider
                                    useInterpolation:useInterpolation] then:^(NSString * _Nonnull urlString) {
        [scheduler scheduleTriggerCallback:^{
            [self performActionWithURLString:urlString
                                       range:rangeOnScreen
                                     session:aSession
                          absoluteLineNumber:lineNumber];
        }];
    }];
    return YES;
}

- (void)performActionWithURLString:(NSString *)urlString
                             range:(NSRange)rangeInString
                           session:(id<iTermTriggerSession>)aSession
                absoluteLineNumber:(long long)lineNumber {
    NSURL *url = urlString.length ? [NSURL URLWithUserSuppliedString:urlString] : nil;
    if (!url) {
        return;
    }

    [aSession triggerSession:self
          makeHyperlinkToURL:url
                     inRange:rangeInString
                        line:lineNumber];
}

@end
