//
//  iTermFunctionCallParser+Private.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/1/19.
//

#import "iTermFunctionCallParser.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermFunctionArgument : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) iTermParsedExpression *expression;
@end

@interface iTermFunctionCallParser (Private)

+ (CPTokeniser *)newTokenizer;
+ (id<CPTokenRecogniser>)stringRecognizerWithClass:(Class)theClass;
+ (void)setEscapeReplacerInStringRecognizer:(id)stringRecogniser;
+ (NSString *)signatureForTopLevelInvocation:(NSString *)invocation;

@end

NS_ASSUME_NONNULL_END
