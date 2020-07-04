//
//  CPLALR1Parser.m
//  CoreParse
//
//  Created by Tom Davie on 05/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import "CPShiftReduceParserProtectedMethods.h"

#import "CPErrorToken.h"

#import "CPShiftReduceAction.h"
#import "CPShiftReduceState.h"

#import "CPGrammarSymbol.h"

#import "CPRHSItemResult.h"

@interface CPShiftReduceParser ()

- (CPShiftReduceAction *)actionForState:(NSUInteger)state token:(CPToken *)token;
- (NSSet *)acceptableTokenNamesForState:(NSUInteger)state;
- (NSUInteger)gotoForState:(NSUInteger)state rule:(CPRule *)rule;

- (CPRecoveryAction *)error:(CPTokenStream *)tokenStream expecting:(NSSet *)acceptableTokens;

@end

@implementation CPShiftReduceParser

@synthesize actionTable;
@synthesize gotoTable;

- (id)initWithGrammar:(CPGrammar *)grammar
{
    self = [super initWithGrammar:grammar];
    
    if (nil != self)
    {
        BOOL succes = [self constructShiftReduceTables];
        if (!succes)
        {
            [self release];
            return nil;
        }
    }
    
    return self;
}

#define CPShiftReduceParserGrammarKey     @"g"
#define CPShiftReduceParserActionTableKey @"at"
#define CPShiftReduceParserGotoTableKey   @"gt"

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithGrammar:[aDecoder decodeObjectForKey:CPShiftReduceParserGrammarKey]];
    
    if (nil != self)
    {
        [self setActionTable:[aDecoder decodeObjectForKey:CPShiftReduceParserActionTableKey]];
        [self setGotoTable:[aDecoder decodeObjectForKey:CPShiftReduceParserGotoTableKey]];
    }
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:[self grammar]     forKey:CPShiftReduceParserGrammarKey];
    [aCoder encodeObject:[self actionTable] forKey:CPShiftReduceParserActionTableKey];
    [aCoder encodeObject:[self gotoTable]   forKey:CPShiftReduceParserGotoTableKey];
}

- (void)dealloc
{
    [actionTable release];
    [gotoTable release];
    
    [super dealloc];
}

- (BOOL)constructShiftReduceTables
{
    NSLog(@"CPShiftReduceParser is abstract, use one of it's concrete subclasses instead");
    return NO;
}

#define kCPStopParsingException @"CPStopParsingException"

