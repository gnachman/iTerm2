//
//  iTermSetTitleTrigger.m
//  iTerm2
//
//  Created by George Nachman on 1/1/17.
//
//

#import "iTermSetTitleTrigger.h"

#import "iTermSessionNameController.h"

@implementation iTermSetTitleTrigger

+ (NSString *)title
{
    return @"Set Title…";
}

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
    return @"Enter new title";
}

- (BOOL)isIdempotent {
    return YES;
}

- (BOOL)takesParameter
{
    return YES;
}

- (BOOL)performActionWithCapturedStrings:(NSArray<NSString *> *)stringArray
                          capturedRanges:(const NSRange *)capturedRanges
                               inSession:(id<iTermTriggerSession>)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    // Need to stop the world to get scope, provided it is needed. Title changes are slow & rare that this is ok.
    [[self paramWithBackreferencesReplacedWithValues:stringArray
                                              scope:[aSession triggerSessionVariableScope:self]
                                              owner:aSession
                                    useInterpolation:useInterpolation] then:^(NSString * _Nonnull newName) {
        [aSession triggerSession:self didChangeNameTo:newName];
    }];
    return YES;
}

@end
