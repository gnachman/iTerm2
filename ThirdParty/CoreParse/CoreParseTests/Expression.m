//
//  Expression.m
//  CoreParse
//
//  Created by Thomas Davie on 26/06/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import "Expression.h"

#import "Term.h"

@implementation Expression

@synthesize value;

- (id)initWithSyntaxTree:(CPSyntaxTree *)syntaxTree
{
    self = [self init];
    
    if (nil != self)
    {
        NSArray *components = [syntaxTree children];
        if ([components count] == 1)
        {
            [self setValue:[(Term *)[components objectAtIndex:0] value]];
        }
        else
        {
            [self setValue:[(Expression *)[components objectAtIndex:0] value] + [(Term *)[components objectAtIndex:2] value]];
        }
    }
    
    return self;
}

@end
