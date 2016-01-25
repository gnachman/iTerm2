//
//  OCHamcrest - HCConformsToProtocol.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Todd Farrell
//

#import "HCConformsToProtocol.h"

#import "HCDescription.h"
#import "HCRequireNonNilObject.h"


@implementation HCConformsToProtocol

+ (id)conformsTo:(Protocol *)protocol
{
    return [[self alloc] initWithProtocol:protocol];
}

- (id)initWithProtocol:(Protocol *)aProtocol
{
    HCRequireNonNilObject(aProtocol);

    self = [super init];
    if (self)
        theProtocol = aProtocol;
    return self;
}

- (BOOL)matches:(id)item
{
    return [item conformsToProtocol:theProtocol];
}

- (void)describeTo:(id<HCDescription>)description
{
    [[description appendText:@"an object that conforms to "]
                  appendText:NSStringFromProtocol(theProtocol)];
}

@end


#pragma mark -

id<HCMatcher> HC_conformsTo(Protocol *aProtocol)
{
    return [HCConformsToProtocol conformsTo:aProtocol];
}
