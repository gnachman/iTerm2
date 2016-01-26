//
//  OCHamcrest - HCIsCollectionContainingInAnyOrder.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import <OCHamcrest/HCBaseMatcher.h>


@interface HCIsCollectionContainingInAnyOrder : HCBaseMatcher
{
    NSMutableArray *matchers;
}

+ (id)isCollectionContainingInAnyOrder:(NSMutableArray *)itemMatchers;
- (id)initWithMatchers:(NSMutableArray *)itemMatchers;

@end


OBJC_EXPORT id<HCMatcher> HC_containsInAnyOrder(id itemMatch, ...) NS_REQUIRES_NIL_TERMINATION;

/**
    containsInAnyOrder(firstMatcher, ...) -
    Matches if collection's elements, in any order, satisfy a given list of matchers.

    @param firstMatcher,...  A comma-separated list of matchers ending with @c nil.

    This matcher iterates the evaluated collection, seeing if each element satisfies any of the
    given matchers. The matchers are tried from left to right, and when a satisfied matcher is
    found, it is no longer a candidate for the remaining elements. If a one-to-one correspondence is
    established between elements and matchers, @c containsInAnyOrder is satisfied.

    Any argument that is not a matcher is implicitly wrapped in an @ref equalTo matcher to check for
    equality.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_containsInAnyOrder instead.)

    @ingroup collection_matchers
 */
#ifdef HC_SHORTHAND
    #define containsInAnyOrder HC_containsInAnyOrder
#endif
