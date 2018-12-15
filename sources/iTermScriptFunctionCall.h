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

// Evaluates an expression given in invocation.
// invocation should look like one of:
//
// 1. function_name(argname: argvalue [, argname: argvalue ...])
// 2. variable
// 3. variable?
//
// If it is a function:
// --------------------
// function_name and argname are identifiers containing ASCII alphanumerics and
// starting with a letter.
//
// argvalue is a path like session.id, consisting of dotted identifiers. A path
// may end in a question mark, like session.id? if the value's nonexistence is
// acceptable.
//
// argvalue may also be a string literal in "quotes" with JSON escaping.
//
// argvalue may also be a decimal number.
//
// The provided source block takes a path (minus the trailing ?) and returns
// its value as a string or number. It may return nil if the path has no value.
//
// completion is invoked either with the first argument having the function's
// return value or with the second argument giving its reason for failing.
// The error will have a localizedDescription and may have a localizedReason
// giving a traceback.
//
// Functions can return any object encodable in JSON (arrays, dictionaries,
// strings, numbers, null.
//
// Functions will timeout after a specified period of no response. This is an
// error condition.
//
// If it is a variable:
// --------------------
// The value will be returned, or an error if undefined. Optional variables ending
// with a ? will return empty string if undefined.
//
// NOTE ON TIMEOUT:
// If timeout is 0, then this guarantees to complete synchronously. All non-builtin
// functions will evaluate to empty string.
+ (void)evaluateExpression:(NSString *)invocation
                   timeout:(NSTimeInterval)timeout
                     scope:(iTermVariableScope *)scope
                completion:(void (^)(id, NSError *, NSSet<NSString *> *missingFunctionSignatures))completion;

// Like evaluateExpression but only accepts a function call at the top level.
+ (void)callFunction:(NSString *)invocation
             timeout:(NSTimeInterval)timeout
               scope:(iTermVariableScope *)scope
          completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion;

+ (NSString *)signatureForFunctionCallInvocation:(NSString *)invocation
                                           error:(out NSError **)error;

// Evaluate a string with embedded function calls like a swift string with \(expression)s in it.
// If you need a string that changes dynamically as its dependencies (i.e., variables) change,
// use iTermSwiftyString instead.
+ (void)evaluateString:(NSString *)string
               timeout:(NSTimeInterval)timeout
                 scope:(iTermVariableScope *)scope
            completion:(void (^)(NSString *result,
                                 NSError *error,
                                 NSSet<NSString *> *missingFunctionSignatures))completion;

@end
