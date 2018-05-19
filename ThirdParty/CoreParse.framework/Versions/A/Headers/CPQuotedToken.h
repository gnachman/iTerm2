//
//  CPQuotedToken.h
//  CoreParse
//
//  Created by Tom Davie on 13/02/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPToken.h"

/**
 * The CPQuotedToken class reperesents a quoted literal appearing in the input.
 * 
 * These tokens return the name specified on their creation as their name.
 */
@interface CPQuotedToken : CPToken

///---------------------------------------------------------------------------------------
/// @name Creating and Initialising a Quoted Literal Token
///---------------------------------------------------------------------------------------

/**
 * Creates a quoted literal token with the quoted literal found in the input.
 *
 * @param content    The string found inside the quotes.
 * @param startQuote The symbol used to quote the content.
 * @param name       The name to use for this token.
 * @return Returns a CPQuotedToken representing the specified quoted literal.
 *
 * @see initWithContent:quoteType:name:
 */
+ (id)content:(NSString *)content quotedWith:(NSString *)startQuote name:(NSString *)name;

/**
 * Initialises a quoted literal token with the quoted literal found in the input.
 *
 * @param content    The string found inside the quotes.
 * @param startQuote The symbol used to quote the content.
 * @param name       The name to use for this token.
 * @return Returns a CPQuotedToken representing the specified quoted literal.
 *
 * @see content:quotedWith:name:
 */
- (id)initWithContent:(NSString *)content quoteType:(NSString *)startQuote name:(NSString *)name;

///---------------------------------------------------------------------------------------
/// @name Configuring a Quoted Literal Token
///---------------------------------------------------------------------------------------

/**
 * The content found inside the quoted literal.
 */
@property (readwrite,copy) NSString *content;

/**
 * The quote used to begin the quoted literal.
 */
@property (readwrite,copy) NSString *quoteType;

@end

@interface NSObject (CPIsQuotedToken)

- (BOOL)isQuotedToken;

@end
