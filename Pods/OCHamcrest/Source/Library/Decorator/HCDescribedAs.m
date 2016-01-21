//
//  OCHamcrest - HCDescribedAs.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCDescribedAs.h"

#import "HCDescription.h"


typedef struct
{
    int first;
    __unsafe_unretained NSString *second;
} HCPairIntNSString;


/**
    Splits string into decimal number (-1 if not found) and remaining string.
 */
static HCPairIntNSString separate(NSString *component)
{
    int index = 0;
    bool gotIndex = false;

    NSUInteger length = [component length];
    NSUInteger charIndex;
    for (charIndex = 0; charIndex < length; ++charIndex)
    {
        unichar character = [component characterAtIndex:charIndex];
        if (!isdigit(character))
            break;
        index = index * 10 + character - '0';
        gotIndex = true;
    }

    if (!gotIndex)
        return (HCPairIntNSString){ -1, component };
    else
        return (HCPairIntNSString){ index, [component substringFromIndex:charIndex] };
}


#pragma mark -

@implementation HCDescribedAs

+ (id)describedAs:(NSString *)description
       forMatcher:(id<HCMatcher>)aMatcher
       overValues:(NSArray *)templateValues
{
    return [[self alloc] initWithDescription:description
                                  forMatcher:aMatcher
                                  overValues:templateValues];
}

- (id)initWithDescription:(NSString *)description
                forMatcher:(id<HCMatcher>)aMatcher
                overValues:(NSArray *)templateValues
{
    self = [super init];
    if (self)
    {
        descriptionTemplate = [description copy];
        matcher = aMatcher;
        values = templateValues;
    }
    return self;
}

- (BOOL)matches:(id)item
{
    return [matcher matches:item];
}

- (void)describeMismatchOf:(id)item to:(id<HCDescription>)mismatchDescription
{
    [matcher describeMismatchOf:item to:mismatchDescription];
}

- (void)describeTo:(id<HCDescription>)description
{
    NSArray *components = [descriptionTemplate componentsSeparatedByString:@"%"];
    bool firstTime = true;
    for (NSString *oneComponent in components)
    {
        if (firstTime)
        {
            firstTime = false;
            [description appendText:oneComponent];
        }
        else
        {
            HCPairIntNSString parseIndex = separate(oneComponent);
            if (parseIndex.first < 0)
                [[description appendText:@"%"] appendText:oneComponent];
            else
            {
                [description appendDescriptionOf:values[(NSUInteger)parseIndex.first]];
                [description appendText:parseIndex.second];
            }
        }
    }
}

@end


#pragma mark -

id<HCMatcher> HC_describedAs(NSString *description, id<HCMatcher> matcher, ...)
{
    NSMutableArray *valueList = [NSMutableArray array];

    va_list args;
    va_start(args, matcher);
    id value = va_arg(args, id);
    while (value != nil)
    {
        [valueList addObject:value];
        value = va_arg(args, id);
    }
    va_end(args);

    return [HCDescribedAs describedAs:description forMatcher:matcher overValues:valueList];
}
