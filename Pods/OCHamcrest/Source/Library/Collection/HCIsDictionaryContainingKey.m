//
//  OCHamcrest - HCIsDictionaryContainingKey.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCIsDictionaryContainingKey.h"

#import "HCDescription.h"
#import "HCRequireNonNilObject.h"
#import "HCWrapInMatcher.h"


@implementation HCIsDictionaryContainingKey

+ (id)isDictionaryContainingKey:(id<HCMatcher>)theKeyMatcher
{
    return [[self alloc] initWithKeyMatcher:theKeyMatcher];
}

- (id)initWithKeyMatcher:(id<HCMatcher>)theKeyMatcher
{
    self = [super init];
    if (self)
        keyMatcher = theKeyMatcher;
    return self;
}

- (BOOL)matches:(id)dict
{
    if ([dict isKindOfClass:[NSDictionary class]])
        for (id oneKey in dict)
            if ([keyMatcher matches:oneKey])
                return YES;
    return NO;
}

- (void)describeTo:(id<HCDescription>)description
{
    [[description appendText:@"a dictionary containing key "]
                  appendDescriptionOf:keyMatcher];
}

@end


#pragma mark -

id<HCMatcher> HC_hasKey(id keyMatch)
{
    HCRequireNonNilObject(keyMatch);
    return [HCIsDictionaryContainingKey isDictionaryContainingKey:HCWrapInMatcher(keyMatch)];
}
