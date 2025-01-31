//
//  iTermScriptFunctionCall+Private.h
//  iTerm2
//
//  Created by George Nachman on 5/20/18.
//

#import "iTermScriptFunctionCall.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermParsedExpression;

@interface iTermScriptFunctionCall()

@property (nonatomic, copy) NSString *namespace;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, readonly) NSString *connectionKey;

- (void)performFunctionCallFromInvocation:(NSString *)invocation
                                 receiver:(NSString * _Nullable)receiver
                                    scope:(iTermVariableScope *)scope
                                  timeout:(NSTimeInterval)timeout
                               completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion;

- (void)addParameterWithName:(NSString *)name parsedExpression:(iTermParsedExpression *)expression;

@end

NS_ASSUME_NONNULL_END
