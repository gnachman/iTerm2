//
//  OCHamcrest - HCAllOf.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import <OCHamcrest/HCBaseMatcher.h>


@interface HCAllOf : HCBaseMatcher
{
    NSArray *matchers;
}

+ (id)allOf:(NSArray *)theMatchers;
- (id)initWithMatchers:(NSArray *)theMatchers;

@end


OBJC_EXPORT id<HCMatcher> HC_allOf(id match, ...) NS_REQUIRES_NIL_TERMINATION;

/**
    allOf(firstMatcher, ...) -
    Matches if all of the given matchers evaluate to @c YES.

    @param firstMatcher,...  A comma-separated list of matchers ending with @c nil.

    The matchers are evaluated from left to right using short-circuit evaluation, so evaluation
    stops as soon as a matcher returns @c NO.

    Any argument that is not a matcher is implicitly wrapped in an @ref equalTo matcher to check for
    equality.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_allOf instead.)

    @ingroup logical_matchers
 */
#ifdef HC_SHORTHAND
    #define allOf HC_allOf
#endif
