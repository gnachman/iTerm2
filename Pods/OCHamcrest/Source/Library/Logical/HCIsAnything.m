//
//  OCHamcrest - HCIsAnything.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCIsAnything.h"

#import "HCDescription.h"


@implementation HCIsAnything

+ (id)isAnything
{
    return [[self alloc] init];
}

+ (id)isAnythingWithDescription:(NSString *)aDescription
{
    return [[self alloc] initWithDescription:aDescription];
}

- (id)init
{
    self = [self initWithDescription:@"ANYTHING"];
    return self;
}

- (id)initWithDescription:(NSString *)aDescription
{
    self = [super init];
    if (self)
        description = [aDescription copy];
    return self;
}

- (BOOL)matches:(id)item
{
    return YES;
}

- (void)describeTo:(id<HCDescription>)aDescription
{
    [aDescription appendText:description];
}

@end


#pragma mark -

id<HCMatcher> HC_anything()
{
    return [HCIsAnything isAnything];
}

id<HCMatcher> HC_anythingWithDescription(NSString *description)
{
    return [HCIsAnything isAnythingWithDescription:description];
}
