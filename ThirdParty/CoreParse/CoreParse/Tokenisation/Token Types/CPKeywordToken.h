//
//  CPKeywordToken.h
//  CoreParse
//
//  Created by Tom Davie on 12/02/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPToken.h"

/**
 * The CPKeywordToken class reperesents a keyword appearing in the input.
 *
 * These tokens can be used to return both language keywords and predetermined operators amongst other things.
 * 
 * These tokens return the keyword name as their name.
 */
@interface CPKeywordToken : CPToken

///---------------------------------------------------------------------------------------
/// @name Creating and Initialising a Keyword Token
///---------------------------------------------------------------------------------------

/**
 * Creates a keyword token with a certain name.
 *
 * @param keyword The name of the keyword found in the input stream.
 * @return Returns a CPKeywordToken representing the specified keyword.
 *
 * @see initWithKeyword:
 */
+ (id)tokenWithKeyword:(NSString *)keyword;

/**
 * Initialises a keyword token with a certain name.
 *
 * @param keyword The name of the keyword found in the input stream.
 * @return Returns a CPKeywordToken representing the specified keyword.
 *
 * @see tokenWithKeyword:
 */
- (id)initWithKeyword:(NSString *)keyword;

///---------------------------------------------------------------------------------------
/// @name Configuring a Keyword Token
///---------------------------------------------------------------------------------------

/**
 * The name of the keyword found in the input stream.
 */
@property (readwrite,copy) NSString *keyword;

@end

@interface NSObject (CPIsKeywordToken)

- (BOOL)isKeywordToken;

@end
