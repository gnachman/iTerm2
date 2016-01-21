//
//  OCHamcrest - HCIsInstanceOf.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCIsInstanceOf.h"

#import "HCDescription.h"
#import "HCRequireNonNilObject.h"


@implementation HCIsInstanceOf

+ (id)isInstanceOf:(Class)type
{
    return [[self alloc] initWithType:type];
}

- (BOOL)matches:(id)item
{
    return [item isKindOfClass:theClass];
}

- (NSString *)expectation
{
    return @"an instance of ";
}

@end


#pragma mark -

id<HCMatcher> HC_instanceOf(Class aClass)
{
    return [HCIsInstanceOf isInstanceOf:aClass];
}
