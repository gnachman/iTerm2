//
//  OCHamcrest - HCDescription.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import <Foundation/Foundation.h>


/**
    A description of an HCMatcher.

    An HCMatcher will describe itself to a description which can later be used for reporting.

    @ingroup core
 */
@protocol HCDescription <NSObject>

/**
    Appends some plain text to the description.

    @return @c self, for chaining.
 */
- (id<HCDescription>)appendText:(NSString *)text;

/**
    Appends description of given value to @c self.

    If the value implements the @ref HCSelfDescribing protocol, then it will be used.

    @return @c self, for chaining.
 */
- (id<HCDescription>)appendDescriptionOf:(id)value;

/**
    Appends a list of objects to the description.

    @return @c self, for chaining.
 */
- (id<HCDescription>)appendList:(NSArray *)values
                          start:(NSString *)start
                      separator:(NSString *)separator
                            end:(NSString *)end;

@end
