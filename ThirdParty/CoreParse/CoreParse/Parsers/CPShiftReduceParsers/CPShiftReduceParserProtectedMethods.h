//
//  CPShiftReduceParserProtectedMethods.h
//  CoreParse
//
//  Created by Tom Davie on 06/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPShiftReduceParser.h"

#import "CPShiftReduceActionTable.h"
#import "CPShiftReduceGotoTable.h"

@interface CPShiftReduceParser ()

@property (readwrite,retain) CPShiftReduceActionTable *actionTable;
@property (readwrite,retain) CPShiftReduceGotoTable *gotoTable;

- (BOOL)constructShiftReduceTables;

@end
