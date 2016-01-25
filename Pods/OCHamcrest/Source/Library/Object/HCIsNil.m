//
//  OCHamcrest - HCIsNil.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCIsNil.h"

#import "HCDescription.h"
#import "HCIsNot.h"


@implementation HCIsNil

+ (id)isNil
{
    return [[self alloc] init];
}

- (BOOL)matches:(id)item
{
    return item == nil;
}

- (void)describeTo:(id<HCDescription>)description
{
    [description appendText:@"nil"];
}

@end


#pragma mark -

id<HCMatcher> HC_nilValue()
{
    return [HCIsNil isNil];
}

id<HCMatcher> HC_notNilValue()
{
    return HC_isNot([HCIsNil isNil]);
}
