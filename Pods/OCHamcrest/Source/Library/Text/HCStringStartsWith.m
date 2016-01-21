//
//  OCHamcrest - HCStringStartsWith.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCStringStartsWith.h"


@implementation HCStringStartsWith

+ (id)stringStartsWith:(NSString *)aSubstring
{
    return [[self alloc] initWithSubstring:aSubstring];
}

- (BOOL)matches:(id)item
{
    if (![item respondsToSelector:@selector(hasPrefix:)])
        return NO;

    return [item hasPrefix:substring];
}

- (NSString *)relationship
{
    return @"starting with";
}

@end


#pragma mark -

id<HCMatcher> HC_startsWith(NSString *aString)
{
    return [HCStringStartsWith stringStartsWith:aString];
}
