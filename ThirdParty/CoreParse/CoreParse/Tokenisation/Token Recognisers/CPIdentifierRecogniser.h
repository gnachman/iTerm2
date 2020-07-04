//
//  CPIdentifierTokeniser.h
//  CoreParse
//
//  Created by Tom Davie on 12/02/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPTokenRecogniser.h"

/**
 * The CPIdentifierRecogniser class attempts to recognise identifiers on the input string.
 *
 * Identifiers are sequences of characters which begin with a character in one set, and then may contain many characters in a further set subsequently.
 * 
 * This recogniser produces CPIdentifierTokens.
 */
@interface CPIdentifierRecogniser : NSObject <CPTokenRecogniser>

///---------------------------------------------------------------------------------------
/// @name Creating and Initialising an Identifier Recogniser
///---------------------------------------------------------------------------------------

/**
 * Creates an identifier recogniser that recognises identifiers starting with any english alphabetic character or underscore, and then containing any number of those characters, hyphens, or numeric characters.
 *
 * @return Returns a CPIdentifierRecogniser that recognises C like identifiers.
 *
 * @see identifierRecogniserWithInitialCharacters:identifierCharacters:
 */
+ (id)identifierRecogniser;

/**
 * Creates an identifier recogniser that recognises identifiers starting with any character in initialCharacters, and then containing any number of characters in identifierCharacters.
 *
 * @param initialCharacters The set of characters that the identifier may begin with.
 * @param identifierCharacters The set of characters that the identifier may contain, after its first character.
 * @return Returns a CPIdentifierRecogniser that recognises identifiers based on the input character sets.
 *
 * @see initWithInitialCharacters:identifierCharacters:
 */
+ (id)identifierRecogniserWithInitialCharacters:(NSCharacterSet *)initialCharacters identifierCharacters:(NSCharacterSet *)identifierCharacters;

/**
 * Initialises an identifier recogniser that recognises identifiers starting with any character in initialCharacters, and then containing any number of characters in identifierCharacters.
 *
 * @param initialCharacters The set of characters that the identifier may begin with.
 * @param identifierCharacters The set of characters that the identifier may contain, after its first character.
 * @return Returns the CPIdentifierRecogniser that recognises identifiers based on the input character sets.
 *
 * @see identifierRecogniserWithInitialCharacters:identifierCharacters:
 */
- (id)initWithInitialCharacters:(NSCharacterSet *)initialCharacters identifierCharacters:(NSCharacterSet *)identifierCharacters;

///---------------------------------------------------------------------------------------
/// @name Configuring an Identifier Recogniser
///---------------------------------------------------------------------------------------

/**
 * Specifies the set of characters the recognised identifiers may begin with.
 * 
 * @see identifierCharacters
 */
@property (readwrite,retain) NSCharacterSet *initialCharacters;

/**
 * Specifies the set of characters the recognised identifiers may contain, other than their first character.
 *
 * @see initialCharacters
 */
@property (readwrite,retain) NSCharacterSet *identifierCharacters;

@end
