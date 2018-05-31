//
//  iTermEval.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/30/18.
//

#import "iTermEval.h"

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
- (NSString *)stringByPerformingSubstitutionsOnString:(NSString *)string;
@end

@implementation NSString(iTermEval)

- (NSString *)it_stringByEvaluatingStringWith:(iTermEval *)eval {
    if (eval) {
        return [eval stringByPerformingSubstitutionsOnString:self];
    } else {
        return self;
    }
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

- (NSString *)stringByPerformingSubstitutionsOnString:(NSString *)string {
    NSString *result = string;
    result = [result stringByReplacingOccurrencesOfString:@"$$$$" withString:@"$$"];
    result = [result stringByPerformingSubstitutions:_macros];
    return result;
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
