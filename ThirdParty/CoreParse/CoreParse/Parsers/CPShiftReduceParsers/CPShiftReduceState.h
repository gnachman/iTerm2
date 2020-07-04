//
//  CPShiftReduceState.h
//  CoreParse
//
//  Created by Tom Davie on 05/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CPShiftReduceState : NSObject

@property (readonly,retain) NSObject *object;
@property (readonly,assign) NSUInteger state;

+ (id)shiftReduceStateWithObject:(NSObject *)object state:(NSUInteger)state;
- (id)initWithObject:(NSObject *)initObject state:(NSUInteger)initState;

@end
