//
//  CPQuotedRecogniser.m
//  CoreParse
//
//  Created by Tom Davie on 13/02/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import "CPQuotedRecogniser.h"

#import "CPQuotedToken.h"

@implementation CPQuotedRecogniser

@synthesize startQuote;
@synthesize endQuote;
@synthesize escapeSequence;
@synthesize escapeReplacer;
@synthesize maximumLength;
@synthesize name;

+ (id)quotedRecogniserWithStartQuote:(NSString *)startQuote endQuote:(NSString *)endQuote name:(NSString *)name
{
    return [CPQuotedRecogniser quotedRecogniserWithStartQuote:startQuote endQuote:endQuote escapeSequence:nil name:name];
}

+ (id)quotedRecogniserWithStartQuote:(NSString *)startQuote endQuote:(NSString *)endQuote escapeSequence:(NSString *)escapeSequence name:(NSString *)name
{
    return [CPQuotedRecogniser quotedRecogniserWithStartQuote:startQuote endQuote:endQuote escapeSequence:escapeSequence maximumLength:NSNotFound name:name];
}

+ (id)quotedRecogniserWithStartQuote:(NSString *)startQuote endQuote:(NSString *)endQuote escapeSequence:(NSString *)escapeSequence maximumLength:(NSUInteger)maximumLength name:(NSString *)name
{
    return [[[CPQuotedRecogniser alloc] initWithStartQuote:startQuote endQuote:endQuote escapeSequence:escapeSequence maximumLength:maximumLength name:name] autorelease];
}

- (id)initWithStartQuote:(NSString *)initStartQuote endQuote:(NSString *)initEndQuote escapeSequence:(NSString *)initEscapeSequence maximumLength:(NSUInteger)initMaximumLength name:(NSString *)initName
{
    self = [super init];
    
    if (nil != self)
    {
        [self setStartQuote:initStartQuote];
        [self setEndQuote:initEndQuote];
        [self setEscapeSequence:initEscapeSequence];
        [self setMaximumLength:initMaximumLength];
        [self setName:initName];
    }
    
    return self;
}

#define CPQuotedRecogniserStartQuoteKey     @"Q.s"
#define CPQuotedRecogniserEndQuoteKey       @"Q.e"
#define CPQuotedRecogniserEscapeSequenceKey @"Q.es"
#define CPQuotedRecogniserMaximumLengthKey  @"Q.m"
#define CPQuotedRecogniserNameKey           @"Q.n"

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    
    if (nil != self)
    {
        [self setStartQuote:[aDecoder decodeObjectForKey:CPQuotedRecogniserStartQuoteKey]];
        [self setEndQuote:[aDecoder decodeObjectForKey:CPQuotedRecogniserEndQuoteKey]];
        [self setEscapeSequence:[aDecoder decodeObjectForKey:CPQuotedRecogniserEscapeSequenceKey]];
        @try
        {
            [self setMaximumLength:[aDecoder decodeIntegerForKey:CPQuotedRecogniserMaximumLengthKey]];
        }
        @catch (NSException *exception)
        {
            NSLog(@"Warning, value for maximum length too long for this platform, allowing infinite lengths");
            [self setMaximumLength:NSNotFound];
        }
        [self setName:[aDecoder decodeObjectForKey:CPQuotedRecogniserNameKey]];
    }
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    if (nil != [self escapeReplacer])
    {
        NSLog(@"Warning: encoding CPQuoteRecogniser with an escapeReplacer set.  This will not be recreated when decoded.");
    }
    [aCoder encodeObject:[self startQuote]     forKey:CPQuotedRecogniserStartQuoteKey];
    [aCoder encodeObject:[self endQuote]       forKey:CPQuotedRecogniserEndQuoteKey];
    [aCoder encodeObject:[self escapeSequence] forKey:CPQuotedRecogniserEscapeSequenceKey];
    [aCoder encodeInteger:[self maximumLength] forKey:CPQuotedRecogniserMaximumLengthKey];
    [aCoder encodeObject:[self name]           forKey:CPQuotedRecogniserNameKey];
}

