//
//  iTermQuotedRecognizer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/12/18.
//

#import "iTermQuotedRecognizer.h"

@implementation iTermQuotedRecognizer

+ (id)quotedRecogniserWithStartQuote:(NSString *)startQuote endQuote:(NSString *)endQuote name:(NSString *)name
{
    return [self quotedRecogniserWithStartQuote:startQuote endQuote:endQuote escapeSequence:nil name:name];
}

+ (id)quotedRecogniserWithStartQuote:(NSString *)startQuote endQuote:(NSString *)endQuote escapeSequence:(NSString *)escapeSequence name:(NSString *)name
{
    return [self quotedRecogniserWithStartQuote:startQuote endQuote:endQuote escapeSequence:escapeSequence maximumLength:NSNotFound name:name];
}

+ (id)quotedRecogniserWithStartQuote:(NSString *)startQuote endQuote:(NSString *)endQuote escapeSequence:(NSString *)escapeSequence maximumLength:(NSUInteger)maximumLength name:(NSString *)name
{
    return [[self alloc] initWithStartQuote:startQuote endQuote:endQuote escapeSequence:escapeSequence maximumLength:maximumLength name:name];
}
- (CPToken *)recogniseTokenInString:(NSString *)tokenString currentTokenPosition:(NSUInteger *)tokenPosition
{
    NSString *(^er)(NSString *tokenStream, NSUInteger *quotePosition) = [self escapeReplacer];
    NSUInteger startQuoteLength = [self.startQuote length];
    NSUInteger endQuoteLength = [self.endQuote length];

    long inputLength = [tokenString length];
    CFRange searchRange = CFRangeMake(*tokenPosition, MIN(inputLength - *tokenPosition,
                                                          startQuoteLength + endQuoteLength + self.maximumLength));
    CFRange range;
    BOOL matched;
    if (self.startQuote.length == 0) {
        matched = searchRange.length > 0;
        range.location = 0;
        range.length = 0;
    } else {
        matched = CFStringFindWithOptions((CFStringRef)tokenString,
                                          (CFStringRef)self.startQuote,
                                          searchRange,
                                          kCFCompareAnchored,
                                          &range);
    }

    CFMutableStringRef outputString = CFStringCreateMutable(kCFAllocatorDefault, 0);

    if (matched)
    {
        searchRange.location = searchRange.location + range.length;
        searchRange.length   = searchRange.length   - range.length;

        CFRange endRange;
        CFRange escapeRange;
        BOOL matchedEndSequence = CFStringFindWithOptions((CFStringRef)tokenString,
                                                          (CFStringRef)self.endQuote,
                                                          searchRange,
                                                          0L,
                                                          &endRange);
        BOOL matchedEscapeSequence =
            (nil == self.escapeSequence) ? NO : CFStringFindWithOptions((CFStringRef)tokenString,
                                                                        (CFStringRef)self.escapeSequence,
                                                                        searchRange,
                                                                        0L,
                                                                        &escapeRange);

        while (matchedEndSequence && searchRange.location < inputLength)
        {
            if (!matchedEscapeSequence || endRange.location <= escapeRange.location)
            {
                *tokenPosition = endRange.location + endRange.length;
                CFStringRef substr = CFStringCreateWithSubstring(kCFAllocatorDefault, (CFStringRef)tokenString, CFRangeMake(searchRange.location, endRange.location - searchRange.location));
                CFStringAppend(outputString, substr);
                CFRelease(substr);
                CPQuotedToken *t = [CPQuotedToken content:(__bridge NSString *)outputString quotedWith:self.startQuote name:[self name]];
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
                    matchedEndSequence = CFStringFindWithOptions((CFStringRef)tokenString, (CFStringRef)self.endQuote, searchRange, 0L, &endRange);
                }
                if (escapeRange.location < searchRange.location)
                {
                    matchedEscapeSequence = CFStringFindWithOptions((CFStringRef)tokenString, (CFStringRef)self.escapeSequence, searchRange, 0L, &escapeRange);
                }
            }
        }
    }

    CFRelease(outputString);
    return nil;
}

@end
