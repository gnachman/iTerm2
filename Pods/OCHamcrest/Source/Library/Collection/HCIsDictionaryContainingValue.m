//
//  OCHamcrest - HCIsDictionaryContainingValue.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCIsDictionaryContainingValue.h"

#import "HCDescription.h"
#import "HCRequireNonNilObject.h"
#import "HCWrapInMatcher.h"


@implementation HCIsDictionaryContainingValue

+ (id)isDictionaryContainingValue:(id<HCMatcher>)theValueMatcher
{
    return [[self alloc] initWithValueMatcher:theValueMatcher];
}

- (id)initWithValueMatcher:(id<HCMatcher>)theValueMatcher
{
    self = [super init];
    if (self)
        valueMatcher = theValueMatcher;
    return self;
}

- (BOOL)matches:(id)dict
{
    if ([dict respondsToSelector:@selector(allValues)])
        for (id oneValue in [dict allValues])
            if ([valueMatcher matches:oneValue])
                return YES;
    return NO;
}

- (void)describeTo:(id<HCDescription>)description
{
    [[description appendText:@"a dictionary containing value "]
                  appendDescriptionOf:valueMatcher];
}

@end


#pragma mark -

id<HCMatcher> HC_hasValue(id valueMatch)
{
    HCRequireNonNilObject(valueMatch);
    return [HCIsDictionaryContainingValue isDictionaryContainingValue:HCWrapInMatcher(valueMatch)];
}