- (void)dealloc
{
    [startQuote release];
    [endQuote release];
    [escapeSequence release];
    [escapeReplacer release];
    [name release];
    
    [super dealloc];
}

- (CPToken *)recogniseTokenInString:(NSString *)tokenString currentTokenPosition:(NSUInteger *)tokenPosition
{
    NSString *(^er)(NSString *tokenStream, NSUInteger *quotePosition) = [self escapeReplacer];
    NSUInteger startQuoteLength = [startQuote length];
    NSUInteger endQuoteLength = [endQuote length];

    long inputLength = [tokenString length];
    CFRange searchRange = CFRangeMake(*tokenPosition, MIN(inputLength - *tokenPosition,startQuoteLength + endQuoteLength + maximumLength));
    CFRange range;
    BOOL matched = CFStringFindWithOptions((CFStringRef)tokenString, (CFStringRef)startQuote, searchRange, kCFCompareAnchored, &range);
    
    CFMutableStringRef outputString = CFStringCreateMutable(kCFAllocatorDefault, 0);
    
    if (matched)
    {
        searchRange.location = searchRange.location + range.length;
        searchRange.length   = searchRange.length   - range.length;
        
        CFRange endRange;
        CFRange escapeRange;
        BOOL matchedEndSequence = CFStringFindWithOptions((CFStringRef)tokenString, (CFStringRef)endQuote, searchRange, 0L, &endRange);
        BOOL matchedEscapeSequence = nil == escapeSequence ? NO : CFStringFindWithOptions((CFStringRef)tokenString, (CFStringRef)escapeSequence, searchRange, 0L, &escapeRange);
        
        while (matchedEndSequence && searchRange.location < inputLength)
        {
            if (!matchedEscapeSequence || endRange.location < escapeRange.location)
            {
                *tokenPosition = endRange.location + endRange.length;
                CFStringRef substr = CFStringCreateWithSubstring(kCFAllocatorDefault, (CFStringRef)tokenString, CFRangeMake(searchRange.location, endRange.location - searchRange.location));
                CFStringAppend(outputString, substr);
                CFRelease(substr);
                CPQuotedToken *t = [CPQuotedToken content:(NSString *)outputString quotedWith:startQuote name:[self name]];
                CFRelease(outputString);
                return t;
            }
            else
            {
                NSUInteger quotedPosition = escapeRange.location + escapeRange.length;
                CFStringRef substr = CFStringCreateWithSubstring(kCFAllocatorDefault, (CFStringRef)tokenString, CFRangeMake(searchRange.location, escapeRange.location - searchRange.location));
                CFStringAppend(outputString, substr);
                CFRelease(substr);
                BOOL appended = NO;
                if (nil != er)
                {
                    NSString *s = er(tokenString, &quotedPosition);
                    if (nil != s)
                    {
                        appended = YES;
                        CFStringAppend(outputString, (CFStringRef)s);
                    }
                }
                if (!appended)
                {
                    substr = CFStringCreateWithSubstring(kCFAllocatorDefault, (CFStringRef)tokenString, CFRangeMake(escapeRange.location + escapeRange.length, 1));
                    CFStringAppend(outputString, substr);
                    CFRelease(substr);
                    quotedPosition += 1;
                }
                searchRange.length   = searchRange.location + searchRange.length - quotedPosition;
                searchRange.location = quotedPosition;
                
                if (endRange.location < searchRange.location)
                {
                    matchedEndSequence = CFStringFindWithOptions((CFStringRef)tokenString, (CFStringRef)endQuote, searchRange, 0L, &endRange);
                }
                if (escapeRange.location < searchRange.location)
                {
                    matchedEscapeSequence = CFStringFindWithOptions((CFStringRef)tokenString, (CFStringRef)escapeSequence, searchRange, 0L, &escapeRange);
                }
            }
        }
    }
    
    CFRelease(outputString);
    return nil;
}

@end
