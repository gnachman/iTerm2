//
//  CPRegexpRecogniser.m
//  CoreParse
//
//  Created by Francis Chong on 1/22/14.
//  Copyright (c) 2014 Ignition Soft. All rights reserved.
//

#import "CPRegexpRecogniser.h"
#import "CPToken.h"
#import "CPKeywordToken.h"

@interface CPRegexpRecogniser()
@property (nonatomic, copy) CPRegexpKeywordRecogniserMatchHandler matchHandler;
@end

@implementation CPRegexpRecogniser

@synthesize regexp;
@synthesize matchHandler;

- (id)initWithRegexp:(NSRegularExpression *)initRegexp matchHandler:(CPRegexpKeywordRecogniserMatchHandler)initMatchHandler
{
    self = [super init];
    if (self) {
        [self setRegexp:initRegexp];
        [self setMatchHandler:initMatchHandler];
    }
    return self;
}

+ (id)recogniserForRegexp:(NSRegularExpression *)regexp matchHandler:(CPRegexpKeywordRecogniserMatchHandler)initMatchHandler
{
    return [[[self alloc] initWithRegexp:regexp matchHandler:initMatchHandler] autorelease];
}

- (void)dealloc
{
    [matchHandler release];
    [regexp release];
    [super dealloc];
}

#pragma mark - NSCoder

#define CPRegexpRecogniserRegexpKey @"R.r"

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    
    if (nil != self)
    {
        [self setRegexp:[aDecoder decodeObjectForKey:CPRegexpRecogniserRegexpKey]];
    }
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:[self regexp] forKey:CPRegexpRecogniserRegexpKey];
}

#pragma mark - CPRecognizer

- (CPToken *)recogniseTokenInString:(NSString *)tokenString currentTokenPosition:(NSUInteger *)tokenPosition
{
    long inputLength = [tokenString length];
    NSRange searchRange = NSMakeRange(*tokenPosition, inputLength - *tokenPosition);
    NSTextCheckingResult* result = [[self regexp] firstMatchInString:tokenString options:NSMatchingAnchored range:searchRange];
    if (nil != result && nil != matchHandler && result.range.location == *tokenPosition && result.range.length > 0)
    {
        CPToken* token = matchHandler(tokenString, result);
        if (token)
        {
             *tokenPosition = result.range.location + result.range.length;
            return token;
        }
    }
    return nil;
}

@end
