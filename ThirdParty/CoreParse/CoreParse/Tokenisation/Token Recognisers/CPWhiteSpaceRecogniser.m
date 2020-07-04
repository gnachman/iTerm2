//
//  CPWhiteSpaceRecogniser.m
//  CoreParse
//
//  Created by Tom Davie on 12/02/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import "CPWhiteSpaceRecogniser.h"

#import "CPWhiteSpaceToken.h"

@implementation CPWhiteSpaceRecogniser

- (id)initWithCoder:(NSCoder *)aDecoder
{
    return [super init];
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
}

+ (id)whiteSpaceRecogniser
{
    return [[[CPWhiteSpaceRecogniser alloc] init] autorelease];
}

- (CPToken *)recogniseTokenInString:(NSString *)tokenString currentTokenPosition:(NSUInteger *)tokenPosition
{
    NSScanner *scanner = [NSScanner scannerWithString:tokenString];
    [scanner setCharactersToBeSkipped:nil];
    [scanner setScanLocation:*tokenPosition];
    NSString *scannedString;
    BOOL success = [scanner scanCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:&scannedString];
    if (success)
    {
        *tokenPosition = [scanner scanLocation];
        return [CPWhiteSpaceToken whiteSpace:scannedString];
    }
    
    return nil;
}

@end
