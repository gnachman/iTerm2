//
//  OCMockito - MKTBaseMockObject.m
//  Copyright 2012 Jonathan M. Reid. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Source: https://github.com/jonreid/OCMockito
//

#import "MKTBaseMockObject.h"

#import "MKTInvocationContainer.h"
#import "MKTInvocationMatcher.h"
#import "MKTMockingProgress.h"
#import "MKTOngoingStubbing.h"
#import "MKTTypeEncoding.h"
#import "MKTVerificationData.h"
#import "MKTVerificationMode.h"


@implementation MKTBaseMockObject
{
    MKTMockingProgress *_mockingProgress;
    MKTInvocationContainer *_invocationContainer;
}

- (id)init
{
    if (self)
    {
        _mockingProgress = [MKTMockingProgress sharedProgress];
        _invocationContainer = [[MKTInvocationContainer alloc] initWithMockingProgress:_mockingProgress];

    }
    return self;
}

#define HANDLE_METHOD_RETURN_TYPE(type, typeName)                                            \
    else if (strcmp(methodReturnType, @encode(type)) == 0)                                   \
    {                                                                                        \
        type answer = [[_invocationContainer findAnswerFor:anInvocation] typeName ## Value]; \
        [anInvocation setReturnValue:&answer];                                               \
    }

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    id <MKTVerificationMode> verificationMode = [_mockingProgress pullVerificationMode];
    if (verificationMode)
    {
        MKTInvocationMatcher *invocationMatcher = [_mockingProgress pullInvocationMatcher];
        if (!invocationMatcher)
            invocationMatcher = [[MKTInvocationMatcher alloc] init];
        [invocationMatcher setExpectedInvocation:anInvocation];

        MKTVerificationData *data = [[MKTVerificationData alloc] init];
        [data setInvocations:_invocationContainer];
        [data setWanted:invocationMatcher];
        [data setTestLocation:[_mockingProgress testLocation]];
        [verificationMode verifyData:data];

        return;
    }

    [_invocationContainer setInvocationForPotentialStubbing:anInvocation];
    MKTOngoingStubbing *ongoingStubbing = [[MKTOngoingStubbing alloc]
                                           initWithInvocationContainer:_invocationContainer];
    [_mockingProgress reportOngoingStubbing:ongoingStubbing];

    NSMethodSignature *methodSignature = [anInvocation methodSignature];
    const char* methodReturnType = [methodSignature methodReturnType];
    if (MKTTypeEncodingIsObjectOrClass(methodReturnType))
    {
        __unsafe_unretained id answer = [_invocationContainer findAnswerFor:anInvocation];
        [anInvocation setReturnValue:&answer];
    }
    HANDLE_METHOD_RETURN_TYPE(char, char)
    HANDLE_METHOD_RETURN_TYPE(int, int)
    HANDLE_METHOD_RETURN_TYPE(short, short)
    HANDLE_METHOD_RETURN_TYPE(long, long)
    HANDLE_METHOD_RETURN_TYPE(long long, longLong)
    HANDLE_METHOD_RETURN_TYPE(unsigned char, unsignedChar)
    HANDLE_METHOD_RETURN_TYPE(unsigned int, unsignedInt)
    HANDLE_METHOD_RETURN_TYPE(unsigned short, unsignedShort)
    HANDLE_METHOD_RETURN_TYPE(unsigned long, unsignedLong)
    HANDLE_METHOD_RETURN_TYPE(unsigned long long, unsignedLongLong)
    HANDLE_METHOD_RETURN_TYPE(float, float)
    HANDLE_METHOD_RETURN_TYPE(double, double)
}


#pragma mark MKTPrimitiveArgumentMatching

- (id)withMatcher:(id <HCMatcher>)matcher forArgument:(NSUInteger)index
{
    [_mockingProgress setMatcher:matcher forArgument:index];
    return self;
}

- (id)withMatcher:(id <HCMatcher>)matcher
{
    return [self withMatcher:matcher forArgument:0];
}

@end
