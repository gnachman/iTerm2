//
//  iTermExpressionEvaluator.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/28/19.
//

#import <Foundation/Foundation.h>

@class iTermParsedExpression;
@class iTermVariableScope;

NS_ASSUME_NONNULL_BEGIN

@interface iTermExpressionEvaluator : NSObject
// If you access this before calling evaluateWithTimeout you get the result of the synchronous
// evaluation.
@property (nonatomic, readonly) id value;
@property (nonatomic, readonly) NSError *error;
@property (nonatomic, readonly) NSSet<NSString *> *missingValues;

- (instancetype)initWithParsedExpression:(iTermParsedExpression *)parsedExpression
                              invocation:(NSString *)invocation
                                   scope:(iTermVariableScope *)scope NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithExpressionString:(NSString *)expressionString
                                   scope:(iTermVariableScope *)scope;

- (instancetype)initWithInterpolatedString:(NSString *)interpolatedString
                                     scope:(iTermVariableScope *)scope;

- (instancetype)init NS_UNAVAILABLE;

// Evaluates an expression. If timeout is 0 then it completes synchronously without making RPCs.
// If the timeout is positive the object will live until the timer fires or the RPC completes.
// Callers do not need to retain a reference to the expression evaluator.
- (void)evaluateWithTimeout:(NSTimeInterval)timeout
                 completion:(void (^)(iTermExpressionEvaluator *evaluator))completion;

@end

NS_ASSUME_NONNULL_END
