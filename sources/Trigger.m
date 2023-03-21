//
//  Trigger.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "Trigger.h"
#import "DebugLogging.h"
#import "iTermSwiftyString.h"
#import "iTermVariableScope.h"
#import "iTermWarning.h"
#import "NSStringITerm.h"
#import "RegexKitLite.h"
#import "ScreenChar.h"
#import <CommonCrypto/CommonDigest.h>
#import "iTerm2SharedARC-Swift.h"

NSString * const kTriggerRegexKey = @"regex";
NSString * const kTriggerActionKey = @"action";
NSString * const kTriggerParameterKey = @"parameter";
NSString * const kTriggerPartialLineKey = @"partial";
NSString * const kTriggerDisabledKey = @"disabled";

@interface Trigger()
@end

@implementation Trigger {
    // The last absolute line number on which this trigger fired for a partial
    // line. -1 means it has not fired on the current line.
    long long _lastLineNumber;
    NSString *regex_;
    id param_;
    iTermSwiftyStringWithBackreferencesEvaluator *_evaluator;
    NSRegularExpression *_compiledRegex;
}

@synthesize regex = regex_;
@synthesize param = param_;

+ (NSSet<NSString *> *)synonyms {
    return [NSSet set];
}

// The purpose of this is to re-encode colors that were previously key-value encoded into hex so that the Python APi can consume them.
+ (NSDictionary *)sanitizedTriggerDictionary:(NSDictionary *)dict {
    Trigger *trigger = [self triggerFromDict:dict];
    [trigger sanitize];
    return trigger.dictionaryValue;
}

+ (Trigger *)triggerFromDict:(NSDictionary *)dict
{
    NSString *className = [dict objectForKey:kTriggerActionKey];
    Class class = NSClassFromString(className);
    Trigger *trigger = [[class alloc] init];
    trigger.regex = dict[kTriggerRegexKey];
    trigger.param = dict[kTriggerParameterKey];
    trigger.partialLine = [dict[kTriggerPartialLineKey] boolValue];
    trigger.disabled = [dict[kTriggerDisabledKey] boolValue];
    return trigger;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lastLineNumber = -1;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p regex=%@ param=%@>",
            NSStringFromClass(self.class), self, self.regex, self.param];
}

- (NSString *)action {
    return NSStringFromClass([self class]);
}

- (void)setAction:(NSString *)action {
    assert(false);
}

- (void)sanitize {
    // Do nothing by default because most triggers don't neet sanitization.
}

+ (NSString *)title {
    // Subclasses must override this
    assert(false);
}

- (NSString *)title
{
    assert(false);
}

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
    assert(false);
}

- (NSString *)triggerOptionalDefaultParameterValueWithInterpolation:(BOOL)interpolation {
    return nil;
}

- (BOOL)takesParameter
{
    assert(false);
}

- (BOOL)paramIsPopupButton {
    return NO;
}

- (BOOL)paramIsTwoColorWells {
    return NO;
}

- (BOOL)paramIsTwoStrings {
    return NO;
}

- (NSDictionary *)menuItemsForPoupupButton
{
    return nil;
}

- (BOOL)isIdempotent {
    return NO;
}

- (NSArray *)groupedMenuItemsForPopupButton
{
    NSDictionary *menuItems = [self menuItemsForPoupupButton];
    if (menuItems) {
        return @[ menuItems ];
    } else {
        return nil;
    }
}

- (id<iTermFocusReportingTextFieldDelegate>)newParameterDelegateWithPassthrough:(id<NSTextFieldDelegate>)passthrough {
    return nil;
}

- (BOOL)performActionWithCapturedStrings:(NSArray<NSString *> *)stringArray
                          capturedRanges:(const NSRange *)capturedRanges
                               inSession:(id<iTermTriggerSession>)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    assert(false);
    return NO;
}

- (BOOL)instantTriggerCanFireMultipleTimesPerLine {
    return NO;
}

- (void)setRegex:(NSString *)regex {
    regex_ = [regex copy];
    _compiledRegex = [NSRegularExpression regularExpressionWithPattern:regex_ options:0 error:nil];
}

- (void)enumerateMatchesInString:(NSString *)string
                           block:(void (^)(NSArray<NSString *> *capturedStrings,
                                           const NSRange *capturedRanges,
                                           BOOL *stop))block {
    const size_t maxStaticRangeCount = 16;
    __block size_t rangeCapacity = maxStaticRangeCount;
    NSRange rangeStorage[maxStaticRangeCount];
    __block NSRange *ranges = rangeStorage;
    __block NSRange *dynamicRangeStorage = NULL;
    [_compiledRegex enumerateMatchesInString:string options:0 range:NSMakeRange(0, string.length) usingBlock:^(NSTextCheckingResult * _Nullable result, NSMatchingFlags flags, BOOL * _Nonnull stop) {
        NSMutableArray<NSString *> *captures = [NSMutableArray arrayWithCapacity:result.numberOfRanges];
        if (result.numberOfRanges > rangeCapacity) {
            dynamicRangeStorage = iTermRealloc(dynamicRangeStorage, result.numberOfRanges, sizeof(NSRange));
            ranges = dynamicRangeStorage;
            rangeCapacity = result.numberOfRanges;
        }

        for (NSInteger i = 0; i < result.numberOfRanges; i++) {
            const NSRange range = [result rangeAtIndex:i];
            NSString *substring;
            if (range.length == 0) {
                substring = @"";
            } else {
                substring = [string substringWithRange:range];
            }
            [captures addObject:substring];
            ranges[i] = [result rangeAtIndex:i];
        }
        block(captures, ranges, stop);

    }];
    if (ranges != rangeStorage) {
        free(ranges);
    }
}

