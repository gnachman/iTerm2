//
//  OCHamcrest - HCStringContains.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import <OCHamcrest/HCSubstringMatcher.h>


@interface HCStringContains : HCSubstringMatcher

+ (id)stringContains:(NSString *)aSubstring;

@end


OBJC_EXPORT id<HCMatcher> HC_containsString(NSString *aSubstring);

/**
    containsString(aString) -
    Matches if object is a string containing a given string.

    @param aString  The string to search for. This value must not be @c nil.

    This matcher first checks whether the evaluated object is a string. If so, it checks whether it
    contains @a aString.

    Example:

    @par
    @ref containsString(@"def")

    will match "abcdefg".

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_containsString instead.)

    @ingroup text_matchers
 */
#ifdef HC_SHORTHAND
    #define containsString HC_containsString
#endif
