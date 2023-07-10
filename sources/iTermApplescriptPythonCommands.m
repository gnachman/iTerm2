//
//  iTermApplescriptPythonCommands.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/24/19.
//

#import "iTermApplescriptPythonCommands.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermAPIScriptLauncher.h"
#import "iTermScriptsMenuController.h"
#import "iTermExpressionEvaluator.h"
#import "iTermExpressionParser.h"
#import "iTermParsedExpression.h"
#import "iTermVariableScope+Global.h"
#import "NSFileManager+iTerm.h"

@implementation iTermLaunchAPIScriptCommand

- (id)performDefaultImplementation {
    NSString *scriptName = self.directParameter;
    if (!scriptName) {
        [self setScriptErrorNumber:1];
        [self setScriptErrorString:@"No script name was specified"];
        return nil;
    }
    NSArray<NSString *> *args = self.evaluatedArguments[@"arguments"];
    if ([scriptName hasPrefix:@"/"]) {
        [[[[iTermApplication sharedApplication] delegate] scriptsMenuController] launchScriptWithAbsolutePath:scriptName
                                                                                                    arguments:args
                                                                                           explicitUserAction:NO];
        return nil;
    }
    NSArray<NSString *> *relativeFilenames = [[[[iTermApplication sharedApplication] delegate] scriptsMenuController] allScripts];
    for (NSString *relativeFilename in relativeFilenames) {
        if ([relativeFilename isEqualToString:scriptName]) {
            [self launchPythonScript:relativeFilename arguments:args];
            return nil;
        }
    }
    for (NSString *relativeFilename in relativeFilenames) {
        if ([relativeFilename.stringByDeletingPathExtension isEqualToString:scriptName]) {
            [self launchPythonScript:relativeFilename arguments:args];
            return nil;
        }
    }
    for (NSString *relativeFilename in relativeFilenames) {
        if ([relativeFilename.lastPathComponent isEqualToString:scriptName]) {
            [self launchPythonScript:relativeFilename arguments:args];
            return nil;
        }
    }
    for (NSString *relativeFilename in relativeFilenames) {
        if ([relativeFilename.lastPathComponent.stringByDeletingPathExtension isEqualToString:scriptName]) {
            [self launchPythonScript:relativeFilename arguments:args];
            return nil;
        }
    }

    [self setScriptErrorNumber:2];
    [self setScriptErrorString:@"Script not found"];
    return nil;
}

- (void)launchPythonScript:(NSString *)script arguments:(NSArray<NSString *> *)arguments {
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
        return;
    }
    [[[[iTermApplication sharedApplication] delegate] scriptsMenuController] launchScriptWithRelativePath:script
                                                                                                arguments:arguments
                                                                                       explicitUserAction:NO];
}

@end

@implementation iTermInvokeAPIExpressionCommand

- (id)performDefaultImplementation {
    NSString *invocation = self.directParameter;
    if (!invocation) {
        [self setScriptErrorNumber:1];
        [self setScriptErrorString:@"No string to invoke was specified"];
        return nil;
    }
    iTermParsedExpression *parsedExpression =
    [[iTermExpressionParser expressionParser] parse:invocation
                                              scope:[iTermVariableScope globalsScope]];

    BOOL sync = NO;
    switch (parsedExpression.expressionType) {
        case iTermParsedExpressionTypeError:
            [self setScriptErrorNumber:1];
            [self setScriptErrorString:parsedExpression.error.localizedDescription];
            return nil;

        case iTermParsedExpressionTypeNil:
        case iTermParsedExpressionTypeNumber:
        case iTermParsedExpressionTypeString:
        case iTermParsedExpressionTypeArrayLookup:
        case iTermParsedExpressionTypeArrayOfValues:
        case iTermParsedExpressionTypeVariableReference:
        case iTermParsedExpressionTypeBoolean:
            sync = YES;
            break;

        case iTermParsedExpressionTypeArrayOfExpressions:
        case iTermParsedExpressionTypeInterpolatedString:
        case iTermParsedExpressionTypeFunctionCall:
        case iTermParsedExpressionTypeFunctionCalls:
            sync = NO;
            break;
    }
    iTermExpressionEvaluator *evaluator =
    [[iTermExpressionEvaluator alloc] initWithParsedExpression:parsedExpression
                                                    invocation:invocation
                                                         scope:[iTermVariableScope globalsScope]];
    [self suspendExecution];
    __weak __typeof(self) weakSelf = self;
    [evaluator evaluateWithTimeout:sync ? 0 : 10 completion:^(iTermExpressionEvaluator * _Nonnull evaluator) {
        if (evaluator.error) {
            [self setScriptErrorNumber:2];
            [self setScriptErrorString:evaluator.error.localizedDescription];
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf resumeExecutionWithResult:nil];
            });
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf resumeExecutionWithResult:[NSString stringWithFormat:@"%@", evaluator.value]];
        });
    }];
    return nil;
}

@end
