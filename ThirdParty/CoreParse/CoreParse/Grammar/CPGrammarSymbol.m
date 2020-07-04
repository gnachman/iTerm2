//
//  CPGrammarSymbol.m
//  CoreParse
//
//  Created by Tom Davie on 13/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import "CPGrammarSymbol.h"

@implementation CPGrammarSymbol

@synthesize name;
@synthesize terminal;

+ (id)nonTerminalWithName:(NSString *)name
{
    return [[[self alloc] initWithName:name isTerminal:NO] autorelease];
}

+ (id)terminalWithName:(NSString *)name
{
    return [[[self alloc] initWithName:name isTerminal:YES] autorelease];
}

- (id)initWithName:(NSString *)initName isTerminal:(BOOL)isTerminal;
{
    self = [super init];
    
    if (nil != self)
    {
        [self setName:initName];
        [self setTerminal:isTerminal];
    }
    
    return self;
}

- (id)init
{
    return [self initWithName:@"" isTerminal:NO];
}

#define CPGrammarSymbolNameKey     @"n"
#define CPGrammarSymbolTerminalKey @"t"

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    
    if (nil != self)
    {
        [self setName:[aDecoder decodeObjectForKey:CPGrammarSymbolNameKey]];
        [self setTerminal:[aDecoder decodeBoolForKey:CPGrammarSymbolTerminalKey]];
    }
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:[self name] forKey:CPGrammarSymbolNameKey];
    [aCoder encodeBool:[self isTerminal] forKey:CPGrammarSymbolTerminalKey];
}

- (BOOL)isGrammarSymbol
{
    return YES;
}

- (BOOL)isEqual:(id)object
{
    return ([object isGrammarSymbol] &&
            ((CPGrammarSymbol *)object)->terminal == terminal &&
            [((CPGrammarSymbol *)object)->name isEqualToString:name]);
}

- (BOOL)isEqualToGrammarSymbol:(CPGrammarSymbol *)object
{
    return (object != nil && object->terminal == terminal && [object->name isEqualToString:name]);
}

- (NSUInteger)hash
{
    return [[self name] hash];
}

- (NSString *)description
{
    if ([self isTerminal])
    {
        return [NSString stringWithFormat:@"\"%@\"", [self name]];
    }
    else
    {
        return [NSString stringWithFormat:@"<%@>", [self name]];
    }
}

- (void)dealloc
{
    [name release];
    
    [super dealloc];
}

@end

@implementation NSObject (CPGrammarSymbol)

- (BOOL)isGrammarSymbol
{
    return NO;
}

@end
