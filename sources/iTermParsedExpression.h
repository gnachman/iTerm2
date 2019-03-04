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
    iTermParsedExpressionTypeInterpolatedString
};

@interface iTermParsedExpression : NSObject
// Only one property will be set.
@property (nonatomic, readonly) iTermParsedExpressionType expressionType;

@property (nonatomic, strong, readonly) NSArray<iTermParsedExpression *> *arrayOfExpressions;
@property (nonatomic, strong, readonly) NSArray *arrayOfValues;
@property (nonatomic, strong, readonly) NSString *string;
@property (nonatomic, strong, readonly) NSNumber *number;
@property (nonatomic, strong, readonly) NSError *error;
@property (nonatomic, strong, readonly) iTermScriptFunctionCall *functionCall;
@property (nonatomic, strong, readonly) NSArray<iTermParsedExpression *> *interpolatedStringParts;

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
- (instancetype)initWithInterpolatedStringParts:(NSArray<iTermParsedExpression *> *)parts;
- (instancetype)initWithArrayOfExpressions:(NSArray<iTermParsedExpression *> *)array;
- (instancetype)initWithArrayOfValues:(NSArray *)array;

- (BOOL)containsAnyFunctionCall;

@end



NS_ASSUME_NONNULL_END
