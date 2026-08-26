//
//  iTermExpressionParser.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import <Foundation/Foundation.h>
#import <CoreParse/CoreParse.h>
#import "iTermParsedExpression.h"

@interface iTermExpressionParser : NSObject <CPParserDelegate, CPTokeniserDelegate>

// Use this to get an instance. Only on the main thread.
// Parses strings like: foo(x:y)
+ (instancetype)callParser NS_SWIFT_NAME(callParser());

// Parses expressions, like:
// 1
// "foo \(bar)"
// [1, 2]
+ (instancetype)expressionParser NS_SWIFT_NAME(expressionParser());

- (instancetype)init NS_UNAVAILABLE;

- (iTermParsedExpression *)parse:(NSString *)invocation scope:(iTermVariableScope *)scope;

+ (iTermParsedExpression *)parsedExpressionWithInterpolatedString:(NSString *)swifty
                                                            scope:(iTermVariableScope *)scope;

// Strings get passed through escapingFunction, if nonnil.
+ (iTermParsedExpression *)parsedExpressionWithInterpolatedString:(NSString *)swifty
                                                 escapingFunction:(NSString *(^)(NSString *string))escapingFunction
                                                            scope:(iTermVariableScope *)scope
                                                           strict:(BOOL)strict;

// When annotateUndefinedVariables is YES, a reference to an undefined variable is rendered inline
// as "[undefined variable <path>]" instead of being silently replaced with an empty string. This
// makes typos and unavailable variables obvious while authoring interpolated strings.
+ (iTermParsedExpression *)parsedExpressionWithInterpolatedString:(NSString *)swifty
                                                 escapingFunction:(NSString *(^)(NSString *string))escapingFunction
                                                            scope:(iTermVariableScope *)scope
                                                           strict:(BOOL)strict
                                       annotateUndefinedVariables:(BOOL)annotateUndefinedVariables;

// Given an invocation like foo(x: "bar", y: [1, 2]) returns the signature like foo(x,y)
+ (NSString *)signatureForFunctionCallInvocation:(NSString *)invocation
                                           error:(out NSError *__autoreleasing *)error;

@end

