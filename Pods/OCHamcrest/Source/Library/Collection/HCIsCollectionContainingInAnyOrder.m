//
//  OCHamcrest - HCIsCollectionContainingInAnyOrder.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCIsCollectionContainingInAnyOrder.h"

#import "HCAllOf.h"
#import "HCDescription.h"
#import "HCWrapInMatcher.h"


@interface HCMatchingInAnyOrder : NSObject
{
    NSMutableArray *matchers;
    id<HCDescription, NSObject> mismatchDescription;
}
@end


@implementation HCMatchingInAnyOrder

- (id)initWithMatchers:(NSMutableArray *)itemMatchers
   mismatchDescription:(id<HCDescription, NSObject>)description
{
    self = [super init];
    if (self)
    {
        matchers = itemMatchers;
        mismatchDescription = description;
    }
    return self;
}

- (BOOL)matches:(id)item
{
    NSUInteger index = 0;
    for (id<HCMatcher> matcher in matchers)
    {
        if ([matcher matches:item])
        {
            [matchers removeObjectAtIndex:index];
            return YES;
        }
        ++index;
    }
    [[mismatchDescription appendText:@"not matched: "] appendDescriptionOf:item];
    return NO;
}

- (BOOL)isFinishedWith:(NSArray *)collection
{
    if ([matchers count] == 0)
        return YES;

    [[[[mismatchDescription appendText:@"no item matches: "]
                            appendList:matchers start:@"" separator:@", " end:@""]
                            appendText:@" in "]
                            appendList:collection start:@"[" separator:@", " end:@"]"];
    return NO;
}

@end


#pragma mark -

@implementation HCIsCollectionContainingInAnyOrder

+ (id)isCollectionContainingInAnyOrder:(NSMutableArray *)itemMatchers
{
    return [[self alloc] initWithMatchers:itemMatchers];
}

- (id)initWithMatchers:(NSMutableArray *)itemMatchers
{
    self = [super init];
    if (self)
        matchers = itemMatchers;
    return self;
}

- (BOOL)matches:(id)collection
{
    return [self matches:collection describingMismatchTo:nil];
}

- (BOOL)matches:(id)collection describingMismatchTo:(id<HCDescription>)mismatchDescription
{
    if (![collection conformsToProtocol:@protocol(NSFastEnumeration)])
    {
        [super describeMismatchOf:collection to:mismatchDescription];
        return NO;
    }

    HCMatchingInAnyOrder *matchSequence =
        [[HCMatchingInAnyOrder alloc] initWithMatchers:matchers
                                   mismatchDescription:mismatchDescription];
    for (id item in collection)
        if (![matchSequence matches:item])
            return NO;

    return [matchSequence isFinishedWith:collection];
}

- (void)describeMismatchOf:(id)item to:(id<HCDescription>)mismatchDescription
{
    [self matches:item describingMismatchTo:mismatchDescription];
}

- (void)describeTo:(id<HCDescription>)description
{
    [[[description appendText:@"a collection over "]
                   appendList:matchers start:@"[" separator:@", " end:@"]"]
                   appendText:@" in any order"];
}

@end


#pragma mark -

id<HCMatcher> HC_containsInAnyOrder(id itemMatch, ...)
{
    NSMutableArray *matchers = [NSMutableArray arrayWithObject:HCWrapInMatcher(itemMatch)];

    va_list args;
    va_start(args, itemMatch);
    itemMatch = va_arg(args, id);
    while (itemMatch != nil)
    {
        [matchers addObject:HCWrapInMatcher(itemMatch)];
        itemMatch = va_arg(args, id);
    }
    va_end(args);

    return [HCIsCollectionContainingInAnyOrder isCollectionContainingInAnyOrder:matchers];
}
