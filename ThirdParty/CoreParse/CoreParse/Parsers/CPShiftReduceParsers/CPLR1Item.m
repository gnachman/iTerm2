//
//  CPLR1Item.m
//  CoreParse
//
//  Created by Tom Davie on 12/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import "CPLR1Item.h"

@interface CPLR1Item ()

@property (readwrite,retain) CPGrammarSymbol *terminal;

@end

@implementation CPLR1Item

@synthesize terminal;

+ (id)lr1ItemWithRule:(CPRule *)rule position:(NSUInteger)position terminal:(CPGrammarSymbol *)terminal
{
    return [[[self alloc] initWithRule:rule position:position terminal:terminal] autorelease];
}

- (id)initWithRule:(CPRule *)rule position:(NSUInteger)position terminal:(CPGrammarSymbol *)initTerminal
{
    self = [super initWithRule:rule position:position];
    
    if (nil != self)
    {
        [self setTerminal:initTerminal];
    }
    
    return self;
}

- (id)initWithRule:(CPRule *)initRule position:(NSUInteger)initPosition
{
    return [self initWithRule:initRule position:initPosition terminal:nil];
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[CPLR1Item allocWithZone:zone] initWithRule:[self rule] position:[self position] terminal:[self terminal]];
}

- (void)dealloc
{
    [terminal release];
    
    [super dealloc];
}

- (BOOL)isLR1Item
{
    return YES;
}

- (BOOL)isEqual:(id)object
{
    return ([object isLR1Item] &&
            [super isEqualToItem:(CPLR1Item *)object] &&
            [((CPLR1Item *)object)->terminal isEqualToGrammarSymbol:terminal]);
}

- (NSUInteger)hash
{
    return [[self rule] hash] ^ [terminal hash] ^ [self position];
}

- (NSString *)description
{
    return [[super description] stringByAppendingFormat:@", %@", [[self terminal] name]];
}

@end

@implementation NSObject(CPIsLR1Item)

- (BOOL)isLR1Item
{
    return NO;
}

@end
