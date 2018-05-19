//
//  CPTokenRecogniser.h
//  CoreParse
//
//  Created by Tom Davie on 10/02/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPToken.h"

/**
 * The CPTokenRecogniser protocol defines methods needed to recognise tokens in a string.
 */
@protocol CPTokenRecogniser <NSObject, NSCoding>

@required
/**
 * Attempts to recognise a token at tokenPosition in tokenString.
 * 
 * If a token is successfully recognised, it should be returned, and tokenPosition advanced to after the consumed characters.
 * If no valid token is found `nil` must be returned instead, and tokenPosition left unchanged.
 * 
 * @param tokenString The string in which to recognise tokens.
 * @param tokenPosition The position at which to try to find the token.  On output, the position after the recognised token.
 * @return Returns the token recognised.
 */
- (CPToken *)recogniseTokenInString:(NSString *)tokenString currentTokenPosition:(NSUInteger *)tokenPosition;

@end
