//
//  OCHamcrest - HCRequireNonNilString.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCRequireNonNilString.h"


void HCRequireNonNilString(NSString *string)
{
    if (string == nil)
    {
        @throw [NSException exceptionWithName:@"NotAString"
                                       reason:@"Must be non-nil string"
                                     userInfo:nil];
    }
}