- (BOOL)tryString:(iTermStringLine *)stringLine
        inSession:(id<iTermTriggerSession>)aSession
      partialLine:(BOOL)partialLine
       lineNumber:(long long)lineNumber
 useInterpolation:(BOOL)useInterpolation {
    if (self.disabled) {
        return NO;
    }
    if (_partialLine &&
        !self.instantTriggerCanFireMultipleTimesPerLine &&
        _lastLineNumber == lineNumber) {
        // Already fired a on a partial line on this line.
        if (!partialLine) {
            _lastLineNumber = -1;
        }
        return NO;
    }
    if (partialLine && !_partialLine) {
        // This trigger doesn't support partial lines.
        return NO;
    }
    
    __block BOOL stopFutureTriggersFromRunningOnThisLine = NO;
    NSString *s = stringLine.stringValue;
    DLog(@"Search for regex %@ in string %@", regex_, s);
    if (![iTermAdvancedSettingsModel fastTriggerRegexes]) {
        DLog(@"Use RegexKitLite");
        [s enumerateStringsMatchedByRegex:regex_
                               usingBlock:^(NSInteger captureCount,
                                            NSString *const __unsafe_unretained *capturedStrings,
                                            const NSRange *capturedRanges,
                                            volatile BOOL *const stopEnumerating) {
            self->_lastLineNumber = lineNumber;
            DLog(@"Trigger %@ matched string %@", self, s);
            NSArray<NSString *> *stringArray = [[NSArray alloc] initWithObjects:capturedStrings
                                                                          count:captureCount];
            if (![self performActionWithCapturedStrings:stringArray
                                         capturedRanges:capturedRanges
                                              inSession:aSession
                                               onString:stringLine
                                   atAbsoluteLineNumber:lineNumber
                                       useInterpolation:useInterpolation
                                                   stop:&stopFutureTriggersFromRunningOnThisLine]) {
                *stopEnumerating = YES;
            }
        }];
    } else if (s != nil) {
        DLog(@"Use NSRegularExpression");
        [self enumerateMatchesInString:s block:^(NSArray<NSString *> *stringArray,
                                                 const NSRange *capturedRanges,
                                                 BOOL *stopEnumerating) {
            self->_lastLineNumber = lineNumber;
            DLog(@"Trigger %@ matched string %@", self, s);
            if (![self performActionWithCapturedStrings:stringArray
                                         capturedRanges:capturedRanges
                                              inSession:aSession
                                               onString:stringLine
                                   atAbsoluteLineNumber:lineNumber
                                       useInterpolation:useInterpolation
                                                   stop:&stopFutureTriggersFromRunningOnThisLine]) {
                *stopEnumerating = YES;
            }
        }];
    }
    if (!partialLine) {
        _lastLineNumber = -1;
    }
    return stopFutureTriggersFromRunningOnThisLine;
}

- (iTermPromise<NSString *> *)paramWithBackreferencesReplacedWithValues:(NSArray *)stringArray
                                                                absLine:(long long)absLine
                                                                  scope:(id<iTermTriggerScopeProvider>)scopeProvider
                                                       useInterpolation:(BOOL)useInterpolation {
    NSString *p = [NSString castFrom:self.param] ?: @"";
    if (useInterpolation && [p interpolatedStringContainsNonliteral]) {
        return [iTermPromise promise:^(id<iTermPromiseSeal>  _Nonnull seal) {
            [scopeProvider performBlockWithScope:^(iTermVariableScope * _Nonnull scope, id<iTermObject> _Nonnull object) {
                assert([NSThread isMainThread]);
                [self evaluateSwiftyStringParameter:p
                                     backreferences:stringArray
                                            absLine:absLine
                                              scope:scope
                                              owner:object
                                         completion:^(NSString *value) {
                    if (value) {
                        [seal fulfill:value];
                    } else {
                        [seal reject:[NSError errorWithDomain:@"com.iterm2.trigger" code:0 userInfo:nil]];
                    }
                }];
            }];
        }];
    }
    
    const NSUInteger count = stringArray.count;
    for (int i = 0; i < 9; i++) {
        NSString *rep = @"";
        if (count > i) {
            rep = stringArray[i];
        }
        p = [p stringByReplacingBackreference:i withString:rep];
    }
    p = [p stringByReplacingEscapedChar:'a' withString:@"\x07"];
    p = [p stringByReplacingEscapedChar:'b' withString:@"\x08"];
    p = [p stringByReplacingEscapedChar:'e' withString:@"\x1b"];
    p = [p stringByReplacingEscapedChar:'n' withString:@"\n"];
    p = [p stringByReplacingEscapedChar:'r' withString:@"\r"];
    p = [p stringByReplacingEscapedChar:'t' withString:@"\t"];
    p = [p stringByReplacingEscapedChar:'\\' withString:@"\\"];
    p = [p stringByReplacingEscapedHexValuesWithChars];

    return [iTermPromise promise:^(id<iTermPromiseSeal>  _Nonnull seal) {
        [seal fulfill:p];
    }];
}

