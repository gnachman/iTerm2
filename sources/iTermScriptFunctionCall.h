//
//  iTermScriptFunctionCall.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/18/18.
//

#import <Foundation/Foundation.h>

@interface iTermScriptFunctionCall : NSObject

// Invokes a function given in invocation.
// invocation should look like:
//
// function_name(argname: argvalue [, argname: argvalue ...])
//
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
// Functions will timeout after a short period of no response. This is an
// error condition.
+ (void)callFunction:(NSString *)invocation
              source:(id (^)(NSString *))source
          completion:(void (^)(id, NSError *))completion;

@end
