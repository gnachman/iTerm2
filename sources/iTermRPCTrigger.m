//
//  iTermRPCTrigger.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/22/18.
//

#import "iTermRPCTrigger.h"
#import "iTermFunctionCallTextFieldDelegate.h"
#import "iTermScriptFunctionCall.h"
#import "iTermVariables.h"
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

- (NSString *)paramPlaceholder {
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
                                    stop:(BOOL *)stop {
    NSString *invocation = [self paramWithBackreferencesReplacedWithValues:capturedStrings
                                                                     count:captureCount];
    NSMutableArray<NSString *> *captureStringArray = [NSMutableArray array];
    NSMutableArray<NSArray<NSNumber *> *> *captureRangeArray = [NSMutableArray array];
    for (NSInteger i = 0; i < captureCount; i++) {
        [captureStringArray addObject:capturedStrings[i] ?: @""];
        [captureRangeArray addObject:@[ @(capturedRanges[i].location), @(capturedRanges[i].length) ]];
    }

    NSDictionary *context = @{ iTermRPCTriggerPathCapturedStrings: captureStringArray,
                               iTermRPCTriggerPathCapturedRanges: captureRangeArray,
                               iTermRPCTriggerPathInput: stringLine.stringValue ?: @"",
                               iTermRPCTriggerPathLineNumber: @(lineNumber) };

    [aSession invokeFunctionCall:invocation extraContext:context];

    return YES;
}

- (id<NSTextFieldDelegate>)newParameterDelegateWithPassthrough:(id<NSTextFieldDelegate>)passthrough {
    NSArray<NSString *> *paths = [[self allPaths] arrayByAddingObjectsFromArray:iTermVariablesGetAll()];
    return [[iTermFunctionCallTextFieldDelegate alloc] initWithPaths:paths
                                                         passthrough:passthrough];
}

@end
