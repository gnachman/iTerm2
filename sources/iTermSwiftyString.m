//
//  iTermSwiftyString.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/12/18.
//

#import "iTermSwiftyString.h"

#import "DebugLogging.h"
#import "iTermAPIHelper.h"
#import "iTermExpressionEvaluator.h"
#import "iTermScriptFunctionCall.h"
#import "iTermScriptHistory.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

@implementation iTermSwiftyString
- (void)setSwiftyString:(NSString *)swiftyString {
    [self setStringToEvaluate:swiftyString];
}

- (NSString *)swiftyString {
    return [self stringToEvaluate];
}

- (NSString *)evaluatedString {
    return [NSString castFrom:self.evaluationResult];
}

- (iTermExpressionEvaluator *)expressionEvaluator {
    return [[iTermExpressionEvaluator alloc] initWithInterpolatedString:self.swiftyString
                                                                  scope:self.scope];
}

- (void)evaluateSynchronously:(BOOL)synchronously
           sideEffectsAllowed:(BOOL)sideEffectsAllowed
                    withScope:(iTermVariableScope *)scope
                   completion:(void (^)(NSString *, NSError *, NSSet<NSString *> *))completion {
    // Make the compiler happy since we have a string result and super has an id result, but we know
    // it will always be a string because of the expression evaluator we provide.
    return [super evaluateSynchronously:synchronously
                     sideEffectsAllowed:sideEffectsAllowed
                              withScope:scope
                             completion:completion];
}
@end

@implementation iTermExpressionObserver

- (iTermExpressionEvaluator *)expressionEvaluator {
    return [[iTermExpressionEvaluator alloc] initWithExpressionString:self.stringToEvaluate
                                                                scope:self.scope];
}

@end

@implementation iTermSwiftyStringPlaceholder {
    NSString *_string;
}

- (instancetype)initWithString:(NSString *)swiftyString {
    self = [super initWithString:@""
                           scope:nil
              sideEffectsAllowed:NO
                        observer:^NSString *(NSString * _Nonnull newValue, NSError *error) { return newValue; }];
    if (self) {
        _string = [swiftyString copy];
    }
    return self;
}

- (NSString *)swiftyString {
    return _string;
}

@end
