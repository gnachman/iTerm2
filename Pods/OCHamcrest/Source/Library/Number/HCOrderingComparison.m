//
//  OCHamcrest - HCOrderingComparison.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCOrderingComparison.h"

#import "HCDescription.h"


@implementation HCOrderingComparison

+ (id)compare:(id)expectedValue
   minCompare:(NSComparisonResult)min
   maxCompare:(NSComparisonResult)max
   comparisonDescription:(NSString *)description
{
    return [[self alloc] initComparing:expectedValue
                             minCompare:min
                             maxCompare:max
                  comparisonDescription:description];
}

- (id)initComparing:(id)expectedValue
         minCompare:(NSComparisonResult)min
         maxCompare:(NSComparisonResult)max
         comparisonDescription:(NSString *)description
{
    if (![expectedValue respondsToSelector:@selector(compare:)])
    {
        @throw [NSException exceptionWithName: @"UncomparableObject"
                                       reason: @"Object must respond to compare:"
                                     userInfo: nil];
    }

    self = [super init];
    if (self)
    {
        expected = expectedValue;
        minCompare = min;
        maxCompare = max;
        comparisonDescription = [description copy];
    }
    return self;
}

- (BOOL)matches:(id)item
{
    if (item == nil)
        return NO;

    NSComparisonResult compare = [expected compare:item];
    return minCompare <= compare && compare <= maxCompare;
}

- (void)describeTo:(id<HCDescription>)description
{
    [[[[description appendText:@"a value "]
                    appendText:comparisonDescription]
                    appendText:@" "]
                    appendDescriptionOf:expected];
}

@end


#pragma mark -

id<HCMatcher> HC_greaterThan(id aValue)
{
    return [HCOrderingComparison compare:aValue
                              minCompare:NSOrderedAscending
                              maxCompare:NSOrderedAscending
                   comparisonDescription:@"greater than"];
}

id<HCMatcher> HC_greaterThanOrEqualTo(id aValue)
{
    return [HCOrderingComparison compare:aValue
                              minCompare:NSOrderedAscending
                              maxCompare:NSOrderedSame
                   comparisonDescription:@"greater than or equal to"];
}

id<HCMatcher> HC_lessThan(id aValue)
{
    return [HCOrderingComparison compare:aValue
                              minCompare:NSOrderedDescending
                              maxCompare:NSOrderedDescending
                   comparisonDescription:@"less than"];
}

id<HCMatcher> HC_lessThanOrEqualTo(id aValue)
{
    return [HCOrderingComparison compare:aValue
                              minCompare:NSOrderedSame
                              maxCompare:NSOrderedDescending
                   comparisonDescription:@"less than or equal to"];
}
