//
//  CPToken.h
//  CoreParse
//
//  Created by Tom Davie on 12/02/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 * The CPToken class reperesents a token in the token stream.
 * 
 * All tokens respond to the -name message which is used to identify the token while parsing.
 *
 * CPToken is an abstract class.  CPTokenRegnisers should add instances of CPTokens concrete subclasses to their token stream.
 */
@interface CPToken : NSObject

/**
 * The token name.
 */
@property (readonly) NSString *name;

/**
 * The line on which the token can be found.
 */
@property (readwrite, assign) NSUInteger lineNumber;

/**
 * The column on which the token can be found.
 */
@property (readwrite, assign) NSUInteger columnNumber;

/**
 * The index in the input string of the first character in this token.
 */
@property (readwrite, assign) NSUInteger characterNumber;

/**
 * The character length of the token.
 */
@property (readwrite, assign) NSUInteger length;

@end

@interface NSObject (CPIsToken)

- (BOOL)isToken;

@end
