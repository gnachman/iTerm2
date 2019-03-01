//
//  iTermExpressionEvaluator.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/28/19.
//

#import <Foundation/Foundation.h>

@class iTermVariableScope;

NS_ASSUME_NONNULL_BEGIN

@interface iTermExpressionEvaluator : NSObject
// If you access this before calling evaluateWithTimeout you get the result of the synchronous
// evaluation.
@property (nonatomic, readonly) id value;
@property (nonatomic, readonly) NSError *error;
@property (nonatomic, readonly) NSSet<NSString *> *missingValues;

// If object is an iTermParsedExpression, it is evaluated as you'd expect.
// Strings are evaluated as swifty strings.
// NSNumber comes back as NSNumber.
// nil comes back as NSNull
// Arrays get each of their elements evaluated.
//
// Note what this does NOT do is evaluate strings *containing* expressions!
// A string "foo(x: y)" gets evaluated as a swifty string.
- (instancetype)initWithObject:(id)object
                         scope:(iTermVariableScope *)scope NS_DESIGNATED_INITIALIZER;

// This takes an expression as input, for example "foo(x:y)".
- (instancetype)initWithExpressionString:(NSString *)expressionString
                                   scope:(iTermVariableScope *)scope;

- (instancetype)init NS_UNAVAILABLE;

- (void)evaluateWithTimeout:(NSTimeInterval)timeout
                 completion:(void (^)(iTermExpressionEvaluator *evaluator))completion;

@end

NS_ASSUME_NONNULL_END
