//
//  CPKeywordRecogniser.h
//  CoreParse
//
//  Created by Tom Davie on 12/02/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPTokenRecogniser.h"
#import "CPKeywordToken.h"

/**
 * The CPKeywordRecogniser class attempts to recognise a specific keyword in a token stream.
 * 
 * A keyword recogniser attempts to recognise a specific word or set of symbols.
 * Keyword recognisers can also check that the keyword is not followed by specific characters in order to stop it recognising the beginnings of words.
 * 
 * This recogniser produces CPKeywordTokens.
 */
@interface CPKeywordRecogniser : NSObject <CPTokenRecogniser>

///---------------------------------------------------------------------------------------
/// @name Creating and Initialising a Keyword Recogniser
///---------------------------------------------------------------------------------------

/**
 * Creates a Keyword Recogniser for a specific keyword.
 * 
 * @param keyword The keyword to recognise.
 *
 * @return Returns a keyword recogniser for the passed keyword.
 *
 * @see initWithKeyword:
 * @see recogniserForKeyword:invalidFollowingCharacters:
 */
+ (id)recogniserForKeyword:(NSString *)keyword;

/**
 * Creates a Keyword Recogniser for a specific keyword.
 * 
 * @param keyword The keyword to recognise.
 * @param invalidFollowingCharacters A set of characters that may not follow the keyword in the string being tokenised.
 *
 * @return Returns a keyword recogniser for the passed keyword.
 *
 * @see recogniserForKeyword:
 * @see initWithKeyword:invalidFollowingCharacters:
 */
+ (id)recogniserForKeyword:(NSString *)keyword invalidFollowingCharacters:(NSCharacterSet *)invalidFollowingCharacters;

/**
 * Initialises a Keyword Recogniser to recognise a specific keyword.
 * 
 * @param keyword The keyword to recognise.
 *
 * @return Returns the keyword recogniser initialised to recognise the passed keyword.
 *
 * @see recogniserForKeyword:
 * @see initWithKeyword:invalidFollowingCharacters:
 */
- (id)initWithKeyword:(NSString *)keyword;

/**
 * Initialises a Keyword Recogniser to recognise a specific keyword.
 * 
 * @param keyword The keyword to recognise.
 * @param invalidFollowingCharacters A set of characters that may not follow the keyword in the string being tokenised.
 *
 * @return Returns the keyword recogniser initialised to recognise the passed keyword.
 *
 * @see initWithKeyword:
 * @see recogniserForKeyword:invalidFollowingCharacters:
 */
- (id)initWithKeyword:(NSString *)keyword invalidFollowingCharacters:(NSCharacterSet *)invalidFollowingCharacters;

///---------------------------------------------------------------------------------------
/// @name Configuring a Keyword Recogniser
///---------------------------------------------------------------------------------------

/**
 * The keyword that the recogniser should attempt to recognise.
 */
@property (readwrite,retain,nonatomic) NSString *keyword;

/**
 * A set of characters that may not follow the keyword.
 */
@property (readwrite,retain,nonatomic) NSCharacterSet *invalidFollowingCharacters;

@end
