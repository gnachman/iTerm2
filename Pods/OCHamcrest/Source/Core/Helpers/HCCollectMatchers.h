//
//  OCHamcrest - HCCollectMatchers.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import <Foundation/Foundation.h>
#import <objc/objc-api.h>

#import <stdarg.h>

@protocol HCMatcher;


/**
    Returns an array of matchers from a variable-length comma-separated list terminated by @c nil.

    @ingroup helpers
*/
OBJC_EXPORT NSMutableArray *HCCollectMatchers(id item1, va_list args);
