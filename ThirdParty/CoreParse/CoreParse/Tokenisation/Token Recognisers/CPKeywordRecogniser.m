//
//  CPKeywordRecogniser.m
//  CoreParse
//
//  Created by Tom Davie on 12/02/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import "CPKeywordRecogniser.h"

@implementation CPKeywordRecogniser

@synthesize keyword;
@synthesize invalidFollowingCharacters;

+ (id)recogniserForKeyword:(NSString *)keyword
{
    return [[[self alloc] initWithKeyword:keyword] autorelease];
}

- (id)initWithKeyword:(NSString *)initKeyword
{
    return [self initWithKeyword:initKeyword invalidFollowingCharacters:nil];
}

+ (id)recogniserForKeyword:(NSString *)keyword invalidFollowingCharacters:(NSCharacterSet *)invalidFollowingCharacters
{
    return [[[self alloc] initWithKeyword:keyword invalidFollowingCharacters:invalidFollowingCharacters] autorelease];
}

- (id)initWithKeyword:(NSString *)initKeyword invalidFollowingCharacters:(NSCharacterSet *)initInvalidFollowingCharacters
{
    self = [super init];
    
    if (nil != self)
    {
        [self setKeyword:initKeyword];
        [self setInvalidFollowingCharacters:initInvalidFollowingCharacters];
    }
    
    return self;
}

- (id)init
{
    return [self initWithKeyword:@" "];
}

#define CPKeywordRecogniserKeywordKey @"K.k"
#define CPKeywordRecogniserInvalidFollowingCharactersKey @"K.f"

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    
    if (nil != self)
    {
        [self setKeyword:[aDecoder decodeObjectForKey:CPKeywordRecogniserKeywordKey]];
        [self setInvalidFollowingCharacters:[aDecoder decodeObjectForKey:CPKeywordRecogniserInvalidFollowingCharactersKey]];
    }
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:[self keyword] forKey:CPKeywordRecogniserKeywordKey];
    [aCoder encodeObject:[self invalidFollowingCharacters] forKey:CPKeywordRecogniserInvalidFollowingCharactersKey];
}

- (void)dealloc
{
   [keyword release];
   [invalidFollowingCharacters release];
    
    [super dealloc];
}

- (CPToken *)recogniseTokenInString:(NSString *)tokenString currentTokenPosition:(NSUInteger *)tokenPosition
{
    NSUInteger kwLength = [keyword length];
    NSUInteger remainingChars = [tokenString length] - *tokenPosition;
    if (remainingChars >= kwLength)
    {
        if (CFStringFindWithOptions((CFStringRef)tokenString, (CFStringRef)keyword, CFRangeMake(*tokenPosition, kwLength), kCFCompareAnchored, NULL))
        {
            if (remainingChars == kwLength ||
                nil == invalidFollowingCharacters ||
                !CFStringFindCharacterFromSet((CFStringRef)tokenString, (CFCharacterSetRef)invalidFollowingCharacters, CFRangeMake(*tokenPosition + kwLength, 1), kCFCompareAnchored, NULL))
            {
                *tokenPosition = *tokenPosition + kwLength;
                return [CPKeywordToken tokenWithKeyword:keyword];
            }
        }
    }
    
    return nil;
}

@end
