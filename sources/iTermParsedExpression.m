//
//  iTermParsedExpression.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/1/19.
//

#import "iTermParsedExpression.h"

#import "iTermScriptFunctionCall.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

@implementation iTermParsedExpression

- (NSString *)description {
    NSString *value = nil;
    switch (self.expressionType) {
        case iTermParsedExpressionTypeInterpolatedString:
            value = [[self.interpolatedStringParts mapWithBlock:^id(id anObject) {
                return [anObject description];
            }] componentsJoinedByString:@""];
            break;
        case iTermParsedExpressionTypeFunctionCall:
            value = self.functionCall.description;
            break;
        case iTermParsedExpressionTypeNil:
            value = @"nil";
            break;
        case iTermParsedExpressionTypeError:
            value = self.error.description;
            break;
        case iTermParsedExpressionTypeNumber:
            value = [self.number stringValue];
            break;
        case iTermParsedExpressionTypeString:
            value = self.string;
            break;
        case iTermParsedExpressionTypeArrayOfExpressions:
        case iTermParsedExpressionTypeArrayOfValues:
            value = [[(NSArray *)_object mapWithBlock:^id(id anObject) {
                return [anObject description];
            }] componentsJoinedByString:@" "];
            value = [NSString stringWithFormat:@"[ %@ ]", value];
            break;
    }
    if (self.optional) {
        value = [value stringByAppendingString:@"?"];
    }
    return [NSString stringWithFormat:@"<Expr %@>", value];
}

- (BOOL)isEqual:(id)object {
    iTermParsedExpression *other = [iTermParsedExpression castFrom:object];
    if (!other) {
        return NO;
    }
    return ([NSObject object:self.object isEqualToObject:other.object] &&
            self.expressionType == other.expressionType &&
            self.optional == other.optional);
}

+ (instancetype)parsedString:(NSString *)string {
    return [[self alloc] initWithString:string optional:NO];
}

- (instancetype)initWithString:(NSString *)string optional:(BOOL)optional {
    self = [super init];
    if (self) {
        _expressionType = iTermParsedExpressionTypeString;
        _optional = optional;
        _object = string;
    }
    return self;
}

- (instancetype)initWithFunctionCall:(iTermScriptFunctionCall *)functionCall {
    self = [super init];
    if (self) {
        _expressionType = iTermParsedExpressionTypeFunctionCall;
        _object = functionCall;
    }
    return self;
}

- (instancetype)initWithErrorCode:(int)code reason:(NSString *)localizedDescription {
    self = [super init];
    if (self) {
        _expressionType = iTermParsedExpressionTypeError;
        _object = [NSError errorWithDomain:@"com.iterm2.parser"
                                      code:code
                                  userInfo:@{ NSLocalizedDescriptionKey: localizedDescription ?: @"Unknown error" }];
    }
    return self;
}

// Object may be NSString, NSNumber, or NSArray. If it is not, an error will be created with the
// given reason.
- (instancetype)initWithObject:(id)object errorReason:(NSString *)errorReason {
    if ([object isKindOfClass:[NSString class]]) {
        return [self initWithString:object optional:NO];
    }
    if ([object isKindOfClass:[NSNumber class]]) {
        return [self initWithNumber:object];
    }
    if ([object isKindOfClass:[NSArray class]]) {
        return [self initWithArrayOfValues:object];
    }
    return [self initWithErrorCode:7 reason:errorReason];
}

- (instancetype)initWithOptionalObject:(id)object {
    if (object) {
        self = [self initWithObject:object errorReason:[NSString stringWithFormat:@"Invalid type: %@", [object class]]];
    } else {
        self = [super init];
    }
    if (self) {
        _optional = YES;
    }
    return self;
}

- (instancetype)initWithArrayOfValues:(NSArray *)array {
    self = [super init];
    if (self) {
        _expressionType = iTermParsedExpressionTypeArrayOfValues;
        _object = array;
    }
    return self;
}

- (instancetype)initWithArrayOfExpressions:(NSArray<iTermParsedExpression *> *)array {
    self = [super init];
    if (self) {
        _expressionType = iTermParsedExpressionTypeArrayOfExpressions;
        _object = array;
    }
    return self;
}

- (instancetype)initWithNumber:(NSNumber *)number {
    self = [super init];
    if (self) {
        _expressionType = iTermParsedExpressionTypeNumber;
        _object = number;
    }
    return self;
}

- (instancetype)initWithError:(NSError *)error {
    self = [super init];
    if (self) {
        _expressionType = iTermParsedExpressionTypeError;
        _object = error;
    }
    return self;
}

- (instancetype)initWithInterpolatedStringParts:(NSArray *)parts {
    self = [super init];
    if (self) {
        _expressionType = iTermParsedExpressionTypeInterpolatedString;
        _object = parts;
    }
    return self;
}

- (NSArray *)arrayOfValues {
    assert([_object isKindOfClass:[NSArray class]]);
    return _object;
}

- (NSArray *)arrayOfExpressions {
    assert([_object isKindOfClass:[NSArray class]]);
    return _object;
}

- (NSString *)string {
    assert([_object isKindOfClass:[NSString class]]);
    return _object;
}

- (NSNumber *)number {
    assert([_object isKindOfClass:[NSNumber class]]);
    return _object;
}

- (NSError *)error {
    assert([_object isKindOfClass:[NSError class]]);
    return _object;
}

- (iTermScriptFunctionCall *)functionCall {
    assert([_object isKindOfClass:[iTermScriptFunctionCall class]]);
    return _object;
}

- (NSArray *)interpolatedStringParts {
    assert([_object isKindOfClass:[NSArray class]]);
    return _object;
}

- (BOOL)containsAnyFunctionCall {
    switch (self.expressionType) {
        case iTermParsedExpressionTypeFunctionCall:
            return YES;
        case iTermParsedExpressionTypeNil:
        case iTermParsedExpressionTypeError:
        case iTermParsedExpressionTypeNumber:
        case iTermParsedExpressionTypeString:
        case iTermParsedExpressionTypeArrayOfValues:
            return NO;
        case iTermParsedExpressionTypeArrayOfExpressions:
            return [self.arrayOfExpressions anyWithBlock:^BOOL(iTermParsedExpression *expression) {
                return [expression containsAnyFunctionCall];
            }];
        case iTermParsedExpressionTypeInterpolatedString:
            return [self.interpolatedStringParts anyWithBlock:^BOOL(iTermParsedExpression *expression) {
                return [expression containsAnyFunctionCall];
            }];
    }
    assert(false);
    return YES;
}

@end
