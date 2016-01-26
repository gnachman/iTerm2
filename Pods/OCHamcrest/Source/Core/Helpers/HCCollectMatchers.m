//
//  OCHamcrest - HCCollectMatchers.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCCollectMatchers.h"

#import "HCWrapInMatcher.h"


NSMutableArray *HCCollectMatchers(id item, va_list args)
{
    NSMutableArray *matcherList = [NSMutableArray arrayWithObject:HCWrapInMatcher(item)];

    item = va_arg(args, id);
    while (item != nil)
    {
        [matcherList addObject:HCWrapInMatcher(item)];
        item = va_arg(args, id);
    }

    return matcherList;
}
