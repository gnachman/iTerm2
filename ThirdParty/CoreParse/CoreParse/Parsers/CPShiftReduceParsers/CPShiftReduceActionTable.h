//
//  CPShiftReduceActionTable.h
//  CoreParse
//
//  Created by Tom Davie on 05/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

@class CPShiftReduceAction;

#import "CPToken.h"
#import "CPGrammar.h"

@interface CPShiftReduceActionTable : NSObject <NSCoding>
{}

- (id)initWithCapacity:(NSUInteger)capacity;

- (BOOL)setAction:(CPShiftReduceAction *)action forState:(NSUInteger)state name:(NSString *)token;

- (CPShiftReduceAction *)actionForState:(NSUInteger)state token:(CPToken *)token;
- (NSSet *)acceptableTokenNamesForState:(NSUInteger)state;

- (NSString *)descriptionWithGrammar:(CPGrammar *)g;

@end
