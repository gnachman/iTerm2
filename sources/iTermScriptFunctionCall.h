//
//  iTermScriptFunctionCall.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/18/18.
//

#import <Foundation/Foundation.h>

@class iTermVariableScope;
@class iTermParsedExpression;

@interface iTermScriptFunctionCall : NSObject

@property (nonatomic, readonly) NSString *signature;
@property (nonatomic, readonly) NSString *name;

// The 'invocation' must be a function call and cannot be any other kind of expression.
// Hold a reference to the result until you no longer care to receive the completion block, or pass retainSelf: YES
+ (iTermParsedExpression *)callFunction:(NSString *)invocation
                                timeout:(NSTimeInterval)timeout
                                  scope:(iTermVariableScope *)scope
                             retainSelf:(BOOL)retainSelf  // YES to keep it alive until it's complete
                             completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion;

+ (iTermParsedExpression *)callMethod:(NSString *)invocation
                             receiver:(NSString *)receiver
                              timeout:(NSTimeInterval)timeout
                           retainSelf:(BOOL)retainSelf  // YES to keep it alive until it's complete
                           completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion;

@end
