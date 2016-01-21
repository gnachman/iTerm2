//
//  OCHamcrest - HCIsDictionaryContainingEntries.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCIsDictionaryContainingEntries.h"

#import "HCDescription.h"
#import "HCWrapInMatcher.h"


@implementation HCIsDictionaryContainingEntries

+ (id)isDictionaryContainingKeys:(NSArray *)theKeys
                   valueMatchers:(NSArray *)theValueMatchers
{
    return [[self alloc] initWithKeys:theKeys valueMatchers:theValueMatchers];
}

- (id)initWithKeys:(NSArray *)theKeys
     valueMatchers:(NSArray *)theValueMatchers
{
    self = [super init];
    if (self)
    {
        keys = theKeys;
        valueMatchers = theValueMatchers;
    }
    return self;
}

- (BOOL)matches:(id)item
{
    return [self matches:item describingMismatchTo:nil];
}

- (BOOL)matches:(id)dict describingMismatchTo:(id<HCDescription>)mismatchDescription
{
    if (![dict isKindOfClass:[NSDictionary class]])
    {
        [super describeMismatchOf:dict to:mismatchDescription];
        return NO;
    }

    NSUInteger count = [keys count];
    for (NSUInteger index = 0; index < count; ++index)
    {
        id key = keys[index];
        if (dict[key] == nil)
        {
            [[[[mismatchDescription appendText:@"no "]
                                    appendDescriptionOf:key]
                                    appendText:@" key in "]
                                    appendDescriptionOf:dict];
            return NO;
        }

        id valueMatcher = valueMatchers[index];
        id actualValue = dict[key];

        if (![valueMatcher matches:actualValue])
        {
            [[[[mismatchDescription appendText:@"value for "]
                                    appendDescriptionOf:key]
                                    appendText:@" was "]
                                    appendDescriptionOf:actualValue];
            return NO;
        }
    }

    return YES;
}

- (void)describeMismatchOf:(id)item to:(id<HCDescription>)mismatchDescription
{
    [self matches:item describingMismatchTo:mismatchDescription];
}

- (void)describeKeyValueAtIndex:(NSUInteger)index to:(id<HCDescription>)description
{
    [[[[description appendDescriptionOf:keys[index]]
                    appendText:@" = "]
                    appendDescriptionOf:valueMatchers[index]]
                    appendText:@"; "];
}

- (void)describeTo:(id<HCDescription>)description
{
    [description appendText:@"a dictionary containing { "];
    NSUInteger count = [keys count];
    NSUInteger index = 0;
    for (; index < count - 1; ++index)
        [self describeKeyValueAtIndex:index to:description];
    [self describeKeyValueAtIndex:index to:description];
    [description appendText:@"}"];
}

@end


#pragma mark -

static void requirePairedObject(id obj)
{
    if (obj == nil)
    {
        @throw [NSException exceptionWithName:@"NilObject"
                                       reason:@"HC_hasEntries keys and value matchers must be paired"
                                     userInfo:nil];
    }
}


id<HCMatcher> HC_hasEntries(id keysAndValueMatch, ...)
{
    va_list args;
    va_start(args, keysAndValueMatch);

    id key = keysAndValueMatch;
    id valueMatcher = va_arg(args, id);
    requirePairedObject(valueMatcher);
    NSMutableArray *keys = [NSMutableArray arrayWithObject:key];
    NSMutableArray *valueMatchers = [NSMutableArray arrayWithObject:HCWrapInMatcher(valueMatcher)];

    key = va_arg(args, id);
    while (key != nil)
    {
        [keys addObject:key];
        valueMatcher = va_arg(args, id);
        requirePairedObject(valueMatcher);
        [valueMatchers addObject:HCWrapInMatcher(valueMatcher)];
        key = va_arg(args, id);
    }

    return [HCIsDictionaryContainingEntries isDictionaryContainingKeys:keys
                                                         valueMatchers:valueMatchers];
}
