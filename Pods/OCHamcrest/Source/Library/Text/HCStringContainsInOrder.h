//
//  OCHamcrest - HCStringContainsInOrder.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import <OCHamcrest/HCBaseMatcher.h>


@interface HCStringContainsInOrder : HCBaseMatcher
{
    NSArray *substrings;
}

+ (id)containsInOrder:(NSArray *)substringList;
- (id)initWithSubstrings:(NSArray *)substringList;

@end


OBJC_EXPORT id<HCMatcher> HC_stringContainsInOrder(NSString *substring, ...) NS_REQUIRES_NIL_TERMINATION;

/**
    stringContainsInOrder(firstString, ...) -
    Matches if object is a string containing a given list of substrings in relative order.

    @param firstString,...  A comma-separated list of strings ending with @c nil.

    This matcher first checks whether the evaluated object is a string. If so, it checks whether it
    contains a given list of strings, in relative order to each other. The searches are performed
    starting from the beginning of the evaluated string.

    Example:

    @par
    @ref stringContainsInOrder(@"bc", @"fg", @"jkl", nil)

    will match "abcdefghijklm".

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_stringContainsInOrder instead.)

    @ingroup text_matchers
 */
#ifdef HC_SHORTHAND
    #define stringContainsInOrder HC_stringContainsInOrder
#endif
