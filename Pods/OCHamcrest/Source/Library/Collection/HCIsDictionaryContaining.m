//
//  OCHamcrest - HCIsDictionaryContaining.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCIsDictionaryContaining.h"

#import "HCDescription.h"
#import "HCRequireNonNilObject.h"
#import "HCWrapInMatcher.h"


@implementation HCIsDictionaryContaining

+ (id)isDictionaryContainingKey:(id<HCMatcher>)aKeyMatcher
                          value:(id<HCMatcher>)aValueMatcher
{
    return [[self alloc] initWithKeyMatcher:aKeyMatcher valueMatcher:aValueMatcher];
}

- (id)initWithKeyMatcher:(id<HCMatcher>)aKeyMatcher
            valueMatcher:(id<HCMatcher>)aValueMatcher
{
    self = [super init];
    if (self)
    {
        keyMatcher = aKeyMatcher;
        valueMatcher = aValueMatcher;
    }
    return self;
}

- (BOOL)matches:(id)dict
{
    if ([dict isKindOfClass:[NSDictionary class]])
        for (id oneKey in dict)
            if ([keyMatcher matches:oneKey] && [valueMatcher matches:dict[oneKey]])
                return YES;
    return NO;
}

- (void)describeTo:(id<HCDescription>)description
{
    [[[[[description appendText:@"a dictionary containing { "]
                     appendDescriptionOf:keyMatcher]
                     appendText:@" = "]
                     appendDescriptionOf:valueMatcher]
                     appendText:@"; }"];
}

@end


#pragma mark -

id<HCMatcher> HC_hasEntry(id keyMatch, id valueMatch)
{
    HCRequireNonNilObject(keyMatch);
    HCRequireNonNilObject(valueMatch);
    return [HCIsDictionaryContaining isDictionaryContainingKey:HCWrapInMatcher(keyMatch)
                                                         value:HCWrapInMatcher(valueMatch)];
}
