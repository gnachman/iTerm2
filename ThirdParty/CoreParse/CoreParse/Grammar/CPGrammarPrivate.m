//
//  CPGrammarPrivate.m
//  CoreParse
//
//  Created by Tom Davie on 04/06/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import "CPGrammarPrivate.h"

#import <objc/runtime.h>

@implementation CPGrammar (CPGrammarPrivate)

static char rulesByNonTerminalKey;
static char followCacheKey;

- (NSMutableDictionary *)rulesByNonTerminal
{
    return (NSMutableDictionary *)objc_getAssociatedObject(self, &rulesByNonTerminalKey);
}

- (void)setRulesByNonTerminal:(NSMutableDictionary *)newRulesByNonTerminal
{
    objc_setAssociatedObject(self, &rulesByNonTerminalKey, newRulesByNonTerminal, OBJC_ASSOCIATION_RETAIN);
}

- (NSMutableDictionary *)followCache
{
    return (NSMutableDictionary *)objc_getAssociatedObject(self, &followCacheKey);
}

- (void)setFollowCache:(NSMutableDictionary *)newFollowCache
{
    objc_setAssociatedObject(self, &followCacheKey, newFollowCache, OBJC_ASSOCIATION_RETAIN);
}

- (NSArray *)rules
{
    NSMutableArray *rs = [NSMutableArray arrayWithCapacity:[[self rulesByNonTerminal] count]];
    
    for (NSArray *arr in [[self rulesByNonTerminal] allValues])
    {
        [rs addObjectsFromArray:arr];
    }
    
    return rs;
}

- (void)setRules:(NSArray *)newRules
{
    @synchronized(self)
    {
        [self setRulesByNonTerminal:[NSMutableDictionary dictionaryWithCapacity:[newRules count]]];
        
        for (CPRule *rule in newRules)
        {
            [self addRule:rule];
        }
    }
}

- (NSArray *)orderedRules
{
    return [[[self allRules] allObjects] sortedArrayUsingComparator:^ NSComparisonResult (CPRule *r1, CPRule *r2)
            {
                NSComparisonResult t = [r1 tag] < [r2 tag] ? NSOrderedDescending : [r1 tag] > [r2 tag] ? NSOrderedAscending: NSOrderedSame;
                NSComparisonResult r = NSOrderedSame != t ? t : [[r1 name] compare:[r2 name]];
                return NSOrderedSame != r ? r : ([[r1 rightHandSideElements] count] < [[r2 rightHandSideElements] count] ? NSOrderedAscending : ([[r1 rightHandSideElements] count] > [[r2 rightHandSideElements] count] ? NSOrderedDescending : NSOrderedSame));
            }];
    
}

- (NSSet *)firstSymbol:(CPGrammarSymbol *)sym
{
    NSString *name = [sym name];
    if ([sym isTerminal] && nil != name)
    {
        return [NSSet setWithObject:name];
    }
    else
    {
        NSMutableSet *f = [NSMutableSet set];
        NSArray *rs = [self rulesForNonTerminalWithName:name];
        BOOL containsEmptyRightHandSide = NO;
        for (CPRule *rule in rs)
        {
            NSArray *rhs = [rule rightHandSideElements];
            NSUInteger numElements = [rhs count];
            if (numElements == 0)
            {
                containsEmptyRightHandSide = YES;
            }
            else
            {
                for (CPGrammarSymbol *symbol in rhs)
                {
                    if (![symbol isEqual:sym])
                    {
                        NSSet *f1 = [self firstSymbol:symbol];
                        [f unionSet:f1];
                        if (![f1 containsObject:@""])
                        {
                            break;
                        }
                    }
                }
            }
        }
        if (containsEmptyRightHandSide)
        {
            [f addObject:@""];
        }
        return f;
    }
}

- (NSSet *)allSymbolNames
{
    return [self symbolNamesInRules:[self rules]];
}

- (NSSet *)symbolNamesInRules:(NSArray *)rules
{
    NSMutableSet *symbols = [NSMutableSet set];
    
    for (CPRule *rule in rules)
    {
        [symbols addObject:[rule name]];
        for (id sym in [rule rightHandSideElements])
        {
            if ([sym isGrammarSymbol])
            {
                [symbols addObject:[sym name]];
            }
        }
    }
    
    return symbols;
}

@end
