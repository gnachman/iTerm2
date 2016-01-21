//
//  OCHamcrest - HCIsCloseTo.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCIsCloseTo.h"

#import "HCDescription.h"


@implementation HCIsCloseTo

+ (id)isCloseTo:(double)aValue within:(double)aDelta
{
    return [[self alloc] initWithValue:aValue delta:aDelta];
}

- (id)initWithValue:(double)aValue delta:(double)aDelta
{
    self = [super init];
    if (self)
    {
        value = aValue;
        delta = aDelta;
    }
    return self;
}

- (BOOL)matches:(id)item
{
    if (![item isKindOfClass:[NSNumber class]])
        return NO;

    return fabs([item doubleValue] - value) <= delta;
}

- (void)describeMismatchOf:(id)item to:(id<HCDescription>)mismatchDescription
{
    if (![item isKindOfClass:[NSNumber class]])
        [super describeMismatchOf:item to:mismatchDescription];
    else
    {
        double actualDelta = fabs([item doubleValue] - value);
        [[[mismatchDescription appendDescriptionOf:item]
                               appendText:@" differed by "]
                               appendDescriptionOf:@(actualDelta)];
    }
}

- (void)describeTo:(id<HCDescription>)description
{
    [[[[description appendText:@"a numeric value within "]
                    appendDescriptionOf:@(delta)]
                    appendText:@" of "]
                    appendDescriptionOf:@(value)];
}

@end


#pragma mark -

id<HCMatcher> HC_closeTo(double value, double delta)
{
    return [HCIsCloseTo isCloseTo:value within:delta];
}
