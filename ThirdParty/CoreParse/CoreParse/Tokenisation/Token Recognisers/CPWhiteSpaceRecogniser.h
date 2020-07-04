//
//  CPWhiteSpaceRecogniser.h
//  CoreParse
//
//  Created by Tom Davie on 12/02/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPTokenRecogniser.h"

/**
 * The CPWhiteSpaceRecogniser class attempts to recognise white space on the input string.
 * 
 * This recogniser produces CPWhiteSpaceTokens.
 */
@interface CPWhiteSpaceRecogniser : NSObject <CPTokenRecogniser>

///---------------------------------------------------------------------------------------
/// @name Creating and Initialising a WhiteSpace Recogniser
///---------------------------------------------------------------------------------------

/**
 * Creates a whitespace recogniser.
 *
 * @return Returns a CPWhiteSpaceRecogniser.
 */
+ (id)whiteSpaceRecogniser;

@end
