//
//  OCHamcrest - HCInvocationMatcher.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCInvocationMatcher.h"

#import "HCDescription.h"


@implementation HCInvocationMatcher

@synthesize shortMismatchDescription;


+ (NSInvocation *)invocationForSelector:(SEL)selector onClass:(Class)aClass
{
    NSMethodSignature* signature = [aClass instanceMethodSignatureForSelector:selector];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setSelector:selector];
    return invocation;
}

- (id)initWithInvocation:(NSInvocation *)anInvocation matching:(id<HCMatcher>)aMatcher
{
    self = [super init];
    if (self)
    {
        invocation = anInvocation;
        subMatcher = aMatcher;
    }
    return self;
}

- (NSString *)stringFromSelector
{
    return NSStringFromSelector([invocation selector]);
}

- (id)invokeOn:(id)item
{
    __unsafe_unretained id result = nil;
    [invocation invokeWithTarget:item];
    [invocation getReturnValue:&result];
    return result;
}

- (BOOL)matches:(id)item
{
    if (![item respondsToSelector:[invocation selector]])
        return NO;

    return [subMatcher matches:[self invokeOn:item]];
}

- (void)describeMismatchOf:(id)item to:(id<HCDescription>)mismatchDescription
{
    if (![item respondsToSelector:[invocation selector]])
        [super describeMismatchOf:item to:mismatchDescription];
    else
    {
        if (!shortMismatchDescription)
        {
            [[[[mismatchDescription appendDescriptionOf:item]
                                    appendText:@" "]
                                    appendText:[self stringFromSelector]]
                                    appendText:@" "];
        }
        [subMatcher describeMismatchOf:[self invokeOn:item] to:mismatchDescription];
    }
}

- (void)describeTo:(id<HCDescription>)description
{
    [[[[description appendText:@"an object with "]
                    appendText:[self stringFromSelector]]
                    appendText:@" "]
                    appendDescriptionOf:subMatcher];
}

@end
