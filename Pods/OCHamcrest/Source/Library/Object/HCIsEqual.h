//
//  OCHamcrest - HCIsEqual.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import <OCHamcrest/HCBaseMatcher.h>


@interface HCIsEqual : HCBaseMatcher
{
    id object;
}

+ (id)isEqualTo:(id)anObject;
- (id)initEqualTo:(id)anObject;

@end


OBJC_EXPORT id<HCMatcher> HC_equalTo(id object);

/**
    equalTo(anObject) -
    Matches if object is equal to a given object.

    @param anObject  The object to compare against as the expected value.

    This matcher compares the evaluated object to @a anObject for equality, as determined by the
    @c -isEqual: method.

    If @a anObject is @c nil, the matcher will successfully match @c nil.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_equalTo instead.)

    @ingroup object_matchers
 */
#ifdef HC_SHORTHAND
    #define equalTo HC_equalTo
#endif
