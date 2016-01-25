//
//  OCHamcrest - HCBaseMatcher.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCBaseMatcher.h"

#import "HCStringDescription.h"

#define ABSTRACT_METHOD [self subclassResponsibility:_cmd]


@implementation HCBaseMatcher

- (NSString *)description
{
    return [HCStringDescription stringFrom:self];
}

- (BOOL)matches:(id)item
{
    ABSTRACT_METHOD;
    return NO;
}

- (BOOL)matches:(id)item describingMismatchTo:(id<HCDescription>)mismatchDescription
{
    BOOL matchResult = [self matches:item];
    if (!matchResult)
        [self describeMismatchOf:item to:mismatchDescription];
    return matchResult;
}

- (void)describeMismatchOf:(id)item to:(id<HCDescription>)mismatchDescription
{
    [[mismatchDescription appendText:@"was "] appendDescriptionOf:item];
}

- (void)describeTo:(id<HCDescription>)description
{
    ABSTRACT_METHOD;
}

- (void)subclassResponsibility:(SEL)command
{
    NSString *className = NSStringFromClass([self class]);
    [NSException raise:NSGenericException
                format:@"-[%@  %@] not implemented", className, NSStringFromSelector(command)];
}

@end
