//
//  OCHamcrest - HCBaseDescription.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import <Foundation/Foundation.h>
#import <OCHamcrest/HCDescription.h>


/**
    Base class for all HCDescription implementations.

    @ingroup core
 */
@interface HCBaseDescription : NSObject <HCDescription>
@end


/**
    Methods that must be provided by subclasses of HCBaseDescription.
 */
@interface HCBaseDescription (SubclassMustImplement)

/**
    Append the string @a str to the description.
 */
- (void)append:(NSString *)str;

@end
