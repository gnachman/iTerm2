//
//  iTermParsedExpression+Tests.h
//  iTerm2
//
//  Created by George Nachman on 6/12/18.
//

@interface iTermParsedExpression()

@property (nonatomic, readwrite) iTermScriptFunctionCall *functionCall;
@property (nonatomic, readwrite) NSError *error;
@property (nonatomic, readwrite) NSString *string;
@property (nonatomic, readwrite) NSNumber *number;
@property (nonatomic, readwrite) BOOL optional;
@property (nonatomic, strong, readwrite) NSArray *interpolatedStringParts;

+ (instancetype)parsedString:(NSString *)string;

@end

