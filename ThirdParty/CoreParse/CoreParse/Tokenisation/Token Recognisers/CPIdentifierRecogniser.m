//
//  CPIdentifierTokeniser.m
//  CoreParse
//
//  Created by Tom Davie on 12/02/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import "CPIdentifierRecogniser.h"

#import "CPIdentifierToken.h"

@implementation CPIdentifierRecogniser

@synthesize initialCharacters;
@synthesize identifierCharacters;

+ (id)identifierRecogniser
{
    return [[[CPIdentifierRecogniser alloc] initWithInitialCharacters:nil identifierCharacters:nil] autorelease];
}

+ (id)identifierRecogniserWithInitialCharacters:(NSCharacterSet *)initialCharacters identifierCharacters:(NSCharacterSet *)identifierCharacters
{
    return [[[CPIdentifierRecogniser alloc] initWithInitialCharacters:initialCharacters identifierCharacters:identifierCharacters] autorelease];
}

- (id)initWithInitialCharacters:(NSCharacterSet *)initInitialCharacters identifierCharacters:(NSCharacterSet *)initIdentifierCharacters
{
    self = [super init];
    
    if (nil != self)
    {
        [self setInitialCharacters:initInitialCharacters];
        [self setIdentifierCharacters:initIdentifierCharacters];
    }
    
    return self;
}

#define CPIdentifierRecogniserInitialCharactersKey @"I.i"
#define CPIdentifierRecogniserIdentifierCharactersKey @"I.c"

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    
    if (nil != self)
    {
        [self setInitialCharacters:[aDecoder decodeObjectForKey:CPIdentifierRecogniserInitialCharactersKey]];
        [self setIdentifierCharacters:[aDecoder decodeObjectForKey:CPIdentifierRecogniserIdentifierCharactersKey]];
    }
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:[self initialCharacters] forKey:CPIdentifierRecogniserInitialCharactersKey];
    [aCoder encodeObject:[self identifierCharacters] forKey:CPIdentifierRecogniserIdentifierCharactersKey];
}

- (void)dealloc
{
    [initialCharacters release];
    [identifierCharacters release];
    
    [super dealloc];
}

- (CPToken *)recogniseTokenInString:(NSString *)tokenString currentTokenPosition:(NSUInteger *)tokenPosition
{
    NSCharacterSet *identifierStartCharacters = nil == [self initialCharacters] ? [NSCharacterSet characterSetWithCharactersInString:
                                                                                   @"abcdefghijklmnopqrstuvwxyz"
                                                                                   @"ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                                                                                   @"_"] : [self initialCharacters];
    NSCharacterSet *idCharacters = nil == [self identifierCharacters] ? [NSCharacterSet characterSetWithCharactersInString:
                                                                         @"abcdefghijklmnopqrstuvwxyz"
                                                                         @"ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                                                                         @"_-1234567890"] : [self identifierCharacters];
    
    unichar firstChar = [tokenString characterAtIndex:*tokenPosition];
    if ([identifierStartCharacters characterIsMember:firstChar])
    {
        NSString *identifierString;
        NSScanner *scanner = [NSScanner scannerWithString:tokenString];
        [scanner setScanLocation:*tokenPosition + 1];
        [scanner setCharactersToBeSkipped:nil];
        BOOL success = [scanner scanCharactersFromSet:idCharacters intoString:&identifierString];
        if (success)
        {
            identifierString = [[[[NSString alloc] initWithCharacters:&firstChar length:1] autorelease] stringByAppendingString:identifierString];
            *tokenPosition = [scanner scanLocation];
        }
        else
        {
            identifierString = [[[NSString alloc] initWithCharacters:&firstChar length:1] autorelease];
            *tokenPosition += 1;
        }
        return [CPIdentifierToken tokenWithIdentifier:identifierString];
    }
    
    return nil;
}

@end
