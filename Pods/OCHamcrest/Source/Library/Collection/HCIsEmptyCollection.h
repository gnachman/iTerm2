//
//  OCHamcrest - HCIsEmptyCollection.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import <OCHamcrest/HCHasCount.h>


@interface HCIsEmptyCollection : HCHasCount

+ (id)isEmptyCollection;
- (id)init;

@end


OBJC_EXPORT id<HCMatcher> HC_empty(void);

/**
    Matches empty collection.

    This matcher invokes @c -count on the evaluated object to determine if the number of elements it
    contains is zero.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_empty instead.)

    @ingroup collection_matchers
 */
#ifdef HC_SHORTHAND
    #define empty() HC_empty()
#endif
