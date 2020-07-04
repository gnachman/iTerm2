//
//  CPGrammarInternal.m
//  CoreParse
//
//  Created by Tom Davie on 04/06/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import "CPGrammarInternal.h"
#import "CPGrammarPrivate.h"

#import "CPRule+Internal.h"

#import "CPItem.h"
#import "CPLR1Item.h"

#import "CPRHSItem.h"
#import "CPRHSItem+Private.h"
#import "CPRHSItemResult.h"

#import "NSSetFunctional.h"

@implementation CPGrammar (CPGrammarInternal)

- (CPGrammar *)augmentedGrammar
{
    return [[[CPGrammar alloc] initWithStart:@"s'"
                                       rules:[[self rules] arrayByAddingObject:[CPRule ruleWithName:@"s'" rightHandSideElements:[NSArray arrayWithObject:[CPGrammarSymbol nonTerminalWithName:[self start]]]]]]
            autorelease];
}

- (NSUInteger)indexOfRule:(CPRule *)rule
{
    return [[self orderedRules] indexOfObject:rule];
}

- (NSString *)description
{
    NSArray *ordered = [self orderedRules];
    NSMutableString *s = [NSMutableString string];
    NSUInteger idx = 0;
    for (CPRule *r in ordered)
    {
        [s appendFormat:@"%3ld %@\n", (long)idx, r];
        idx++;
    }
    
    return s;
}

- (NSSet *)lr0Closure:(NSSet *)i
{
    NSMutableSet *j = [i mutableCopy];
    NSMutableArray *processingQueue = [[j allObjects] mutableCopy];
    
    while ([processingQueue count] > 0)
    {
        CPItem *item = [processingQueue objectAtIndex:0];
        CPGrammarSymbol *nextSymbol = [item nextSymbol];
        if (![nextSymbol isTerminal])
        {
            [[self rulesForNonTerminalWithName:[nextSymbol name]] enumerateObjectsUsingBlock:^(CPRule *rule, NSUInteger ix, BOOL *s)
             {
                 CPItem *newItem = [CPItem itemWithRule:rule position:0];
                 if (![j containsObject:newItem])
                 {
                     [processingQueue addObject:newItem];
                     [j addObject:newItem];
                 }
             }];
        }
        
        [processingQueue removeObjectAtIndex:0];
    }
    
    [processingQueue release];
    
    return [j autorelease];
}

- (NSSet *)lr0GotoKernelWithItems:(NSSet *)i symbol:(CPGrammarSymbol *)symbol
{
    return [[i objectsPassingTest:^ BOOL (CPItem *item, BOOL *stop)
             {
                 return [symbol isEqualToGrammarSymbol:[item nextSymbol]];
             }]
            cp_map:^ id (CPItem *item)
            {
                return [item itemByMovingDotRight];
            }];
}

- (NSArray *)lr0Kernels
{
    CPRule *startRule = [[self rulesForNonTerminalWithName:[self start]] objectAtIndex:0];
    NSSet *initialKernel = [NSSet setWithObject:[CPItem itemWithRule:startRule position:0]];
    NSMutableArray *c = [NSMutableArray arrayWithObject:initialKernel];
    NSMutableArray *processingQueue = [NSMutableArray arrayWithObject:initialKernel];
    
    while ([processingQueue count] > 0)
    {
        NSSet *kernel = [processingQueue objectAtIndex:0];
        NSSet *itemSet = [self lr0Closure:kernel];
        NSSet *validNexts = [itemSet cp_map:^ id (CPItem *item) { return [item nextSymbol]; }];
        
        for (CPGrammarSymbol *s in validNexts)
        {
            NSSet *g = [self lr0GotoKernelWithItems:itemSet symbol:s];
            if (![c containsObject:g])
            {
                [processingQueue addObject:g];
                [c addObject:g];
            }
        }
        
        [processingQueue removeObjectAtIndex:0];
    }
    
    return c;
}

- (NSSet *)lr1Closure:(NSSet *)i
{
    NSMutableSet *j = [i mutableCopy];
    NSMutableArray *processingQueue = [[j allObjects] mutableCopy];
    
    while ([processingQueue count] > 0)
    {
        CPLR1Item *item = (CPLR1Item *)[processingQueue objectAtIndex:0];
        NSArray *followingSymbols = [item followingSymbols];
        CPGrammarSymbol *nextSymbol = [followingSymbols count] > 0 ? [followingSymbols objectAtIndex:0] : nil;
        if (![nextSymbol isTerminal])
        {
            NSArray *rs = [self rulesForNonTerminalWithName:[(CPGrammarSymbol *)nextSymbol name]];
            for (CPRule *r in rs)
            {
                NSArray *afterNext = [followingSymbols subarrayWithRange:NSMakeRange(1, [followingSymbols count] - 1)];
                NSArray *afterNextWithTerminal = [afterNext arrayByAddingObject:[item terminal]];
                NSSet *firstAfterNext = [self first:afterNextWithTerminal];
                for (NSString *o in firstAfterNext)
                {
                    CPLR1Item *newItem = [CPLR1Item lr1ItemWithRule:r position:0 terminal:[CPGrammarSymbol terminalWithName:o]];
                    if (![j containsObject:newItem])
                    {
                        [processingQueue addObject:newItem];
                        [j addObject:newItem];
                    }
                }
            }
        }
        
        [processingQueue removeObjectAtIndex:0];
    }
    
    [processingQueue release];
    
    return [j autorelease];
}

