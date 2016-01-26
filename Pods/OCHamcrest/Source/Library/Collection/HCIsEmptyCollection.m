//
//  OCHamcrest - HCIsEmptyCollection.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCIsEmptyCollection.h"

#import "HCDescription.h"
#import "HCIsEqualToNumber.h"


@implementation HCIsEmptyCollection

+ (id)isEmptyCollection
{
    return [[self alloc] init];
}

- (id)init
{
    self = [super initWithCount:HC_equalToUnsignedInteger(0)];
    return self;
}

- (void)describeMismatchOf:(id)item to:(id<HCDescription>)mismatchDescription
{
    [[mismatchDescription appendText:@"was "] appendDescriptionOf:item];
}

- (void)describeTo:(id<HCDescription>)description
{
    [description appendText:@"empty collection"];
}

@end


#pragma mark -

OBJC_EXPORT id<HCMatcher> HC_empty()
{
    return [HCIsEmptyCollection isEmptyCollection];
}
