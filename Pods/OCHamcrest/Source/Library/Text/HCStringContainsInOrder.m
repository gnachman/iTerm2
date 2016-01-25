//
//  OCHamcrest - HCStringContainsInOrder.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCStringContainsInOrder.h"

#import "HCDescription.h"


@implementation HCStringContainsInOrder

+ (id)containsInOrder:(NSArray *)substringList
{
    return [[self alloc] initWithSubstrings:substringList];
}

- (id)initWithSubstrings:(NSArray *)substringList
{
    self = [super init];
    if (self)
    {
        for (id substring in substringList)
        {
            if (![substring isKindOfClass:[NSString class]])
            {
                @throw [NSException exceptionWithName:@"NotAString"
                                               reason:@"Arguments must be strings"
                                             userInfo:nil];
            }
        }

        substrings = substringList;
    }
    return self;
}

- (BOOL)matches:(id)item
{
    if (![item isKindOfClass:[NSString class]])
        return NO;

    NSRange searchRange = NSMakeRange(0, [item length]);
    for (NSString *substring in substrings)
    {
        NSRange substringRange = [item rangeOfString:substring options:0 range:searchRange];
        if (substringRange.location == NSNotFound)
            return NO;
        searchRange.location = substringRange.location + substringRange.length;
        searchRange.length = [item length] - searchRange.location;
    }
    return YES;
}

- (void)describeTo:(id<HCDescription>)description
{
    [description appendList:substrings start:@"a string containing " separator:@", " end:@" in order"];
}

@end


#pragma mark -

id<HCMatcher> HC_stringContainsInOrder(NSString *substring, ...)
{
    va_list args;
    va_start(args, substring);
    NSMutableArray *substringList = [NSMutableArray arrayWithObject:substring];

    substring = va_arg(args, NSString *);
    while (substring != nil)
    {
        [substringList addObject:substring];
        substring = va_arg(args, NSString *);
    }

    va_end(args);

    return [HCStringContainsInOrder containsInOrder:substringList];
}
