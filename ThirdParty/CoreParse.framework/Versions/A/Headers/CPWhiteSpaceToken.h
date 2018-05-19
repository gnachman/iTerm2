//
//  CPWhiteSpaceToken.h
//  CoreParse
//
//  Created by Tom Davie on 12/02/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPToken.h"

/**
 * The CPWhiteSpaceToken class reperesents some white space appearing in the input.
 * 
 * These tokens return `@"Whitespace"` as their name.
 */
@interface CPWhiteSpaceToken : CPToken

///---------------------------------------------------------------------------------------
/// @name Creating and Initialising a WhiteSpace Token
///---------------------------------------------------------------------------------------

/**
 * Creates a white space token with the white space found in the input.
 *
 * @param whiteSpace The white space found in the input stream.
 * @return Returns a CPWhiteSpaceToken representing the specified white space.
 *
 * @see initWithWhiteSpace:
 */
+ (id)whiteSpace:(NSString *)whiteSpace;

/**
 * Initialises a white space token with the white space found in the input.
 *
 * @param whiteSpace The white space found in the input stream.
 * @return Returns a CPWhiteSpaceToken representing the specified white space.
 *
 * @see whiteSpace:
 */
- (id)initWithWhiteSpace:(NSString *)whiteSpace;

///---------------------------------------------------------------------------------------
/// @name Configuring a WhiteSpace Token
///---------------------------------------------------------------------------------------

/**
 * The white space string found in the input stream.
 */
@property (readwrite,copy) NSString *whiteSpace;

@end

@interface NSObject (CPIsWhiteSpaceToken)

- (BOOL)isWhiteSpaceToken;

@end
