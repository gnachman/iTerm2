//
//  OCHamcrest - HCIsDictionaryContainingValue.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import <OCHamcrest/HCBaseMatcher.h>


@interface HCIsDictionaryContainingValue : HCBaseMatcher
{
    id<HCMatcher> valueMatcher;
}

+ (id)isDictionaryContainingValue:(id<HCMatcher>)theValueMatcher;
- (id)initWithValueMatcher:(id<HCMatcher>)theValueMatcher;

@end


OBJC_EXPORT id<HCMatcher> HC_hasValue(id valueMatch);

/**
    hasValue(valueMatcher) -
    Matches if dictionary contains an entry whose value satisfies a given matcher.

    @param valueMatcher  The matcher to satisfy for the value, or an expected value for @ref equalTo matching.

    This matcher iterates the evaluated dictionary, searching for any key-value entry whose value
    satisfies the given matcher. If a matching entry is found, @c hasValue is satisfied.

    Any argument that is not a matcher is implicitly wrapped in an @ref equalTo matcher to check for
    equality.

    Examples:
    @li @ref hasValue(equalTo(@"bar"))
    @li @ref hasValue(@"bar")

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_hasValue instead.)

    @ingroup collection_matchers
 */
#ifdef HC_SHORTHAND
    #define hasValue HC_hasValue
#endif
