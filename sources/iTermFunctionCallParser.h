//
//  iTermFunctionCallParser.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import <Foundation/Foundation.h>
#import <CoreParse/CoreParse.h>

@class iTermScriptFunctionCall;
@class iTermVariableScope;

typedef NS_ENUM(NSUInteger, iTermParsedExpressionType) {
    iTermParsedExpressionTypeNil,
    iTermParsedExpressionTypeArray,
    iTermParsedExpressionTypeString,
    iTermParsedExpressionTypeNumber,
    iTermParsedExpressionTypeFunctionCall,
    iTermParsedExpressionTypeError,
    iTermParsedExpressionTypeInterpolatedString
};

@interface iTermParsedExpression : NSObject
// Only one property will be set.
@property (nonatomic, readonly) iTermParsedExpressionType expressionType;

@property (nonatomic, strong, readonly) NSArray *array;
@property (nonatomic, strong, readonly) NSString *string;
@property (nonatomic, strong, readonly) NSNumber *number;
@property (nonatomic, strong, readonly) NSError *error;
@property (nonatomic, strong, readonly) iTermScriptFunctionCall *functionCall;
@property (nonatomic, strong, readonly) NSArray *interpolatedStringParts;

// This is always equal to the only set property above (or nil if none is set)
@property (nonatomic, strong, readonly) id object;

@property (nonatomic, readonly) BOOL optional;

- (instancetype)initWithString:(NSString *)string optional:(BOOL)optional;
- (instancetype)initWithFunctionCall:(iTermScriptFunctionCall *)functionCall;
- (instancetype)initWithErrorCode:(int)code reason:(NSString *)localizedDescription;
// Object may be NSString, NSNumber, or NSArray. If it is not, an error will be created with the
// given reason.
- (instancetype)initWithObject:(id)object errorReason:(NSString *)errorReason;
- (instancetype)initWithOptionalObject:(id)object;
- (instancetype)initWithNumber:(NSNumber *)number;
- (instancetype)initWithError:(NSError *)error;
- (instancetype)initWithInterpolatedStringParts:(NSArray *)parts;
- (instancetype)initWithArray:(NSArray *)array;

@end

@interface iTermFunctionCallParser : NSObject <CPParserDelegate, CPTokeniserDelegate>

+ (CPTokeniser *)newTokenizer;
+ (id<CPTokenRecogniser>)stringRecognizerWithClass:(Class)theClass;
+ (void)setEscapeReplacerInStringRecognizer:(id)stringRecogniser;
+ (NSString *)signatureForTopLevelInvocation:(NSString *)invocation;

// Use this to get an instance. Only on the main thread.
+ (instancetype)callParser;
+ (instancetype)expressionParser;

- (instancetype)init NS_UNAVAILABLE;
// Start gives root grammar rule name.
- (id)initWithStart:(NSString *)start NS_DESIGNATED_INITIALIZER;

- (iTermParsedExpression *)parse:(NSString *)invocation scope:(iTermVariableScope *)scope;

@end
