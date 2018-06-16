//
//  iTermFunctionCallParser.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import <Foundation/Foundation.h>
#import <CoreParse/CoreParse.h>

@class iTermScriptFunctionCall;

@interface iTermParsedExpression : NSObject
// Only one property will be set.
@property (nonatomic, strong, readonly) iTermScriptFunctionCall *functionCall;
@property (nonatomic, strong, readonly) NSString *string;
@property (nonatomic, strong, readonly) NSNumber *number;
@property (nonatomic, strong, readonly) NSError *error;
@property (nonatomic, readonly) BOOL optional;
@property (nonatomic, strong, readonly) NSArray *interpolatedStringParts;
@end

@interface iTermFunctionCallParser : NSObject <CPParserDelegate, CPTokeniserDelegate>

+ (CPTokeniser *)newTokenizer;
+ (id<CPTokenRecogniser>)stringRecognizerWithClass:(Class)theClass;
+ (void)setEscapeReplacerInStringRecognizer:(id)stringRecogniser;

// Use this to get an instance. Only on the main thread.
+ (instancetype)callParser;
+ (instancetype)expressionParser;

- (instancetype)init NS_UNAVAILABLE;
// Start gives root grammar rule name.
- (id)initWithStart:(NSString *)start NS_DESIGNATED_INITIALIZER;

- (iTermParsedExpression *)parse:(NSString *)invocation source:(id (^)(NSString *))source;

@end
