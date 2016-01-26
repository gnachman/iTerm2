//
//  OCHamcrest - HCConformsToProtocol.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Todd Farrell
//

#import <OCHamcrest/HCBaseMatcher.h>


@interface HCConformsToProtocol : HCBaseMatcher
{
    Protocol *theProtocol;
}

+ (id)conformsTo:(Protocol *)protocol;
- (id)initWithProtocol:(Protocol *)protocol;

@end


OBJC_EXPORT id<HCMatcher> HC_conformsTo(Protocol *aProtocol);

/**
    conformsTo(aProtocol) -
    Matches if object conforms to a given protocol.

    @param aProtocol  The protocol to compare against as the expected protocol.

    This matcher checks whether the evaluated object conforms to @a aProtocol.

    Example:
    @li @ref conformsTo(\@protocol(NSObject))

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_conformsTo instead.)

    @ingroup object_matchers
 */
#ifdef HC_SHORTHAND
    #define conformsTo HC_conformsTo
#endif
