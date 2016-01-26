//
//  OCHamcrest - HCStringEndsWith.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCStringEndsWith.h"


@implementation HCStringEndsWith

+ (id)stringEndsWith:(NSString *)aString
{
    return [[self alloc] initWithSubstring:aString];
}

- (BOOL)matches:(id)item
{
    if (![item respondsToSelector:@selector(hasSuffix:)])
        return NO;

    return [item hasSuffix:substring];
}

- (NSString *)relationship
{
    return @"ending with";
}

@end


#pragma mark -

id<HCMatcher> HC_endsWith(NSString *aString)
{
    return [HCStringEndsWith stringEndsWith:aString];
}
