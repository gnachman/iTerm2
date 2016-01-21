//
//  OCHamcrest - HCHasCount.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import <OCHamcrest/HCBaseMatcher.h>


@interface HCHasCount : HCBaseMatcher
{
    id<HCMatcher> countMatcher;
}

+ (id)hasCount:(id<HCMatcher>)matcher;
- (id)initWithCount:(id<HCMatcher>)matcher;

@end


OBJC_EXPORT id<HCMatcher> HC_hasCount(id<HCMatcher> matcher);

/**
    hasCount(aMatcher) -
    Matches if object's @c -count satisfies a given matcher.

    @param aMatcher  The matcher to satisfy.

    This matcher invokes @c -count on the evaluated object to get the number of elements it
    contains, passing the result to @a aMatcher for evaluation.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_hasCount instead.)

    @ingroup collection_matchers
 */
#ifdef HC_SHORTHAND
    #define hasCount HC_hasCount
#endif


OBJC_EXPORT id<HCMatcher> HC_hasCountOf(NSUInteger count);

/**
    hasCountOf(value) -
    Matches if object's @c -count equals a given value.

    @param value  @c NSUInteger value to compare against as the expected value.

    This matcher invokes @c -count on the evaluated object to get the number of elements it
    contains, comparing the result to @a value for equality.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_hasCountOf instead.)

    @ingroup collection_matchers
 */
#ifdef HC_SHORTHAND
    #define hasCountOf HC_hasCountOf
#endif
