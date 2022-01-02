//
//  SetDirectoryTrigger.m
//  iTerm2
//
//  Created by George Nachman on 11/9/15.
//
//

#import "SetDirectoryTrigger.h"

#import "DebugLogging.h"
#import "VT100Screen+Mutation.h"

@implementation SetDirectoryTrigger

+ (NSString *)title {
  return @"Report Directory";
}

- (BOOL)takesParameter{
  return YES;
}

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
  return @"Directory";
}

- (BOOL)isIdempotent {
    return YES;
}

- (BOOL)performActionWithCapturedStrings:(NSArray<NSString *> *)stringArray
                          capturedRanges:(const NSRange *)capturedRanges
                               inSession:(id<iTermTriggerSession>)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    // Need to stop the world to get scope, provided it is needed. Directory changes slow & rare that this is ok.
    [self paramWithBackreferencesReplacedWithValues:stringArray
                                              scope:[aSession triggerSessionVariableScope:self]
                                              owner:aSession
                                   useInterpolation:useInterpolation
                                         completion:^(NSString *currentDirectory) {
        DLog(@"SetDirectoryTrigger completed substitution with %@", currentDirectory);
        if (currentDirectory.length) {
            [aSession triggerSession:self setCurrentDirectory:currentDirectory];
        }
    }];
    return YES;
}


@end
