//
//  OCMockito - MKTPrimitiveArgumentMatching.h
//  Copyright 2012 Jonathan M. Reid. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Source: https://github.com/jonreid/OCMockito
//

@protocol HCMatcher;


/**
    Ability to specify OCHamcrest matchers for primitive numeric arguments.
 */
@protocol MKTPrimitiveArgumentMatching

/**
    Specifies OCHamcrest matcher for a specific argument of a method.

    For methods arguments that take objects, just pass the matcher directly as a method call. But
    for arguments that take primitive numeric types, call this to specify the matcher before passing
    in a dummy value. Upon verification, the actual numeric argument received will be converted to
    an NSNumber before being checked by the matcher.

    The argument index is 0-based, so the first argument of a method has index 0.

    Example:
@code
[[verify(mockArray) withMatcher:greaterThan([NSNumber numberWithInt:1]) forArgument:0]
    removeObjectAtIndex:0];
@endcode
    This verifies that @c removeObjectAtIndex: was called with a number greater than 1.
 */
- (id)withMatcher:(id <HCMatcher>)matcher forArgument:(NSUInteger)index;

/**
    Specifies OCHamcrest matcher for the first argument of a method.

    Equivalent to <code>withMatcher:matcher forArgument:0</code>.

    Example:
@code
[[verify(mockArray) withMatcher:greaterThan([NSNumber numberWithInt:1]) forArgument:0]
    removeObjectAtIndex:0];
@endcode
    This verifies that @c removeObjectAtIndex: was called with a number greater than 1.
*/
- (id)withMatcher:(id <HCMatcher>)matcher;

@end