- (NSSet *)lr1GotoKernelWithItems:(NSSet *)i symbol:(CPGrammarSymbol *)symbol
{
    return [[i objectsPassingTest:^ BOOL (CPItem *item, BOOL *stop)
             {
                 return [symbol isEqualToGrammarSymbol:[item nextSymbol]];
             }]
            cp_map:^ id (CPItem *item)
            {
                return [item itemByMovingDotRight];
            }];
}

- (NSSet *)follow:(NSString *)name
{
    NSSet *follows = [[self followCache] objectForKey:name];
    
    if (nil == follows)
    {
        NSMutableSet *f = [NSMutableSet setWithObject:@"EOF"];
        for (CPRule *rule in [self allRules])
        {
            NSArray *rightHandSide = [rule rightHandSideElements];
            NSUInteger numElements = [rightHandSide count];
            [rightHandSide enumerateObjectsUsingBlock:^(CPGrammarSymbol *rhsE, NSUInteger idx, BOOL *s)
             {
                 if (![rhsE isTerminal] && [[rhsE name] isEqualToString:name])
                 {
                     if (idx + 1 < numElements)
                     {
                         NSSet *first = [self first:[rightHandSide subarrayWithRange:NSMakeRange(idx+1, [rightHandSide count] - idx - 1)]];
                         NSSet *firstMinusEmpty = [first objectsPassingTest:^ BOOL (NSString *symbolName, BOOL *fstop)
                                                   {
                                                       return ![symbolName isEqualToString:@""];
                                                   }];
                         [f unionSet:firstMinusEmpty];
                     }
                     else if (![[rule name] isEqualToString:name])
                     {
                         [f unionSet:[self follow:[rule name]]];
                     }
                 }
             }];
        }
        
        follows = f;
        [[self followCache] setObject:f forKey:name];
    }
    
    return follows;
}

- (NSSet *)first:(NSArray *)symbols
{
    NSMutableSet *f = [NSMutableSet set];
    
    for (CPGrammarSymbol *symbol in symbols)
    {
        NSSet *f1 = [self firstSymbol:symbol];
        [f unionSet:f1];
        if (![f1 containsObject:@""])
        {
            break;
        }
    }
    
    return f;
}

- (NSString *)uniqueSymbolNameBasedOnName:(NSString *)name
{
    return [self symbolNameNotInSet:[self allSymbolNames] basedOnName:name];
}

- (NSString *)symbolNameNotInSet:(NSSet *)symbols basedOnName:(NSString *)name
{
    NSString *testName = [[name copy] autorelease];
    while ([symbols containsObject:testName])
    {
        testName = [NSString stringWithFormat:@"_%@", testName];
    }
    
    return testName;
}

- (NSArray *)tidyRightHandSides:(NSArray *)oldRules error:(NSError **)error
{
    NSError *invalidRuleError = [self checkRulesForErrors:oldRules];
    if (nil != invalidRuleError)
    {
        if (NULL != error)
        {
            *error = invalidRuleError;
        }
        return nil;
    }
    
    NSMutableSet *rhsElements = [NSMutableSet set];
    for (CPRule *r in oldRules)
    {
        [rhsElements unionSet:[self collectRHSElementsForNewRules:[r rightHandSideElements]]];
    }
    
    NSDictionary *names = [self nameNewRules:rhsElements withRules:oldRules];
    
    return [self addRHSRules:names toRules:oldRules];
}

- (NSError *)checkRulesForErrors:(NSArray *)rules
{
    NSError *error = nil;
    for (CPRule *rule in rules)
    {
        NSArray *rightHandSide = [rule rightHandSideElements];
        NSMutableSet *tagNames = [NSMutableSet set];
        for (id element in rightHandSide)
        {
            if ([element isRHSItem])
            {
                NSSet *newTagNames = [(CPRHSItem *)element tagNamesWithError:&error];
                if (nil != error)
                {
                    return error;
                }
                NSMutableSet *duplicateTags = [[tagNames mutableCopy] autorelease];
                [duplicateTags intersectSet:newTagNames];
                if ([duplicateTags count] > 0)
                {
                    return [NSError errorWithDomain:CPEBNFParserErrorDomain
                                               code:CPErrorCodeDuplicateTag
                                           userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                                     [NSString stringWithFormat:@"Duplicate tag names %@ in same part of alternative is not allowed in \"%@\".", duplicateTags, rule], NSLocalizedDescriptionKey,
                                                     nil]];
                }
                [tagNames unionSet:newTagNames];
                NSSet *tns = [(CPRHSItem *)element tags];
                if (nil != tns)
                {
                    if ([tagNames intersectsSet:tns])
                    {
                        NSMutableSet *intersection = [[tagNames mutableCopy] autorelease];
                        [intersection intersectSet:tns];
                        return [NSError errorWithDomain:CPEBNFParserErrorDomain
                                                   code:CPErrorCodeDuplicateTag
                                               userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                                         [NSString stringWithFormat:@"Duplicate tag names (%@) in same part of alternative is not allowed in \"%@\".", intersection, rule], NSLocalizedDescriptionKey,
                                                         nil]];
                    }
                    [tagNames unionSet:tns];
                }
            }
        }
    }
    
    return nil;
}

