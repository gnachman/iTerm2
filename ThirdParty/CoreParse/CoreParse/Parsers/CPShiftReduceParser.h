//
//  CPLALR1Parser.h
//  CoreParse
//
//  Created by Tom Davie on 05/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPParser.h"

/**
 * The CPShiftReduceParser is a further abstract class based on CPParser.  This implements the parts of a parser in common between all shift/reduce type parsers.
 *
 * @warning Note that to create a parser you should use one of CPShiftReduceParser's subclasses.
 */
@interface CPShiftReduceParser : CPParser <NSCoding>

@end
