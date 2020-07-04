//
//  CPTestEvaluatorDelegate.m
//  CoreParse
//
//  Created by Tom Davie on 12/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import "CPTestEvaluatorDelegate.h"

#import "CPNumberToken.h"

@implementation CPTestEvaluatorDelegate

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
            return [NSNumber numberWithInt:[[c objectAtIndex:0] intValue] + [[c objectAtIndex:2] intValue]];
        case 3:
            return [NSNumber numberWithInt:[[c objectAtIndex:0] intValue] * [[c objectAtIndex:2] intValue]];
        case 4:
            return [(CPNumberToken *)[c objectAtIndex:0] number];
        case 5:
            return [c objectAtIndex:1];
        default:
            return syntaxTree;
    }
}

@end
