//
//  CPShiftReduceState.m
//  CoreParse
//
//  Created by Tom Davie on 05/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import "CPShiftReduceState.h"

@interface CPShiftReduceState ()

@property (readwrite,retain) NSObject *object;
@property (readwrite,assign) NSUInteger state;

@end

@implementation CPShiftReduceState

@synthesize object;
@synthesize state;

+ (id)shiftReduceStateWithObject:(NSObject *)object state:(NSUInteger)state
{
    return [[[self alloc] initWithObject:object state:state] autorelease];
}

- (id)initWithObject:(NSObject *)initObject state:(NSUInteger)initState
{
    self = [super init];
    
    if (nil != self)
    {
        [self setObject:initObject];
        [self setState:initState];
    }
    
    return self;
}

- (void)dealloc
{
    [object release];
    
    [super dealloc];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<CPShiftReduceState: %@ (%ld)", [self object], (long)[self state]];
}

@end
