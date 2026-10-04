//
//  iTermParsedExpression+Tests.h
//  iTerm2
//
//  Created by George Nachman on 6/12/18.
//

NS_ASSUME_NONNULL_BEGIN

@interface iTermParsedExpression()

@property (nonatomic, readwrite) BOOL optional;

+ (instancetype)parsedString:(NSString *)string;

// Exposed for the parser to construct the null literal expression.
- (instancetype)initWithExpressionType:(iTermParsedExpressionType)expressionType
                                object:(nullable id)object
                              optional:(BOOL)optional;

@end

NS_ASSUME_NONNULL_END
