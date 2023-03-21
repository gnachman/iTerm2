//
//  AnnotateTrigger.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/13/19.
//

#import "AnnotateTrigger.h"
#import "ScreenChar.h"
#import "PTYAnnotation.h"

@implementation AnnotateTrigger

+ (NSString *)title
{
    return @"Annotate…";
}

- (BOOL)takesParameter
{
    return YES;
}

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
    return @"Enter annotation";
}


- (BOOL)performActionWithCapturedStrings:(NSArray<NSString *> *)stringArray
                          capturedRanges:(const NSRange *)capturedRanges
                               inSession:(id<iTermTriggerSession>)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    const NSRange rangeInString = capturedRanges[0];
    const NSRange rangeInScreenChars = [stringLine rangeOfScreenCharsForRangeInString:rangeInString];
    const long long length = rangeInScreenChars.length;
    if (length == 0) {
        return YES;
    }
    // Need to stop the world to get scope, provided it is needed. This is potentially going to be a performance problem for a small number of users.
    id<PTYAnnotationReading> annotation =
        [aSession triggerSession:self
           makeAnnotationInRange:rangeInScreenChars
                            line:lineNumber];
    if (!annotation) {
        return YES;
    }
    id<iTermTriggerScopeProvider> scopeProvider = [aSession triggerSessionVariableScopeProvider:self];
    id<iTermTriggerCallbackScheduler> scheduler = [scopeProvider triggerCallbackScheduler];
    [[self paramWithBackreferencesReplacedWithValues:stringArray
                                             absLine:lineNumber
                                               scope:scopeProvider
                                    useInterpolation:useInterpolation] then:^(NSString * _Nonnull text) {
        [scheduler scheduleTriggerCallback:^{
            [aSession triggerSession:self
                       setAnnotation:annotation
                            stringTo:text];
        }];
    }];
    return YES;
}

@end
