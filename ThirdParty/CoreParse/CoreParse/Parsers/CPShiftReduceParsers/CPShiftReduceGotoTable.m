//
//  CPShiftReduceGotoTable.m
//  CoreParse
//
//  Created by Tom Davie on 05/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import "CPShiftReduceGotoTable.h"


@implementation CPShiftReduceGotoTable
{
    NSMutableDictionary **table;
    NSUInteger capacity;
}

- (id)initWithCapacity:(NSUInteger)initCapacity
{
    self = [super init];
    
    if (nil != self)
    {
        capacity = initCapacity;
        table = malloc(capacity * sizeof(NSMutableDictionary *));
        for (NSUInteger buildingState = 0; buildingState < capacity; buildingState++)
        {
            table[buildingState] = [[NSMutableDictionary alloc] init];
        }
    }
    
    return self;
}

#define CPShiftReduceGotoTableTableKey @"t"

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    
    if (nil != self)
    {
        NSArray *rows = [aDecoder decodeObjectForKey:CPShiftReduceGotoTableTableKey];
        capacity = [rows count];
        table = malloc(capacity * sizeof(NSMutableDictionary *));
        [rows getObjects:table range:NSMakeRange(0, capacity)];
        for (NSUInteger i = 0; i < capacity; i++)
        {
            [table[i] retain];
        }
    }
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:[NSArray arrayWithObjects:table count:capacity] forKey:CPShiftReduceGotoTableTableKey];
}

- (void)dealloc
{
    for (NSUInteger state = 0; state < capacity; state++)
    {
        [table[state] release];
    }
    free(table);
    
    [super dealloc];
}

- (BOOL)setGoto:(NSUInteger)gotoIndex forState:(NSUInteger)state nonTerminalNamed:(NSString *)nonTerminalName
{
    NSMutableDictionary *row = table[state];
    if (nil != [row objectForKey:nonTerminalName] && [[row objectForKey:nonTerminalName] unsignedIntegerValue] != gotoIndex)
    {
        return NO;
    }
    [row setObject:[NSNumber numberWithUnsignedInteger:gotoIndex] forKey:nonTerminalName];
    return YES;
}

- (NSUInteger)gotoForState:(NSUInteger)state rule:(CPRule *)rule
{
    return [(NSNumber *)[table[state] objectForKey:[rule name]] unsignedIntegerValue];
}

@end
