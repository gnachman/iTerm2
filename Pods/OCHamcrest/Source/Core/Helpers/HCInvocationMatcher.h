//
//  OCHamcrest - HCInvocationMatcher.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import <OCHamcrest/HCBaseMatcher.h>


/**
    Supporting class for matching a feature of an object.

    Tests whether the result of passing a given invocation to the value satisfies a given matcher.

    @ingroup helpers
 */
@interface HCInvocationMatcher : HCBaseMatcher
{
    NSInvocation *invocation;
    id<HCMatcher> subMatcher;
    BOOL shortMismatchDescription;
}

/**
    Determines whether a mismatch will be described in short form.

    Default is long form, which describes the object, the name of the invocation, and the
    sub-matcher's mismatch diagnosis. Short form only has the sub-matcher's mismatch diagnosis.
 */
@property (assign, nonatomic) BOOL shortMismatchDescription;

/**
    Helper method for creating an invocation.

    A class is specified only so we can determine the method signature.
 */
+ (NSInvocation *)invocationForSelector:(SEL)selector onClass:(Class)aClass;

/**
    Returns an HCInvocationMatcher object initialized with an invocation and a matcher.
 */
- (id)initWithInvocation:(NSInvocation *)anInvocation matching:(id<HCMatcher>)aMatcher;

/**
    Invokes stored invocation on given item and returns the result.
 */
- (id)invokeOn:(id)item;

/**
    Returns string representation of the invocation's selector.
 */
- (NSString *)stringFromSelector;

@end
