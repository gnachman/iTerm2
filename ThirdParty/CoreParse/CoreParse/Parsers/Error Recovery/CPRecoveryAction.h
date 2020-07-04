//
//  CPRecoveryAction.h
//  CoreParse
//
//  Created by Thomas Davie on 05/02/2012.
//  Copyright (c) 2012 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPToken.h"

typedef enum
{
    CPRecoveryTypeAddToken    = 0,
    CPRecoveryTypeRemoveToken    ,
    CPRecoveryTypeBail
} CPRecoveryType;

/**
 * Represents an action to take to recover from an error.
 */
@interface CPRecoveryAction : NSObject

/**
 * The type of recovery action to take.  May be CPRecoveryTypeAddToken or CPRecoveryTypeRemoveToken.
 */
@property (readwrite, assign) CPRecoveryType recoveryType;

/**
 * The token to insert in the token streem if a CPRecoveryTypeAddToken action is taken.
 */
@property (readwrite, retain) CPToken *additionalToken;

/**
 * Allocates an initialises a new CPRecoveryAction asking the parser to add a new token to the token stream.
 *
 * @param token The token to add to the stream.
 * @return A new recovery action.
 */
+ (id)recoveryActionWithAdditionalToken:(CPToken *)token;

/**
 * Allocates an initialises a new CPRecoveryAction asking the parser to delete an offending token from the token stream.
 *
 * @return A new recovery action.
 */
+ (id)recoveryActionDeletingCurrentToken;

/**
 * Allocates and initialise a new CPRecovery action asking the parser to stop immediately.
 */
+ (id)recoveryActionStop;

/**
 * Initialises a CPRecoveryAction asking the parser to add a new token to the token stream.
 *
 * @param token The token to add to the stream.
 * @return An initialised recovery action.
 */
- (id)initWithAdditionalToken:(CPToken *)token;

/**
 * Initialises a CPRecoveryAction asking the parser to delete an offending token from the token stream.
 *
 * @return An initialised recovery action.
 */
- (id)initWithDeleteAction;

/**
 * Initialises a CPRecoveryAction asking the parser to stop immediately.
 */
- (id)initWithStopAction;

@end
