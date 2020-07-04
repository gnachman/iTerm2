//
//  CPLALR1Parser.h
//  CoreParse
//
//  Created by Tom Davie on 03/04/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPLR1Parser.h"

/**
 * The CPLALR1Parser class is a concrete implementation of CPParser based on the lookahead left-to-right parsing method with a one symbol lookahead.
 * 
 * The LALR1 parser is almost as fast as the SLR parser and covers almost as many grammars as the LR1 parser.  LALR1 parsers consume only as much memory as SLR parsers.
 */
@interface CPLALR1Parser : CPShiftReduceParser

@end
