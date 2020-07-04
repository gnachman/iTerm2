//
//  CPTokenStream.m
//  CoreParse
//
//  Created by Tom Davie on 10/02/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import "CPTokenStream.h"

@interface CPTokenStream ()

@property (readwrite,copy) NSArray *tokens;

- (void)unlockTokenStream;

@end

typedef enum
{
    CPTokenStreamAvailable = 0,
    CPTokenStreamUnavailable
} CPTokenStreamLockCondition;

@implementation CPTokenStream
{
    BOOL isClosed;
    NSMutableArray *tokens;
    NSConditionLock *readWriteLock;
}

+ (id)tokenStreamWithTokens:(NSArray *)tokens
{
    return [[[self alloc] initWithTokens:tokens] autorelease];
}

- (id)initWithTokens:(NSArray *)initTokens
{
    self = [self init];
    
    if (nil != self)
    {
        [self setTokens:[[initTokens mutableCopy] autorelease]];
    }
    
    return self;
}

- (id)init
{
    self = [super init];
    
    if (nil != self)
    {
        isClosed = NO;
        readWriteLock = [[NSConditionLock alloc] initWithCondition:CPTokenStreamUnavailable];
        [self setTokens:[NSMutableArray array]];
    }
    
    return self;
}

- (void)dealloc
{
    [tokens release];
    [readWriteLock release];
    
    [super dealloc];
}

- (CPToken *)peekToken
{
    [readWriteLock lockWhenCondition:CPTokenStreamAvailable];
    CPToken *token = nil;
    
    if ([tokens count] > 0)
    {
        token = [[[tokens objectAtIndex:0] retain] autorelease];
    }
    [readWriteLock unlockWithCondition:CPTokenStreamAvailable];
    
    return token;
}

- (CPToken *)popToken
{
    [readWriteLock lockWhenCondition:CPTokenStreamAvailable];
    CPToken *token = nil;
    if ([tokens count] > 0)
    {
        token = [[[tokens objectAtIndex:0] retain] autorelease];
        [tokens removeObjectAtIndex:0];
    }
    [self unlockTokenStream];
    return token;
}


- (NSArray *)tokens
{
    return [[tokens copy] autorelease];
}

- (void)setTokens:(NSMutableArray *)newTokens
{
    [readWriteLock lock];
    if (tokens != newTokens)
    {
        [tokens release];
        tokens = [newTokens mutableCopy];
    }
    [self unlockTokenStream];
}

- (void)pushToken:(CPToken *)token
{
    [readWriteLock lock];
    [tokens addObject:token];
    [readWriteLock unlockWithCondition:CPTokenStreamAvailable];
}

- (void)pushTokens:(NSArray *)newTokens
{
    [readWriteLock lock];
    [tokens addObjectsFromArray:newTokens];
    [self unlockTokenStream];
}

- (void)closeTokenStream
{
    [readWriteLock lock];
    isClosed = YES;
    [readWriteLock unlockWithCondition:CPTokenStreamAvailable];
}

- (NSString *)description
{
    NSMutableString *desc = [NSMutableString string];
    
    for (CPToken *tok in [self tokens])
    {
        [desc appendFormat:@"%@ ", tok];
    }
    
    return desc;
}

- (void)unlockTokenStream
{
    [readWriteLock unlockWithCondition:isClosed || [tokens count] > 0 ? CPTokenStreamAvailable : CPTokenStreamUnavailable];
}

- (NSUInteger)hash
{
    return [[self tokens] hash];
}

- (BOOL)isTokenStream
{
    return YES;
}

- (BOOL)isEqual:(id)object
{
    return ([object isTokenStream] &&
            [((CPTokenStream *)object)->tokens isEqualToArray:tokens]);
}

@end

@implementation NSObject (CPIsTokenStream)

- (BOOL)isTokenStream
{
    return NO;
}

@end
