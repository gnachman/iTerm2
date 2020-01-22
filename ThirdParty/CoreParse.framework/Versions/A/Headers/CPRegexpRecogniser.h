//
//  CPRegexpRecogniser.h
//  CoreParse
//
//  Created by Francis Chong on 1/22/14.
//  Copyright (c) 2014 Ignition Soft. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CPTokenRecogniser.h"

typedef CPToken* (^CPRegexpKeywordRecogniserMatchHandler)(NSString* tokenString, NSTextCheckingResult* match);

/**
 * The CPRegexpRecogniser class attempts to recognise a specific NSRegularExpression.
 *
 * A regexp recogniser attempts to recognise a regexp.
 *
 * This recogniser produces a token via matchHandler.
 */
@interface CPRegexpRecogniser : NSObject <CPTokenRecogniser>

@property (nonatomic, retain) NSRegularExpression* regexp;

///---------------------------------------------------------------------------------------
/// @name Creating and Initialising a Regexp Keyword Recogniser
///---------------------------------------------------------------------------------------

/**
 * Initialises a Regexp Recogniser to recognise a specific regexp.
 *
 * @param regexp The NSRegularExpression to recognise.
 * @param matchHandler A block that process first match result of the regular expression, and return a CPToken.
 *
 * @return Returns the regexp recogniser initialised to recognise the passed regexp.
 *
 * @see recogniserForRegexp:
 */
- (id)initWithRegexp:(NSRegularExpression *)regexp matchHandler:(CPRegexpKeywordRecogniserMatchHandler)matchHandler;

/**
 * Initialises a Regexp Recogniser to recognise a specific regexp.
 *
 * @param regexp The NSRegularExpression to recognise.
 * @param matchHandler A block that process first match result of the regular expression, and return a CPToken.
 *
 * @return Returns the regexp recogniser initialised to recognise the passed regexp.
 *
 * @see initWithRegexp:
 */
+ (id)recogniserForRegexp:(NSRegularExpression *)regexp matchHandler:(CPRegexpKeywordRecogniserMatchHandler)matchHandler;

@end
