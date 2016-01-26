//
//  OCHamcrest - HCIsEqualIgnoringCase.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import <OCHamcrest/HCBaseMatcher.h>


@interface HCIsEqualIgnoringCase : HCBaseMatcher
{
    NSString *string;
}

+ (id)isEqualIgnoringCase:(NSString *)aString;
- (id)initWithString:(NSString *)aString;

@end


OBJC_EXPORT id<HCMatcher> HC_equalToIgnoringCase(NSString *aString);

/**
    equalToIgnoringCase(aString) -
    Matches if object is a string equal to a given string, ignoring case differences.

    @param aString  The string to compare against as the expected value. This value must not be @c nil.

    This matcher first checks whether the evaluated object is a string. If so, it compares it with
    @a aString, ignoring differences of case.

    Example:

    @par
    @ref equalToIgnoringCase(@"hello world")

    will match "heLLo WorlD".

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_equalToIgnoringCase instead.)

    @ingroup text_matchers
 */
#ifdef HC_SHORTHAND
    #define equalToIgnoringCase HC_equalToIgnoringCase
#endif
