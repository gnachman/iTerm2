//
//  OCHamcrest - HCHasProperty.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Justin Shacklette
//

#import <OCHamcrest/HCBaseMatcher.h>


@interface HCHasProperty : HCBaseMatcher
{
    NSString *propertyName;
    id<HCMatcher> valueMatcher;
}

+ (id)hasProperty:(NSString *)property value:(id<HCMatcher>)aValueMatcher;
- (id)initWithProperty:(NSString *)property value:(id<HCMatcher>)aValueMatcher;

@end


OBJC_EXPORT id<HCMatcher> HC_hasProperty(NSString *name, id valueMatch);

/**
    hasProperty(name, valueMatcher) -
    Matches if object has a method of a given name whose return value satisfies a given matcher.

    @param name  The name of a method without arguments that returns an object.
    @param valueMatcher  The matcher to satisfy for the return value, or an expected value for @ref equalTo matching.

    This matcher first checks if the evaluated object has a method with a name matching the given
    @c name. If so, it invokes the method and sees if the returned value satisfies @c valueMatcher.

    While this matcher is called "hasProperty", it's useful for checking the results of any simple
    methods, not just properties.

    Examples:
    @li @ref hasProperty(\@"firstName", \@"Joe")
    @li @ref hasProperty(\@"firstName", startsWith(\@"J"))

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_hasProperty instead.)

    @ingroup object_matchers
 */
#ifdef HC_SHORTHAND
    #define hasProperty HC_hasProperty
#endif
