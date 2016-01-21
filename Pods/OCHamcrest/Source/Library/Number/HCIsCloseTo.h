//
//  OCHamcrest - HCIsCloseTo.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import <OCHamcrest/HCBaseMatcher.h>


@interface HCIsCloseTo : HCBaseMatcher
{
    double value;
    double delta;
}

+ (id)isCloseTo:(double)aValue within:(double)aDelta;
- (id)initWithValue:(double)aValue delta:(double)aDelta;

@end


OBJC_EXPORT id<HCMatcher> HC_closeTo(double aValue, double aDelta);

/**
    closeTo(aValue, aDelta) -
    Matches if object is a number close to a given value, within a given delta.

    @param aValue   The @c double value to compare against as the expected value.
    @param aDelta   The @c double maximum delta between the values for which the numbers are considered close.

    This matcher invokes @c -doubleValue on the evaluated object to get its value as a @c double.
    The result is compared against @a aValue to see if the difference is within a positive @a aDelta.

    Example:
    @li @ref closeTo(3.0, 0.25)

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_closeTo instead.)

    @ingroup number_matchers
 */
#ifdef HC_SHORTHAND
    #define closeTo HC_closeTo
#endif
