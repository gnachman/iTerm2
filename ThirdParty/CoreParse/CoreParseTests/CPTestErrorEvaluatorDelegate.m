//
//  CPTestErrorEvaluatorDelegate.m
//  CoreParse
//
//  Created by Thomas Davie on 05/02/2012.
//  Copyright (c) 2012 In The Beginning... All rights reserved.
//

#import "CPTestErrorEvaluatorDelegate.h"

@implementation CPTestErrorEvaluatorDelegate

- (id)parser:(CPParser *)parser didProduceSyntaxTree:(CPSyntaxTree *)syntaxTree
{
    CPRule *r = [syntaxTree rule];
    NSArray *c = [syntaxTree children];
    
    switch ([r tag])
    {
        case 0:
        case 2:
            return [c objectAtIndex:0];
        case 1:
        {
            int v1 = [[c objectAtIndex:0] isErrorToken] ? 0.0 : [[c objectAtIndex:0] intValue];
            int v2 = [[c objectAtIndex:2] isErrorToken] ? 0.0 : [[c objectAtIndex:2] intValue];
            return [NSNumber numberWithInt:v1 + v2];
        }
        case 3:
        {
            int v1 = [[c objectAtIndex:0] isErrorToken] ? 1.0 : [[c objectAtIndex:0] intValue];
            int v2 = [[c objectAtIndex:2] isErrorToken] ? 1.0 : [[c objectAtIndex:2] intValue];
            return [NSNumber numberWithInt:v1 * v2];
        }
        case 4:
            return [(CPNumberToken *)[c objectAtIndex:0] number];
        case 5:
            return [c objectAtIndex:1];
        default:
            return syntaxTree;
    }
}

- (CPRecoveryAction *)parser:(CPParser *)parser didEncounterErrorOnInput:(CPTokenStream *)inputStream expecting:(NSSet *)acceptableTokens
{
    return [CPRecoveryAction recoveryActionWithAdditionalToken:[CPErrorToken errorWithMessage:@"Expected expression"]];
}

@end