- (iTermVariableScope *)variableScope:(iTermVariableScope *)scope byAddingBackreferences:(NSArray<NSString *> *)backreferences {
    return [scope variableScopeByAddingBackreferences:backreferences owner:self];
}

- (void)evaluateSwiftyStringParameter:(NSString *)expression
                       backreferences:(NSArray<NSString *> *)backreferences
                              absLine:(long long)absLine
                                scope:(iTermVariableScope *)scope
                                owner:(id<iTermObject>)owner
                           completion:(void (^)(NSString *))completion {
    if (!_evaluator) {
        _evaluator = [[iTermSwiftyStringWithBackreferencesEvaluator alloc] initWithExpression:expression];
    } else {
        _evaluator.expression = expression;
    }
    __weak __typeof(self) weakSelf = self;
    [_evaluator evaluateWithAdditionalContext:@{ @"matches": backreferences, @"line": @(absLine) }
                                        scope:scope
                                        owner:owner
                                   completion:^(NSString * _Nullable value, NSError * _Nullable error) {
        if (error) {
            [weakSelf evaluationDidFailWithError:error];
            completion(nil);
        } else {
            completion(value);
        }
    }];
}

- (void)evaluationDidFailWithError:(NSError *)error {
    NSString *title =
    [NSString stringWithFormat:@"The following parameter for a “%@” trigger could not be evaluated:\n\n%@\n\nThe error was:\n\n%@",
     [[self class] title],
     _evaluator.expression,
     error.localizedDescription];
    [iTermWarning showWarningWithTitle:title
                               actions:@[ @"OK" ]
                             accessory:nil
                            identifier:@"NoSyncErrorInTriggerParameter"
                           silenceable:kiTermWarningTypeTemporarilySilenceable
                               heading:@"Error in Trigger Parameter"
                                window:nil];
}

- (NSComparisonResult)compareTitle:(Trigger *)other
{
    return [[self title] compare:[other title]];
}

- (NSInteger)indexForObject:(id)object {
    return [object intValue];
}

- (id)objectAtIndex:(NSInteger)index {
    return @(index);
}

- (NSArray *)objectsSortedByValueInDict:(NSDictionary *)dict
{
    return [dict keysSortedByValueUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (int)defaultIndex {
    return 0;
}

- (id)defaultPopupParameterObject {
    return @0;
}

// Called before a trigger window opens.
- (void)reloadData {
}

- (NSDictionary *)dictionaryValue {
    return @{ kTriggerActionKey: NSStringFromClass(self.class),
              kTriggerRegexKey: self.regex ?: @"",
              kTriggerParameterKey: self.param ?: @"",
              kTriggerPartialLineKey: @(self.partialLine),
              kTriggerDisabledKey: @(self.disabled) };
}

- (NSData *)digest {
    NSDictionary *triggerDictionary = [self dictionaryValue];
    
    // Glom all the data together as key=value\nkey=value\n...
    NSMutableString *temp = [NSMutableString string];
    for (NSString *key in [[triggerDictionary allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [temp appendFormat:@"%@=%@\n", key, triggerDictionary[key]];
    }
    
    NSData *data = [temp dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA1_DIGEST_LENGTH];
    if (CC_SHA1([data bytes], [data length], hash) ) {
        NSData *sha1 = [NSData dataWithBytes:hash length:CC_SHA1_DIGEST_LENGTH];
        return sha1;
    } else {
        return data;
    }
}

+ (NSDictionary *)triggerNormalizedDictionary:(NSDictionary *)dict {
    NSMutableDictionary *temp = [dict mutableCopy];
    if (!temp[kTriggerPartialLineKey]) {
        temp[kTriggerPartialLineKey] = @NO;
    }
    if (!temp[kTriggerDisabledKey]) {
        temp[kTriggerDisabledKey] = @NO;
    }
    if (!temp[kTriggerParameterKey]) {
        temp[kTriggerParameterKey] = @"";
    }
    return temp;
}

#pragma mark - iTermObject

- (iTermBuiltInFunctions *)objectMethodRegistry {
    return nil;
}

- (iTermVariableScope *)objectScope {
    return nil;
}

@end
