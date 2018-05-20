//
//  iTermFunctionCallParser.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import <Foundation/Foundation.h>
#import <CoreParse/CoreParse.h>

@class iTermScriptFunctionCall;

@interface iTermFunctionCallParser : NSObject <CPParserDelegate, CPTokeniserDelegate>

+ (CPTokeniser *)newTokenizer;
+ (id<CPTokenRecogniser>)stringRecognizerWithClass:(Class)theClass;
- (iTermScriptFunctionCall *)parse:(NSString *)invocation source:(id (^)(NSString *))source;

@end
