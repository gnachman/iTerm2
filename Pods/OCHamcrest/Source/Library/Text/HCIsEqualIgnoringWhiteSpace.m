//
//  OCHamcrest - HCIsEqualIgnoringWhiteSpace.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCIsEqualIgnoringWhiteSpace.h"

#import "HCDescription.h"
#import "HCRequireNonNilObject.h"


static void removeTrailingSpace(NSMutableString *string)
{
    NSUInteger length = [string length];
    if (length > 0)
    {
        NSUInteger charIndex = length - 1;
        if (isspace([string characterAtIndex:charIndex]))
            [string deleteCharactersInRange:NSMakeRange(charIndex, 1)];
    }
}

static NSMutableString *stripSpace(NSString *string)
{
    NSUInteger length = [string length];
    NSMutableString *result = [NSMutableString stringWithCapacity:length];
    bool lastWasSpace = true;
    for (NSUInteger charIndex = 0; charIndex < length; ++charIndex)
    {
        unichar character = [string characterAtIndex:charIndex];
        if (isspace(character))
        {
            if (!lastWasSpace)
                [result appendString:@" "];
            lastWasSpace = true;
        }
        else
        {
            [result appendFormat:@"%C", character];
            lastWasSpace = false;
        }
    }

    removeTrailingSpace(result);
    return result;
}


#pragma mark -

@implementation HCIsEqualIgnoringWhiteSpace

+ (id)isEqualIgnoringWhiteSpace:(NSString *)aString
{
    return [[self alloc] initWithString:aString];
}

- (id)initWithString:(NSString *)aString
{
    HCRequireNonNilObject(aString);

    self = [super init];
    if (self)
    {
        originalString = [aString copy];
        strippedString = stripSpace(aString);
    }
    return self;
}

- (BOOL)matches:(id)item
{
    if (![item isKindOfClass:[NSString class]])
        return NO;

    return [strippedString isEqualToString:stripSpace(item)];
}

- (void)describeTo:(id<HCDescription>)description
{
    [[description appendDescriptionOf:originalString]
                  appendText:@" ignoring whitespace"];
}

@end


#pragma mark -

id<HCMatcher> HC_equalToIgnoringWhiteSpace(NSString *aString)
{
    return [HCIsEqualIgnoringWhiteSpace isEqualIgnoringWhiteSpace:aString];
}
