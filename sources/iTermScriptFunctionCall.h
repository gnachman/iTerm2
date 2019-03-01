//
//  iTermScriptFunctionCall.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/18/18.
//

#import <Foundation/Foundation.h>

@class iTermVariableScope;

@interface iTermScriptFunctionCall : NSObject

@property (nonatomic, readonly) NSString *signature;
@property (nonatomic, readonly) NSString *name;

// The 'invocation' must be a function call and cannot be any other kind of expression.
+ (void)callFunction:(NSString *)invocation
             timeout:(NSTimeInterval)timeout
               scope:(iTermVariableScope *)scope
          completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion;

@end
