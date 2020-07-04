//
//  Term.m
//  CoreParse
//
//  Created by Thomas Davie on 26/06/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import "Term.h"

@implementation Term

@synthesize value;

- (id)initWithSyntaxTree:(CPSyntaxTree *)syntaxTree
{
    self = [super init];
    
    if (nil != self)
    {
        [self setValue:[[(CPNumberToken *)[[syntaxTree children] objectAtIndex:0] number] floatValue]];
    }
    
    return self;
}

@end
