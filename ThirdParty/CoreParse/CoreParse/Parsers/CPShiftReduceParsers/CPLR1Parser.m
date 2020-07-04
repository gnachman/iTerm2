//
//  CPLR1Parser.m
//  CoreParse
//
//  Created by Tom Davie on 12/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import "CPLR1Parser.h"

#import "CPShiftReduceParserProtectedMethods.h"

#import "CPLR1Item.h"
#import "NSSetFunctional.h"

#import "CPShiftReduceAction.h"

#import "CPGrammarInternal.h"

@interface CPLR1Parser ()

- (BOOL)constructShiftReduceTables;

- (NSArray *)kernelsForGrammar:(CPGrammar *)aug;

@end

@implementation CPLR1Parser

- (BOOL)constructShiftReduceTables
{
    CPGrammar *aug = [[self grammar] augmentedGrammar];
    NSArray *kernels = [self kernelsForGrammar:aug];
    NSUInteger itemCount = [kernels count];
    NSArray *allNonTerminalNames = [[self grammar] allNonTerminalNames];
    NSString *startSymbol = [aug start];
    
    [self setActionTable:[[[CPShiftReduceActionTable alloc] initWithCapacity:itemCount] autorelease]];
    [self setGotoTable:  [[[CPShiftReduceGotoTable   alloc] initWithCapacity:itemCount] autorelease]];
    
    NSUInteger idx = 0;
    for (NSSet *kernel in kernels)
    {
        NSSet *itemsSet = [aug lr1Closure:kernel];
        for (CPLR1Item *item in itemsSet)
        {
            CPGrammarSymbol *next = [item nextSymbol];
            if (nil == next)
            {
                if ([[[item rule] name] isEqualToString:startSymbol])
                {
                    BOOL success = [[self actionTable] setAction:[CPShiftReduceAction acceptAction] forState:idx name:@"EOF"];
                    if (!success)
                    {
                        return NO;
                    }
                }
                else
                {
                    BOOL success = [[self actionTable] setAction:[CPShiftReduceAction reduceAction:[item rule]] forState:idx name:[[item terminal] name]];
                    if (!success)
                    {
                        return NO;
                    }
                }
            }
            else if ([next isTerminal])
            {
                NSSet *g = [aug lr1GotoKernelWithItems:itemsSet symbol:next];
                NSUInteger ix = [kernels indexOfObject:g];
                BOOL success = [[self actionTable] setAction:[CPShiftReduceAction shiftAction:ix] forState:idx name:[next name]];
                if (!success)
                {
                    return NO;
                }
            }
        }
        
        for (NSString *nonTerminalName in allNonTerminalNames)
        {
            NSSet *g = [aug lr1GotoKernelWithItems:itemsSet symbol:[CPGrammarSymbol nonTerminalWithName:nonTerminalName]];
            NSUInteger gotoIndex = [kernels indexOfObject:g];
            BOOL success = [[self gotoTable] setGoto:gotoIndex forState:idx nonTerminalNamed:nonTerminalName];
            if (!success)
            {
                return NO;
            }
        }

        idx++;
    }
        
    return YES;
}

- (NSArray *)kernelsForGrammar:(CPGrammar *)aug
{
    CPRule *startRule = [[aug rulesForNonTerminalWithName:[aug start]] objectAtIndex:0];
    NSSet *initialKernel = [NSSet setWithObject:[CPLR1Item lr1ItemWithRule:startRule position:0 terminal:[CPGrammarSymbol terminalWithName:@"EOF"]]];
    NSMutableArray *c = [NSMutableArray arrayWithObject:initialKernel];
    NSMutableArray *processingQueue = [NSMutableArray arrayWithObject:initialKernel];
    
    while ([processingQueue count] > 0)
    {
        NSSet *kernels = [processingQueue objectAtIndex:0];
        NSSet *itemSet = [aug lr1Closure:kernels];
        NSSet *validNexts = [itemSet cp_map:^ id (CPItem *item)
                             {
                                 return [item nextSymbol];
                             }];
        
        for (CPGrammarSymbol *s in validNexts)
        {
            NSSet *g = [aug lr1GotoKernelWithItems:itemSet symbol:s];
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

@end
