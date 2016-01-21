//
//  OCHamcrest - HCIsCollectionContainingInOrder.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCIsCollectionContainingInOrder.h"

#import "HCAllOf.h"
#import "HCDescription.h"
#import "HCWrapInMatcher.h"


@interface HCMatchSequence : NSObject
{
    NSArray *matchers;
    id<HCDescription, NSObject> mismatchDescription;
    NSUInteger nextMatchIndex;
}

- (BOOL)isMatched:(id)item;
- (BOOL)isNotSurplus:(id)item;
- (void)describeMismatchOfMatcher:(id<HCMatcher>)matcher item:(id)item;

@end

@implementation HCMatchSequence

- (id)initWithMatchers:(NSArray *)itemMatchers mismatchDescription:(id<HCDescription, NSObject>)description
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
    return [self isNotSurplus:item] && [self isMatched:item];
}

- (BOOL)isFinished
{
    if (nextMatchIndex < [matchers count])
    {
        [[mismatchDescription appendText:@"no item matched: "]
                              appendDescriptionOf:matchers[nextMatchIndex]];
        return NO;
    }
    return YES;
}

- (BOOL)isMatched:(id)item
{
    id<HCMatcher> matcher = matchers[nextMatchIndex];
    if (![matcher matches:item])
    {
        [self describeMismatchOfMatcher:matcher item:item];
        return NO;
    }
    ++nextMatchIndex;
    return YES;
}

- (BOOL)isNotSurplus:(id)item
{
    if ([matchers count] <= nextMatchIndex)
    {
        [[mismatchDescription appendText:@"not matched: "] appendDescriptionOf:item];
        return NO;
    }
    return YES;
}

- (void)describeMismatchOfMatcher:(id<HCMatcher>)matcher item:(id)item
{
    [mismatchDescription appendText:[NSString stringWithFormat:@"item %zi: ", nextMatchIndex]];
    [matcher describeMismatchOf:item to:mismatchDescription];
}

@end


#pragma mark -

@implementation HCIsCollectionContainingInOrder

+ (id)isCollectionContainingInOrder:(NSArray *)itemMatchers
{
    return [[self alloc] initWithMatchers:itemMatchers];
}

- (id)initWithMatchers:(NSArray *)itemMatchers
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

- (BOOL)matches:(id)collection describingMismatchTo:(id<HCDescription, NSObject>)mismatchDescription
{
    if (![collection conformsToProtocol:@protocol(NSFastEnumeration)])
    {
        [super describeMismatchOf:collection to:mismatchDescription];
        return NO;
    }

    HCMatchSequence *matchSequence =
        [[HCMatchSequence alloc] initWithMatchers:matchers
                              mismatchDescription:mismatchDescription];
    for (id item in collection)
        if (![matchSequence matches:item])
            return NO;

    return [matchSequence isFinished];
}

- (void)describeMismatchOf:(id)item to:(id<HCDescription>)mismatchDescription
{
    [self matches:item describingMismatchTo:mismatchDescription];
}

- (void)describeTo:(id<HCDescription>)description
{
    [[description appendText:@"a collection containing "]
                    appendList:matchers start:@"[" separator:@", " end:@"]"];
}

@end


#pragma mark -

id<HCMatcher> HC_contains(id itemMatch, ...)
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

    return [HCIsCollectionContainingInOrder isCollectionContainingInOrder:matchers];
}
