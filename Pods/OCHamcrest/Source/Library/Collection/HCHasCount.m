//
//  OCHamcrest - HCHasCount.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCHasCount.h"

#import "HCDescription.h"
#import "HCIsEqualToNumber.h"


@implementation HCHasCount

+ (id)hasCount:(id<HCMatcher>)matcher
{
    return [[self alloc] initWithCount:matcher];
}

- (id)initWithCount:(id<HCMatcher>)matcher
{
    self = [super init];
    if (self)
        countMatcher = matcher;
    return self;
}

- (BOOL)matches:(id)item
{
    if (![item respondsToSelector:@selector(count)])
        return NO;

    NSNumber *count = @([item count]);
    return [countMatcher matches:count];
}

- (void)describeMismatchOf:(id)item to:(id<HCDescription>)mismatchDescription
{
    [mismatchDescription appendText:@"was "];
    if ([item respondsToSelector:@selector(count)])
    {
        [[[mismatchDescription appendText:@"count of "]
                               appendDescriptionOf:@([item count])]
                               appendText:@" with "];
    }
    [mismatchDescription appendDescriptionOf:item];
}

- (void)describeTo:(id<HCDescription>)description
{
    [[description appendText:@"a collection with count of "] appendDescriptionOf:countMatcher];
}

@end


#pragma mark -

id<HCMatcher> HC_hasCount(id<HCMatcher> matcher)
{
    return [HCHasCount hasCount:matcher];
}

id<HCMatcher> HC_hasCountOf(NSUInteger value)
{
    return HC_hasCount(HC_equalToUnsignedInteger(value));
}
