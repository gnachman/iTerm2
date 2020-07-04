//
//  CPTestWhiteSpaceIgnoringDelegate.m
//  CoreParse
//
//  Created by Tom Davie on 15/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import "CPTestWhiteSpaceIgnoringDelegate.h"

@implementation CPTestWhiteSpaceIgnoringDelegate

- (BOOL)tokeniser:(CPTokeniser *)tokeniser shouldConsumeToken:(CPToken *)token
{
    return YES;
}

- (void)tokeniser:(CPTokeniser *)tokeniser requestsToken:(CPToken *)token pushedOntoStream:(CPTokenStream *)stream
{
    if (![token isWhiteSpaceToken])
    {
        [stream pushToken:token];
    }
}

- (NSUInteger)tokeniser:(CPTokeniser *)tokeniser didNotFindTokenOnInput:(NSString *)input position:(NSUInteger)position error:(NSString **)errorMessage
{
    *errorMessage = @"Found something that wasn't a numeric expression";
    NSRange nextSafeStuff = [input rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"1234567890+*()"] options:NSLiteralSearch range:NSMakeRange(position, [input length] - position)];
    return nextSafeStuff.location;
}

@end
