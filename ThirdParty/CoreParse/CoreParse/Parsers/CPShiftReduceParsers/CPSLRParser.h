//
//  CPSLRParser.h
//  CoreParse
//
//  Created by Tom Davie on 06/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPShiftReduceParser.h"

/**
 * The CPSLRParser class is a concrete implementation of CPParser based on the simple left-to-right parsing method.
 * 
 * The SLR parser is the fastest parser type available in CoreParse, but covers the smallest set of grammars.
 */
@interface CPSLRParser : CPShiftReduceParser

@end
