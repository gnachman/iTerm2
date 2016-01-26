//
//  OCMockito - MKTOngoingStubbing.m
//  Copyright 2012 Jonathan M. Reid. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Source: https://github.com/jonreid/OCMockito
//

#import "MKTOngoingStubbing.h"

#import "MKTInvocationContainer.h"


@implementation MKTOngoingStubbing
{
    MKTInvocationContainer *_invocationContainer;
}

- (id)initWithInvocationContainer:(MKTInvocationContainer *)invocationContainer
{
    self = [super init];
    if (self)
        _invocationContainer = invocationContainer;
    return self;
}

- (MKTOngoingStubbing *)willReturn:(id)object
{
    [_invocationContainer addAnswer:object];
    return self;
}

#define DEFINE_RETURN_METHOD(type, typeName)                        \
    - (MKTOngoingStubbing *)willReturn ## typeName:(type)value      \
    {                                                               \
        [_invocationContainer addAnswer:@(value)];                  \
        return self;                                                \
    }

DEFINE_RETURN_METHOD(BOOL, Bool)
DEFINE_RETURN_METHOD(char, Char)
DEFINE_RETURN_METHOD(int, Int)
DEFINE_RETURN_METHOD(short, Short)
DEFINE_RETURN_METHOD(long, Long)
DEFINE_RETURN_METHOD(long long, LongLong)
DEFINE_RETURN_METHOD(NSInteger, Integer)
DEFINE_RETURN_METHOD(unsigned char, UnsignedChar)
DEFINE_RETURN_METHOD(unsigned int, UnsignedInt)
DEFINE_RETURN_METHOD(unsigned short, UnsignedShort)
DEFINE_RETURN_METHOD(unsigned long, UnsignedLong)
DEFINE_RETURN_METHOD(unsigned long long, UnsignedLongLong)
DEFINE_RETURN_METHOD(NSUInteger, UnsignedInteger)
DEFINE_RETURN_METHOD(float, Float)
DEFINE_RETURN_METHOD(double, Double)


#pragma mark MKTPrimitiveArgumentMatching

- (id)withMatcher:(id <HCMatcher>)matcher forArgument:(NSUInteger)index
{
    [_invocationContainer setMatcher:matcher atIndex:index+2];
    return self;
}

- (id)withMatcher:(id <HCMatcher>)matcher
{
    return [self withMatcher:matcher forArgument:0];
}

@end