- (id)parse:(CPTokenStream *)tokenStream
{
    @try
    {
        NSMutableArray *stateStack = [NSMutableArray arrayWithObject:[CPShiftReduceState shiftReduceStateWithObject:nil state:0]];
        CPToken *nextToken = [[tokenStream peekToken] retain];
        BOOL hasErrorToken = NO;
        while (1)
        {
            @autoreleasepool
            {
                CPShiftReduceAction *action = [self actionForState:[(CPShiftReduceState *)[stateStack lastObject] state] token:nextToken];
                
                if ([action isShiftAction])
                {
                    [stateStack addObject:[CPShiftReduceState shiftReduceStateWithObject:nextToken state:[action newState]]];
                    if (!hasErrorToken)
                    {
                        [tokenStream popToken];
                    }
                    [nextToken release];
                    nextToken = [[tokenStream peekToken] retain];
                    hasErrorToken = NO;
                }
                else if ([action isReduceAction])
                {
                    CPRule *reductionRule = [action reductionRule];
                    NSUInteger numElements = [[reductionRule rightHandSideElements] count];
                    NSMutableArray *components = [NSMutableArray arrayWithCapacity:numElements];
                    NSRange stateStackRange = NSMakeRange([stateStack count] - numElements, numElements);
                    NSMutableDictionary *tagValues = [NSMutableDictionary dictionary];
                    [stateStack enumerateObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:stateStackRange]
                                                  options:NSEnumerationReverse
                                               usingBlock:^(CPShiftReduceState *state, NSUInteger idx, BOOL *stop)
                     {
                         id o = [state object];
                         if ([o isRHSItemResult])
                         {
                             CPRHSItemResult *r = o;
                             
                             if ([o shouldCollapse])
                             {
                                 NSArray *comps = [r contents];
                                 [components insertObjects:comps atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [comps count])]];
                                 
                                 if ([r tagNames] != nil && [comps count] == 1)
                                 {
                                     for (NSString *tagName in [r tagNames])
                                     {
                                         [tagValues setObject:[comps objectAtIndex:0] forKey:tagName];
                                     }
                                 }
                             }
                             else
                             {
                                 [components insertObject:[r contents] atIndex:0];
                                 if ([r tagNames] != nil)
                                 {
                                     for (NSString *tagName in [r tagNames])
                                     {
                                         [tagValues setObject:[r contents] forKey:tagName];
                                     }
                                 }
                             }
                             
                             [tagValues addEntriesFromDictionary:[r tagValues]];
                         }
                         else
                         {
                             [components insertObject:o atIndex:0];
                         }
                     }];
                    [stateStack removeObjectsInRange:stateStackRange];
                    
                    CPSyntaxTree *tree = [CPSyntaxTree syntaxTreeWithRule:reductionRule children:components tagValues:tagValues];
                    id result = nil;
                    
                    Class c = [reductionRule representitiveClass];
                    if (nil != c)
                    {
                        result = [[(id<CPParseResult>)[c alloc] initWithSyntaxTree:tree] autorelease];
                    }
                    
                    if (nil == result)
                    {
                        result = tree;
                        if (delegateRespondsTo.didProduceSyntaxTree)
                        {
                            result = [[self delegate] parser:self didProduceSyntaxTree:tree];
                        }
                    }
                    
                    NSUInteger newState = [self gotoForState:[(CPShiftReduceState *)[stateStack lastObject] state] rule:reductionRule];
                    [stateStack addObject:[CPShiftReduceState shiftReduceStateWithObject:result state:newState]];
                }
                else if ([action isAccept])
                {
                    [nextToken release];
                    return [(CPShiftReduceState *)[stateStack lastObject] object];
                }
                else
                {
                    CPRecoveryAction *recoveryAction = [self error:tokenStream expecting:[self acceptableTokenNamesForState:[(CPShiftReduceState *)[stateStack lastObject] state]]];
                    if (nil == recoveryAction)
                    {
                        if ([nextToken isErrorToken] && [stateStack count] > 0)
                        {
                            [stateStack removeLastObject];
                        }
                        else
                        {
                            [nextToken release];
                            return nil;
                        }
                    }
                    else
                    {
                        switch ([recoveryAction recoveryType])
                        {
                            case CPRecoveryTypeAddToken:
                                [nextToken release];
                                nextToken = [[recoveryAction additionalToken] retain];
                                hasErrorToken = YES;
                                break;
                            case CPRecoveryTypeRemoveToken:
                                [tokenStream popToken];
                                [nextToken release];
                                nextToken = [[tokenStream peekToken] retain];
                                hasErrorToken = NO;
                                break;
                            case CPRecoveryTypeBail:
                                [NSException raise:kCPStopParsingException format:@""];
                                break;
                            default:
                                break;
                        }
                    }
                }
            }
        }
    }
    @catch (NSException *e)
    {
        if (![[e name] isEqualToString:kCPStopParsingException])
        {
            [e raise];
        }
        return nil;
    }
}

- (CPRecoveryAction *)error:(CPTokenStream *)tokenStream expecting:(NSSet *)acceptableTokens
{
    if (delegateRespondsTo.didEncounterErrorOnInputExpecting)
    {
        return [[self delegate] parser:self didEncounterErrorOnInput:tokenStream expecting:acceptableTokens];
    }
    else if (delegateRespondsTo.didEncounterErrorOnInput)
    {
        return [[self delegate] performSelector:@selector(parser:didEncounterErrorOnInput:) withObject:self withObject:tokenStream];
//        return [[self delegate] parser:self didEncounterErrorOnInput:tokenStream];
    }
    else
    {
        CPToken *t = [tokenStream peekToken];
        NSLog(@"%ld:%ld: parse error.  Expected %@, found %@", (long)[t lineNumber] + 1, (long)[t columnNumber] + 1, acceptableTokens, t);
        return nil;
    }
}

- (CPShiftReduceAction *)actionForState:(NSUInteger)state token:(CPToken *)token
{
    return [[self actionTable] actionForState:state token:token];
}

- (NSSet *)acceptableTokenNamesForState:(NSUInteger)state
{
    return [[self actionTable] acceptableTokenNamesForState:state];
}

- (NSUInteger)gotoForState:(NSUInteger)state rule:(CPRule *)rule
{
    return [[self gotoTable] gotoForState:state rule:rule];
}

@end
