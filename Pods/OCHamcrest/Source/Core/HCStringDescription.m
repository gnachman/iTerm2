//
//  OCHamcrest - HCStringDescription.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCStringDescription.h"

#import "HCSelfDescribing.h"


@implementation HCStringDescription

+ (NSString *)stringFrom:(id<HCSelfDescribing>)selfDescribing
{
    HCStringDescription *description = [HCStringDescription stringDescription];
    [description appendDescriptionOf:selfDescribing];
    return [description description];
}

+ (HCStringDescription *)stringDescription
{
    return [[HCStringDescription alloc] init];
}

- (id)init
{
    self = [super init];
    if (self)
        accumulator = [[NSMutableString alloc] init];
    return self;
}

- (NSString *)description
{
    return accumulator;
}

- (void)append:(NSString *)str
{
    [accumulator appendString:str];
}

@end
