//
//  CPNumberToken.h
//  CoreParse
//
//  Created by Tom Davie on 12/02/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPToken.h"

/**
 * The CPNumberToken class reperesents a number appearing in the input.
 * 
 * These tokens return `@"Number"` as their name.
 */
@interface CPNumberToken : CPToken

///---------------------------------------------------------------------------------------
/// @name Creating and Initialising a Number Token
///---------------------------------------------------------------------------------------

/**
 * Creates a number token with the number found in the input.
 *
 * @param number The number found in the input stream.
 * @return Returns a CPNumberToken representing the specified number.
 *
 * @see initWithNumber:
 */
+ (id)tokenWithNumber:(NSNumber *)number;

/**
 * Initialises a number token with the number found in the input.
 *
 * @param number The number found in the input stream.
 * @return Returns a CPNumberToken representing the specified number.
 *
 * @see tokenWithNumber:
 */
- (id)initWithNumber:(NSNumber *)number;

///---------------------------------------------------------------------------------------
/// @name Configuring a Number Token
///---------------------------------------------------------------------------------------

/**
 * The number found in the input stream.
 */
@property (readwrite,copy) NSNumber *number;

@end

@interface NSObject (CPIsNumberToken)

- (BOOL)isNumberToken;

@end
