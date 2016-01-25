//
//  OCMockito - MKTMockitoCore.m
//  Copyright 2012 Jonathan M. Reid. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Source: https://github.com/jonreid/OCMockito
//

#import "MKTMockitoCore.h"

#import "MKTMockingProgress.h"
#import "MKTVerificationMode.h"


@implementation MKTMockitoCore
{
    MKTMockingProgress *_mockingProgress;
}

+ (id)sharedCore
{
    static id sharedCore = nil;

    if (!sharedCore)
        sharedCore = [[self alloc] init];
    return sharedCore;
}

- (id)init
{
    self = [super init];
    if (self)
        _mockingProgress = [MKTMockingProgress sharedProgress];
    return self;
}

- (MKTOngoingStubbing *)stubAtLocation:(MKTTestLocation)location
{
    [_mockingProgress stubbingStartedAtLocation:location];
    return [self stub];
}

- (MKTOngoingStubbing *)stub
{
    return [_mockingProgress pullOngoingStubbing];
}

- (id)verifyMock:(MKTObjectMock *)mock
        withMode:(id <MKTVerificationMode>)mode
      atLocation:(MKTTestLocation)location
{
    [_mockingProgress verificationStarted:mode atLocation:location];
    return mock;
}

@end
