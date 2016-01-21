//
//  OCHamcrest - HCIsSame.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCIsSame.h"

#import "HCDescription.h"


@implementation HCIsSame

+ (id)isSameAs:(id)anObject
{
    return [[self alloc] initSameAs:anObject];
}

- (id)initSameAs:(id)anObject
{
    self = [super init];
    if (self)
        object = anObject;
    return self;
}

- (BOOL)matches:(id)item
{
    return item == object;
}

- (void)describeMismatchOf:(id)item to:(id<HCDescription>)mismatchDescription
{
    [mismatchDescription appendText:@"was "];
    if (item)
        [mismatchDescription appendText:[NSString stringWithFormat:@"%p ", (__bridge void *)item]];
    [mismatchDescription appendDescriptionOf:item];
}

- (void)describeTo:(id<HCDescription>)description
{
    [[description appendText:[NSString stringWithFormat:@"same instance as %p ", (__bridge void *)object]]
         appendDescriptionOf:object];
}

@end


#pragma mark -

id<HCMatcher> HC_sameInstance(id object)
{
    return [HCIsSame isSameAs:object];
}
