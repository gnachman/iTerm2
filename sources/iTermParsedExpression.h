//
//  iTermParsedExpression.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/1/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermScriptFunctionCall;
@class iTermVariableScope;

typedef NS_ENUM(NSUInteger, iTermParsedExpressionType) {
    iTermParsedExpressionTypeNil,
    iTermParsedExpressionTypeArrayOfExpressions,
    iTermParsedExpressionTypeArrayOfValues,
    iTermParsedExpressionTypeString,  // This only occurs inside interpolated string parts arrays.
    iTermParsedExpressionTypeNumber,
    iTermParsedExpressionTypeFunctionCall,
    iTermParsedExpressionTypeError,
    iTermParsedExpressionTypeInterpolatedString,
    // These two are only produced if you request an AST from the expression parser
    iTermParsedExpressionTypeVariableReference,
    iTermParsedExpressionTypeArrayLookup,
    iTermParsedExpressionTypeFunctionCalls,
    iTermParsedExpressionTypeBoolean

    // Note: When adding new types, also update the Python function iterm2_encode().
};

@protocol iTermExpressionParserPlaceholder<NSObject>
@property (nonatomic, readonly, copy) NSString *path;
- (iTermParsedExpressionType)expressionType;
@end

@interface iTermExpressionParserArrayDereferencePlaceholder : NSObject<iTermExpressionParserPlaceholder>
@property (nonatomic, readonly) NSInteger index;
- (instancetype)initWithPath:(NSString *)path index:(NSInteger)index;
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
@property (nonatomic, strong, readonly) NSNumber *number;
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
- (instancetype)initWithOptionalObject:(id)object;
- (instancetype)initWithNumber:(NSNumber *)number;
- (instancetype)initWithBoolean:(BOOL)value;
- (instancetype)initWithError:(NSError *)error;
- (instancetype)initWithInterpolatedStringParts:(NSArray<iTermParsedExpression *> *)parts;
- (instancetype)initWithArrayOfExpressions:(NSArray<iTermParsedExpression *> *)array;
- (instancetype)initWithArrayOfValues:(NSArray *)array;
- (instancetype)initWithPlaceholder:(id<iTermExpressionParserPlaceholder>)placeholder
                           optional:(BOOL)optional;
- (BOOL)containsAnyFunctionCall;

@end



NS_ASSUME_NONNULL_END
