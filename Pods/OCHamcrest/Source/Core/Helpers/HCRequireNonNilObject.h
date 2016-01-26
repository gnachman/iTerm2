//
//  OCHamcrest - HCRequireNonNilObject.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import <Foundation/Foundation.h>
#import <objc/objc-api.h>


/**
    Throws an NSException if @a obj is @c nil.

    @ingroup helpers
*/
OBJC_EXPORT void HCRequireNonNilObject(id obj);
