//
//  iTermParsedExpression+Tests.h
//  iTerm2
//
//  Created by George Nachman on 6/12/18.
//

@interface iTermParsedExpression()

@property (nonatomic, readwrite) BOOL optional;

+ (instancetype)parsedString:(NSString *)string;

@end

