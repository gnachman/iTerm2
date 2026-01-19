//
//  iTermParsedExpression.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/1/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermIndirectValue;
@class iTermScriptFunctionCall;
@class iTermVariableScope;
@class iTermVariableReference;
@class iTermSubexpression;

typedef NS_ENUM(NSUInteger, iTermParsedExpressionType) {
    iTermParsedExpressionTypeNil,
    iTermParsedExpressionTypeArrayOfExpressions,
    iTermParsedExpressionTypeArrayOfValues,
    iTermParsedExpressionTypeString,  // This only occurs inside interpolated string parts arrays.
    iTermParsedExpressionTypeSubexpression,
    iTermParsedExpressionTypeFunctionCall,
    iTermParsedExpressionTypeError,
    iTermParsedExpressionTypeInterpolatedString,
    iTermParsedExpressionTypeReference,
    iTermParsedExpressionTypeIndirectValue,

    // These two are only produced if you request an AST from the expression parser
    iTermParsedExpressionTypeVariableReference,
    iTermParsedExpressionTypeArrayLookup,
    iTermParsedExpressionTypeFunctionCalls,

    // Note: When adding new types, also update the Python function iterm2_encode().
};

@protocol iTermExpressionParserPlaceholder<NSObject>
@property (nonatomic, readonly, copy) NSString *path;
- (iTermParsedExpressionType)expressionType;
@end

@interface iTermExpressionParserArrayDereferencePlaceholder : NSObject<iTermExpressionParserPlaceholder>
@property (nonatomic, readonly) iTermSubexpression *indexExpression;
- (instancetype)initWithPath:(NSString *)path indexExpression:(iTermSubexpression *)indexExpression;
@end

@interface iTermExpressionParserVariableReferencePlaceholder : NSObject<iTermExpressionParserPlaceholder>
- (instancetype)initWithPath:(NSString *)path;
@end

@interface iTermParsedExpression : NSObject
// Only one property will be set.
@property (nonatomic, readonly) iTermParsedExpressionType expressionType;

@property (nonatomic, strong, readonly) NSArray<iTermParsedExpression *> *arrayOfExpressions;
@property (nonatomic, strong, readonly) NSArray *arrayOfValues;
@property (nonatomic, strong, readonly) NSString *string;
@property (nonatomic, strong, readonly) iTermSubexpression *subexpression;
@property (nonatomic, strong, readonly) iTermIndirectValue *indirectValue;
@property (nonatomic, strong, readonly) NSError *error;
@property (nonatomic, strong, readonly) iTermScriptFunctionCall *functionCall;
@property (nonatomic, strong, readonly) NSArray<iTermScriptFunctionCall *> *functionCalls;
@property (nonatomic, strong, readonly) NSArray<iTermParsedExpression *> *interpolatedStringParts;
@property (nonatomic, strong, readonly) id<iTermExpressionParserPlaceholder> placeholder;

// This is always equal to the only set property above (or nil if none is set)
@property (nonatomic, strong, readonly) id object;

@property (nonatomic, readonly) BOOL optional;

- (instancetype)initWithString:(NSString *)string;
- (instancetype)initWithFunctionCall:(iTermScriptFunctionCall *)functionCall;
- (instancetype)initWithFunctionCalls:(NSArray<iTermScriptFunctionCall *> *)functionCalls;
- (instancetype)initWithErrorCode:(int)code reason:(NSString *)localizedDescription;
// Object may be NSString, NSNumber, or NSArray. If it is not, an error will be created with the
// given reason.
- (instancetype)initWithObject:(id)object errorReason:(NSString *)errorReason;
- (instancetype)initWithIndirectValue:(iTermIndirectValue *)indirectValue;
- (instancetype)initWithOptionalObject:(id)object;
- (instancetype)initWithSubexpression:(iTermSubexpression *)subexpression;
- (instancetype)initWithError:(NSError *)error;
- (instancetype)initWithInterpolatedStringParts:(NSArray<iTermParsedExpression *> *)parts;
- (instancetype)initWithArrayOfExpressions:(NSArray<iTermParsedExpression *> *)array;
- (instancetype)initWithArrayOfValues:(NSArray *)array;
- (instancetype)initWithPlaceholder:(id<iTermExpressionParserPlaceholder>)placeholder
                           optional:(BOOL)optional;
- (instancetype)initWithReference:(iTermVariableReference *)ref;
- (BOOL)containsAnyFunctionCall;
- (iTermParsedExpression *)optionalized;
- (iTermParsedExpression *)deoptionalized;

// Returns subexpression if this is a Subexpression type.
// Wraps function calls in Subexpression for use in arithmetic.
// Returns nil for other types (caller should handle error).
- (iTermSubexpression * _Nullable)asSubexpression;

@end



NS_ASSUME_NONNULL_END