- (NSSet *)collectRHSElementsForNewRules:(NSArray *)rightHandSide
{
    NSMutableSet *ret = [NSMutableSet set];
    for (id element in rightHandSide)
    {
        if ([element isRHSItem])
        {
            [ret addObject:element];
            for (NSArray *contents in [(CPRHSItem *)element alternatives])
            {
                [ret unionSet:[self collectRHSElementsForNewRules:contents]];
            }
        }
    }
    return ret;
}

- (NSDictionary *)nameNewRules:(NSSet *)rhsElements withRules:(NSArray *)oldRules
{
    NSSet *symbolNames = [self symbolNamesInRules:oldRules];
    NSUInteger name = 0;
    NSMutableDictionary *namedRules = [NSMutableDictionary dictionaryWithCapacity:[rhsElements count]];
    for (CPRHSItem *item in rhsElements)
    {
        [namedRules setObject:[self symbolNameNotInSet:symbolNames basedOnName:[NSString stringWithFormat:@"RHS%ld", (long)name]] forKey:item];
        name++;
    }
    return namedRules;
}
         
- (NSArray *)addRHSRules:(NSDictionary *)newRules toRules:(NSArray *)oldRules
{
    NSMutableArray *rules = [[[NSMutableArray alloc] initWithArray:oldRules] autorelease];
    
    Class rhsItemClass = [CPRHSItemResult class];
    for (CPRHSItem *item in newRules)
    {
        NSString *ruleName = [newRules objectForKey:item];
        
        // We never generate a CPRHSItem which both repeats/mayNotExist, and has alternatives
        // Cases where this happens are represented as two CPRHSItems, one inside another
        // Because of this, we can deal with the two cases completely seperately.
        
        if ([[item alternatives] count] == 1)
        {
            CPRule *rule;
            
            if ([item mayNotExist])
            {
                rule = [[[CPRule alloc] initWithName:ruleName rightHandSideElements:[NSArray array]] autorelease];
                [rule setTag:0];
            }
            else
            {
                rule = [[[CPRule alloc] initWithName:ruleName rightHandSideElements:[[item alternatives] objectAtIndex:0]] autorelease];
                [rule setTag:1];
            }
            [rule setShouldCollapse:[item shouldCollapse]];
            [rule setTagNames:[item tags]];
            [rule setRepresentitiveClass:rhsItemClass];
            [rules addObject:rule];
            
            if ([item repeats])
            {
                rule = [[[CPRule alloc] initWithName:ruleName rightHandSideElements:[[[item alternatives] objectAtIndex:0] arrayByAddingObject:[CPGrammarSymbol nonTerminalWithName:ruleName]]] autorelease];
                [rule setTag:2];
            }
            else if ([item mayNotExist])
            {
                rule = [[[CPRule alloc] initWithName:ruleName rightHandSideElements:[[item alternatives] objectAtIndex:0]] autorelease];
                [rule setTag:1];
            }
            else
            {
                rule = nil;
            }
            
            if (nil != rule)
            {
                [rule setShouldCollapse:[item shouldCollapse]];
                [rule setTagNames:[item tags]];
                [rule setRepresentitiveClass:rhsItemClass];
                [rules addObject:rule];
            }
        }
        else
        {
            NSUInteger i = 0;
            for (NSArray *contents in [item alternatives])
            {
                CPRule *rule = [[[CPRule alloc] initWithName:ruleName rightHandSideElements:contents] autorelease];
                [rule setTag:3 + i];
                [rule setRepresentitiveClass:rhsItemClass];
                [rule setShouldCollapse:[item shouldCollapse]];
                [rule setTagNames:[item tags]];
                [rules addObject:rule];
                i++;
            }
        }
    }
    
    for (CPRule *rule in rules)
    {
        NSArray *rhsElements = [rule rightHandSideElements];
        NSMutableArray *newRightHandSideElements = [NSMutableArray arrayWithCapacity:[rhsElements count]];
        for (id element in rhsElements)
        {
            [newRightHandSideElements addObject:[element isRHSItem] ? [CPGrammarSymbol nonTerminalWithName:[newRules objectForKey:element]] : element];
        }
        [rule setRightHandSideElements:newRightHandSideElements];
    }
    
    return rules;
}


@end
