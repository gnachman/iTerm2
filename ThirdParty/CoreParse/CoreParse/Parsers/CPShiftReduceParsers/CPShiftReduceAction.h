//
//  CPShiftReduceAction.h
//  CoreParse
//
//  Created by Tom Davie on 05/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPRule.h"

#import "CPGrammar.h"

@interface CPShiftReduceAction : NSObject <NSCoding>

+ (id)shiftAction:(NSUInteger)shiftLocation;
+ (id)reduceAction:(CPRule *)reduction;
+ (id)acceptAction;

- (id)initWithShift:(NSUInteger)shiftLocation;
- (id)initWithReductionRule:(CPRule *)reduction;

- (BOOL)isShiftAction;
- (BOOL)isReduceAction;
- (BOOL)isAccept;

- (NSUInteger)newState;
- (CPRule *)reductionRule;

- (NSString *)descriptionWithGrammar:(CPGrammar *)g;

- (BOOL)isEqualToShiftReduceAction:(CPShiftReduceAction *)object;

@end

@interface NSObject (CPIsShiftReduceAction)

- (BOOL)isShiftReduceAction;

@end
