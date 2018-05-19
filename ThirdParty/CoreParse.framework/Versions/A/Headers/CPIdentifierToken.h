//
//  CPIdentifierToken.h
//  CoreParse
//
//  Created by Tom Davie on 12/02/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPToken.h"

/**
 * The CPIdentifierToken class reperesents an identifier appearing in the input.
 * 
 * These tokens return `@"Identifier"` as their name.
 */
@interface CPIdentifierToken : CPToken

///---------------------------------------------------------------------------------------
/// @name Creating and Initialising an Identifier Token
///---------------------------------------------------------------------------------------

/**
 * Creates an identifier token with the identifier found in the input.
 *
 * @param identifier The identifier found in the input stream.
 * @return Returns a CPIdentifierToken representing the specified identifier.
 *
 * @see initWithIdentifier:
 */
+ (id)tokenWithIdentifier:(NSString *)identifier;

/**
 * Initialises an identifier token with the identifier found in the input.
 *
 * @param identifier The identifier found in the input stream.
 * @return Returns a CPIdentifierToken representing the specified identifier.
 *
 * @see tokenWithIdentifier:
 */
- (id)initWithIdentifier:(NSString *)identifier;

///---------------------------------------------------------------------------------------
/// @name Configuring an Identifier Token
///---------------------------------------------------------------------------------------

/**
 * The identifier found in the input stream
 */
@property (readwrite,copy) NSString *identifier;

@end

@interface NSObject (CPIsIdentifierToken)

- (BOOL)isIdentifierToken;

@end

