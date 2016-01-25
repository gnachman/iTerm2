//
//  OCHamcrest - HCAllOf.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCAllOf.h"

#import "HCCollectMatchers.h"
#import "HCDescription.h"


@implementation HCAllOf

+ (id)allOf:(NSArray *)theMatchers
{
    return [[self alloc] initWithMatchers:theMatchers];
}

- (id)initWithMatchers:(NSArray *)theMatchers
{
    self = [super init];
    if (self)
        matchers = theMatchers;
    return self;
}

- (BOOL)matches:(id)item
{
    return [self matches:item describingMismatchTo:nil];
}

- (BOOL)matches:(id)item describingMismatchTo:(id<HCDescription>)mismatchDescription
{
    for (id<HCMatcher> oneMatcher in matchers)
    {
        if (![oneMatcher matches:item])
        {
            [[mismatchDescription appendDescriptionOf:oneMatcher] appendText:@" "];
            [oneMatcher describeMismatchOf:item to:mismatchDescription];
            return NO;
        }
    }
    return YES;
}

- (void)describeMismatchOf:(id)item to:(id<HCDescription>)mismatchDescription
{
    [self matches:item describingMismatchTo:mismatchDescription];
}

- (void)describeTo:(id<HCDescription>)description
{
    [description appendList:matchers start:@"(" separator:@" and " end:@")"];
}

@end


#pragma mark -

id<HCMatcher> HC_allOf(id match, ...)
{
    va_list args;
    va_start(args, match);
    NSArray *matcherList = HCCollectMatchers(match, args);
    va_end(args);

    return [HCAllOf allOf:matcherList];
}
