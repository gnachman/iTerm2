//
//  OCHamcrest - HCIsEqual.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCIsEqual.h"

#import "HCDescription.h"


@implementation HCIsEqual

+ (id)isEqualTo:(id)anObject
{
    return [[self alloc] initEqualTo:anObject];
}

- (id)initEqualTo:(id)anObject
{
    self = [super init];
    if (self)
        object = anObject;
    return self;
}

- (BOOL)matches:(id)item
{
    if (item == nil)
        return object == nil;
    else
        return [item isEqual:object];
}

- (void)describeTo:(id<HCDescription>)description
{
    if ([object conformsToProtocol:@protocol(HCMatcher)])
    {
        [[[description appendText:@"<"]
                       appendDescriptionOf:object]
                       appendText:@">"];
    }
    else
        [description appendDescriptionOf:object];
}

@end


#pragma mark -

id<HCMatcher> HC_equalTo(id object)
{
    return [HCIsEqual isEqualTo:object];
}
