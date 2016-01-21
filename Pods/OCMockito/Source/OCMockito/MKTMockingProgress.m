//
//  OCMockito - MKTMockingProgress.m
//  Copyright 2012 Jonathan M. Reid. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Source: https://github.com/jonreid/OCMockito
//

#import "MKTMockingProgress.h"

#import "MKTInvocationMatcher.h"
#import "MKTOngoingStubbing.h"
#import "MKTVerificationMode.h"


@interface MKTMockingProgress ()
@property (nonatomic, strong) MKTInvocationMatcher *invocationMatcher;
@property (nonatomic, strong) id <MKTVerificationMode> verificationMode;
@property (nonatomic, strong) MKTOngoingStubbing *ongoingStubbing;
@end


@implementation MKTMockingProgress

+ (id)sharedProgress
{
    static id sharedProgress = nil;

    if (!sharedProgress)
        sharedProgress = [[self alloc] init];
    return sharedProgress;
}

- (void)stubbingStartedAtLocation:(MKTTestLocation)location
{
    [self setTestLocation:location];
}

- (void)reportOngoingStubbing:(MKTOngoingStubbing *)ongoingStubbing
{
    [self setOngoingStubbing:ongoingStubbing];
}

- (MKTOngoingStubbing *)pullOngoingStubbing
{
    MKTOngoingStubbing *result = _ongoingStubbing;
    [self setOngoingStubbing:nil];
    return result;
}

- (void)verificationStarted:(id <MKTVerificationMode>)mode atLocation:(MKTTestLocation)location
{
    [self setVerificationMode:mode];
    [self setTestLocation:location];
}

- (id <MKTVerificationMode>)pullVerificationMode
{
    id <MKTVerificationMode> result = _verificationMode;
    [self setVerificationMode:nil];
    return result;
}

- (void)setMatcher:(id <HCMatcher>)matcher forArgument:(NSUInteger)index
{
    if (!_invocationMatcher)
        _invocationMatcher = [[MKTInvocationMatcher alloc] init];
    [_invocationMatcher setMatcher:matcher atIndex:index+2];
}

- (MKTInvocationMatcher *)pullInvocationMatcher
{
    MKTInvocationMatcher *result = _invocationMatcher;
    [self setInvocationMatcher:nil];
    return result;
}

@end
