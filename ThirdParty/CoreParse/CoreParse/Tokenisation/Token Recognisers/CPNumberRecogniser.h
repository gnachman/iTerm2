//
//  CPIntegerRecogniser.h
//  CoreParse
//
//  Created by Tom Davie on 12/02/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPTokenRecogniser.h"

/**
 * The CPNumberRecogniser class attempts to recognise integers and floating point numbers in the input string.
 * 
 * Number recognisers can be set up to recognise only integers, only floating point numbers, or both.
 * 
 * This recogniser produces CPNumberTokens.
 */
@interface CPNumberRecogniser : NSObject <CPTokenRecogniser>

///---------------------------------------------------------------------------------------
/// @name Creating and Initialising a Number Recogniser
///---------------------------------------------------------------------------------------

/**
 * Creates a number recogniser that recognises only integers.
 *
 * @return Returns a CPNumberRecogniser that recognises only integers.
 * 
 * @see floatRecogniser
 * @see numberRecogniser
 */
+ (id)integerRecogniser;

/**
 * Creates a number recogniser that recognises only floating point numbers.
 *
 * @return Returns a CPNumberRecogniser that recognises only floating point numbers.
 * 
 * @see integerRecogniser
 * @see numberRecogniser
 */
+ (id)floatRecogniser;

/**
 * Creates a number recogniser that recognises both integers and floating point numbers.
 *
 * @return Returns a CPNumberRecogniser that recognises both integers and floating point numbers.
 * 
 * @see integerRecogniser
 * @see floatRecogniser
 */
+ (id)numberRecogniser;

///---------------------------------------------------------------------------------------
/// @name Configuring a Number Recogniser
///---------------------------------------------------------------------------------------

/**
 * Specifies whether the recogniser should recognise integers.
 *
 * @see recognisesFloats
 */
@property (readwrite,assign) BOOL recognisesInts;

/**
 * Specifies whether the recogniser should recognise floating point numbers.
 *
 * @see recognisesFloats
 */
@property (readwrite,assign) BOOL recognisesFloats;

@end
