//
//  CPRecoveryAction.m
//  CoreParse
//
//  Created by Thomas Davie on 05/02/2012.
//  Copyright (c) 2012 In The Beginning... All rights reserved.
//

#import "CPRecoveryAction.h"

@implementation CPRecoveryAction

@synthesize recoveryType;
@synthesize additionalToken;

+ (id)recoveryActionWithAdditionalToken:(CPToken *)token
{
    return [[[self alloc] initWithAdditionalToken:token] autorelease];
}

+ (id)recoveryActionDeletingCurrentToken
{
    return [[[self alloc] initWithDeleteAction] autorelease];
}

+ (id)recoveryActionStop
{
    return [[[self alloc] initWithStopAction] autorelease];
}

- (id)initWithAdditionalToken:(CPToken *)token
{
    self = [super init];
    
    if (nil != self)
    {
        [self setRecoveryType:CPRecoveryTypeAddToken];
        [self setAdditionalToken:token];
    }
    
    return self;
}

- (id)initWithDeleteAction
{
    self = [super init];
    
    if (nil != self)
    {
        [self setRecoveryType:CPRecoveryTypeRemoveToken];
    }
    
    return self;
}

- (id)initWithStopAction
{
    self = [super init];
    
    if (nil != self)
    {
        [self setRecoveryType:CPRecoveryTypeBail];
    }
    
    return self;
}

- (void)dealloc
{
    [additionalToken release];
    
    [super dealloc];
}

@end
