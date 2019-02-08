//
//  iTermRPCTrigger.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/22/18.
//

#import "iTermRPCTrigger.h"
#import "iTermFunctionCallTextFieldDelegate.h"
#import "iTermScriptFunctionCall.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "PTYSession.h"

static NSString *const iTermRPCTriggerPathCapturedStrings = @"trigger.captured_strings";
static NSString *const iTermRPCTriggerPathCapturedRanges = @"trigger.captured_ranges";
static NSString *const iTermRPCTriggerPathInput = @"trigger.input";
static NSString *const iTermRPCTriggerPathLineNumber = @"trigger.line_number";
// NOTE: When adding new paths, update -allPaths

@implementation iTermRPCTrigger

+ (NSString *)title {
    return @"Invoke Script Function";
}

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
    return @"Function call";
}

- (BOOL)takesParameter {
    return YES;
}

- (NSArray<NSString *> *)allPaths {
    return @[ iTermRPCTriggerPathCapturedStrings,
              iTermRPCTriggerPathCapturedRanges,
              iTermRPCTriggerPathInput,
              iTermRPCTriggerPathLineNumber ];
}

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    NSString *invocation = self.param;

    NSArray<NSString *> *captureStringArray = [[NSArray alloc] initWithObjects:capturedStrings
                                                                         count:captureCount];
    NSMutableArray<NSArray<NSNumber *> *> *captureRangeArray = [NSMutableArray array];
    for (NSInteger i = 0; i < captureCount; i++) {
        [captureRangeArray addObject:@[ @(capturedRanges[i].location), @(capturedRanges[i].length) ]];
    }

    NSDictionary *temporaryVariables = @{ iTermRPCTriggerPathCapturedStrings: captureStringArray,
                                          iTermRPCTriggerPathCapturedRanges: captureRangeArray,
                                          iTermRPCTriggerPathInput: stringLine.stringValue ?: @"",
                                          iTermRPCTriggerPathLineNumber: @(lineNumber) };
    iTermVariableScope *scope = [self variableScope:aSession.variablesScope
                             byAddingBackreferences:captureStringArray];
    [scope setValuesFromDictionary:temporaryVariables];
    [aSession invokeFunctionCall:invocation scope:scope origin:@"Trigger"];

    return YES;
}

- (id<NSTextFieldDelegate>)newParameterDelegateWithPassthrough:(id<NSTextFieldDelegate>)passthrough {
    return [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession
                                                                                                       augmentedWith:[NSSet setWithArray:self.allPaths]]
                                                              passthrough:passthrough
                                                            functionsOnly:YES];
}

@end
