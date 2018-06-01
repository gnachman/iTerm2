//
//  iTermEval.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/30/18.
//

#import "iTermEval.h"

#import "iTermAPIHelper.h"
#import "iTermFunctionCallParser.h"
#import "iTermScriptFunctionCall.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

@interface iTermEvalMissingValue : NSString
@end

@implementation iTermEvalMissingValue
@end

NS_ASSUME_NONNULL_BEGIN

@interface iTermEvalPanelWindowController : NSWindowController
@property (nonatomic, strong) IBOutlet NSTextField *parameterName;
@property (nonatomic, strong) IBOutlet NSTextField *parameterValue;
@property (nonatomic, strong) IBOutlet NSTextField *parameterPrompt;
@property (nonatomic, readonly) BOOL parameterPanelCanceled;
@end

@implementation iTermEvalPanelWindowController

// Called when the parameter panel should close.
- (IBAction)parameterPanelEnd:(id)sender {
    _parameterPanelCanceled = ([sender tag] == 0);
    [NSApp stopModal];
}

@end

@interface iTermEval()
- (void)evaluateString:(NSString *)string
               timeout:(NSTimeInterval)timeout
                source:(NSString * _Nonnull (^)(NSString * _Nonnull))source
            completion:(void (^)(NSString * _Nonnull))completion;
@end

@implementation NSString(iTermEval)

- (void)it_evaluateWith:(iTermEval *)eval
                timeout:(NSTimeInterval)timeout
                 source:(NSString * _Nonnull (^)(NSString * _Nonnull))source
             completion:(void (^)(NSString * _Nonnull))completion {
    if (!eval) {
        completion(self);
    }

    [eval evaluateString:self timeout:timeout source:source completion:completion];
}

@end

static NSString *const iTermEvalDictionaryIsEval = @"$$$$iTermEval$$$$";
static NSString *const iTermEvalDictionaryKeyMacros = @"macros";
static NSString *const iTermEvalDictionaryKeyMacroNames = @"macro names";

@implementation iTermEval {
    NSMutableDictionary<NSString *, NSString *> *_macros;
    iTermEvalPanelWindowController *_panelWindowController;
}

- (instancetype)initWithMacros:(nullable NSDictionary<NSString *, NSString *> *)macros {
    self = [super init];
    if (self) {
        _macros = [macros ?: @{} mutableCopy];
    }
    return self;
}

- (instancetype)initWithDictionaryValue:(NSDictionary *)dictionaryValue {
    if ([[NSNumber castFrom:dictionaryValue[iTermEvalDictionaryIsEval]] boolValue]) {
        // Modern path
        return [self initWithMacros:dictionaryValue[iTermEvalDictionaryKeyMacros]];
    } else {
        // Legacy path
        return[ self initWithMacros:dictionaryValue];
    }
}

- (NSDictionary *)dictionaryValue {
    return @{ iTermEvalDictionaryIsEval: @YES,
              iTermEvalDictionaryKeyMacros: _macros ?: @{} };
}

- (void)addStringWithPossibleSubstitutions:(NSString *)string {
    for (NSString *name in string.doubleDollarVariables) {
        _macros[name] = [[iTermEvalMissingValue alloc] init];
    }
}

- (BOOL)promptForMissingValuesInWindow:(NSWindow *)parent {
    for (NSString *name in _macros.allKeys) {
        NSString *value = _macros[name];
        if ([iTermEvalMissingValue castFrom:value]) {
            value = [self promptForParameter:name inWindow:parent];
            if (!value) {
                return NO;
            }
            _macros[name] = value;
        }
    }
    return YES;
}

- (void)replaceMissingValuesWithString:(NSString *)replacement {
    for (NSString *name in _macros.allKeys) {
        NSString *value = _macros[name];
        if ([iTermEvalMissingValue castFrom:value]) {
            _macros[name] = replacement.copy;
        }
    }
}

- (void)evaluateString:(NSString *)string
               timeout:(NSTimeInterval)timeout
                source:(NSString * _Nonnull (^)(NSString * _Nonnull))source
            completion:(void (^)(NSString * _Nonnull))completion {
    NSString *substitutedString = string;
    substitutedString = [substitutedString stringByReplacingOccurrencesOfString:@"$$$$" withString:@"$$"];
    substitutedString = [substitutedString stringByPerformingSubstitutions:_macros];
    NSMutableString *result = [NSMutableString string];
    NSMutableArray<NSString *> *evaluatedSubstrings = [NSMutableArray array];
    dispatch_group_t group = dispatch_group_create();
    [substitutedString enumerateSwiftySubstrings:^(NSString *substring, BOOL isLiteral) {
        if (isLiteral) {
            [evaluatedSubstrings addObject:substring];
        } else {
            NSError *error;
            iTermScriptFunctionCall *call = [[iTermFunctionCallParser sharedInstance] parse:substring
                                                                                     source:source];
            if (!call || call.error) {
                [evaluatedSubstrings addObject:@""];
#warning TODO: Handle errors better
                return;
            }

            const NSInteger index = evaluatedSubstrings.count;
            [evaluatedSubstrings addObject:@""];
            iTermAPIHelper *helper = [iTermAPIHelper sharedInstance];
            dispatch_group_enter(group);
            [helper performBlockWhenFunctionRegisteredWithName:call.name arguments:call.argumentNames timeout:1 block:^(BOOL timedOut) {
                if (timedOut) {
#warning Handle timeouts
                    dispatch_group_leave(group);
                    return;
                }
                [call callWithCompletion:^(id output, NSError *callError) {
                    if (callError) {
#warning Handle errors
                        dispatch_group_leave(group);
                        return;
                    }
                    NSString *string = [NSString castFrom:output];
                    if (string) {
                        evaluatedSubstrings[index] = string;
                    } else {
                        evaluatedSubstrings[index] = [NSJSONSerialization it_jsonStringForObject:output];
                    }
                    dispatch_group_leave(group);
                }];
            }];
        }
    }];
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        completion([evaluatedSubstrings componentsJoinedByString:@""]);
    });
}

#pragma mark - Private

- (NSString *)promptForParameter:(NSString *)name inWindow:(NSWindow *)parent {
    // Make the name pretty.
    name = [name stringByReplacingOccurrencesOfString:@"$$" withString:@""];
    name = [name stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    name = [name lowercaseString];
    if (name.length) {
        NSString *firstLetter = [name substringWithRange:NSMakeRange(0, 1)];
        NSString *lastLetters = [name substringFromIndex:1];
        name = [[firstLetter uppercaseString] stringByAppendingString:lastLetters];
    }

    _panelWindowController = [[iTermEvalPanelWindowController alloc] initWithWindowNibName:@"iTermEvalPanel"];
    [_panelWindowController window];
    [_panelWindowController.parameterName setStringValue:[NSString stringWithFormat:@"“%@”:", name]];
    [_panelWindowController.parameterValue setStringValue:@""];

    [parent beginSheet:_panelWindowController.window completionHandler:nil];
    [NSApp runModalForWindow:_panelWindowController.window];
    [parent endSheet:_panelWindowController.window];
    [_panelWindowController.window orderOut:self];
    NSString *result;
    if (_panelWindowController.parameterPanelCanceled) {
        result = nil;
    } else {
        result = [_panelWindowController.parameterValue.stringValue copy];
    }
    _panelWindowController = nil;
    return result;
}

@end

NS_ASSUME_NONNULL_END
