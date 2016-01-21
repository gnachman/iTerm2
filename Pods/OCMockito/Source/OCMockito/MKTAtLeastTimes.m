//
//  OCMockito - MKTAtLeastTimes.m
//  Copyright 2012 Jonathan M. Reid. See LICENSE.txt
//
//  Created by Markus Gasser on 18.04.12.
//  Source: https://github.com/jonreid/OCMockito
//

#import "MKTAtLeastTimes.h"

#import "MKTInvocationContainer.h"
#import "MKTInvocationMatcher.h"
#import "MKTVerificationData.h"


@implementation MKTAtLeastTimes
{
    NSUInteger _minimumExpectedCount;
}

+ (id)timesWithMinimumCount:(NSUInteger)minimumExpectedNumberOfInvocations
{
    return [[self alloc] initWithMinimumCount:minimumExpectedNumberOfInvocations];
}

- (id)initWithMinimumCount:(NSUInteger)minimumExpectedNumberOfInvocations
{
    self = [super init];
    if (self)
        _minimumExpectedCount = minimumExpectedNumberOfInvocations;
    return self;
}


#pragma mark MKTVerificationMode

- (void)verifyData:(MKTVerificationData *)data
{
    if (_minimumExpectedCount == 0)
        return;     // this always succeeds

    NSUInteger matchingCount = 0;
    for (NSInvocation *invocation in [[data invocations] registeredInvocations])
    {
        if ([[data wanted] matches:invocation])
            ++matchingCount;
    }

    if (matchingCount < _minimumExpectedCount)
    {
        NSString *plural = (_minimumExpectedCount == 1) ? @"" : @"s";
        NSString *description = [NSString stringWithFormat:@"Expected %u matching invocation%@, but received %u",
                                 (unsigned)_minimumExpectedCount, plural, (unsigned)matchingCount];
        MKTFailTestLocation([data testLocation], description);
    }
}

@end
