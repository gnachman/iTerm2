//
//  Grammar.m
//  CoreParse
//
//  Created by Tom Davie on 13/02/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import "CPGrammar.h"
#import "CPGrammarPrivate.h"
#import "CPGrammarInternal.h"

#import "CPTokeniser.h"
#import "CPTokenStream.h"
#import "CPKeywordRecogniser.h"
#import "CPNumberRecogniser.h"
#import "CPWhitespaceRecogniser.h"
#import "CPWhiteSpaceToken.h"
#import "CPQuotedRecogniser.h"
#import "CPIdentifierRecogniser.h"
#import "CPLALR1Parser.h"
#import "CPIdentifierToken.h"
#import "CPQuotedToken.h"
#import "CPNumberToken.h"

#import "CPItem.h"
#import "CPLR1Item.h"

#import "CPRHSItem.h"
#import "CPRHSItem+Private.h"

#import "NSSetFunctional.h"

#import <objc/runtime.h>

@interface CPBNFParserDelegate : NSObject <CPTokeniserDelegate,CPParserDelegate>

@property (readwrite, retain, nonatomic) NSError *err;

@end

@implementation CPBNFParserDelegate

@synthesize err = _err;

- (id)parser:(CPParser *)parser didProduceSyntaxTree:(CPSyntaxTree *)syntaxTree
{
    NSArray *children = [syntaxTree children];
    switch ([[syntaxTree rule] tag])
    {
        case 0:
        {
            NSMutableArray *rules = (NSMutableArray *)[children objectAtIndex:0];
            [rules addObjectsFromArray:[children objectAtIndex:1]];
            return rules;
        }
        case 1:
            return [NSMutableArray arrayWithArray:[children objectAtIndex:0]];
        case 2:
        {
            NSArray *rules = [children objectAtIndex:1];
            for (CPRule *r in rules)
            {
                [r setTag:[[(CPNumberToken *)[children objectAtIndex:0] number] intValue]];
            }
            return rules;
        }
        case 3:
            return [children objectAtIndex:0];
        case 4:
        {
            NSArray *arrs = [children objectAtIndex:2];
            NSMutableArray *rules = [NSMutableArray arrayWithCapacity:[arrs count]];
            for (NSArray *rhs in arrs)
            {
                NSString *name = [(CPIdentifierToken *)[children objectAtIndex:0] identifier];
                Class c = NSClassFromString(name);
                CPRule *rule = nil == c || ![c conformsToProtocol:@protocol(CPParseResult)] ? [CPRule ruleWithName:name rightHandSideElements:rhs] : [CPRule ruleWithName:name rightHandSideElements:rhs representitiveClass:c];
                [rules addObject:rule];
            }
            return rules;
        }
        case 5:
        {
            NSMutableArray *rhs = [children objectAtIndex:0];
            [rhs addObject:[children objectAtIndex:2]];
            return rhs;
        }
        case 6:
        {
            NSMutableArray *rhs = [children objectAtIndex:0];
            [rhs addObject:[NSArray array]];
            return rhs;
        }
        case 7:
            return [NSMutableArray arrayWithObject:[children objectAtIndex:0]];
        case 8:
        {
            NSMutableArray *elements = (NSMutableArray *)[children objectAtIndex:0];
            [elements addObject:[children objectAtIndex:1]];
            return elements;
        }
        case 9:
            return [NSMutableArray arrayWithObject:[children objectAtIndex:0]];
        case 10:
            return [children objectAtIndex:0];
        case 11:
        {
            id i = [children objectAtIndex:2];
            if ([i isRHSItem])
            {
                [(CPRHSItem *)i addTag:[[children objectAtIndex:0] identifier]];
                return i;
            }
            else
            {
                CPRHSItem *newI = [[[CPRHSItem alloc] init] autorelease];
                [newI setAlternatives:[NSArray arrayWithObject:[NSArray arrayWithObject:i]]];
                [newI setRepeats:NO];
                [newI setMayNotExist:NO];
                [newI addTag:[[children objectAtIndex:0] identifier]];
                [newI setShouldCollapse:YES];
                return newI;
            }
        }
        case 12:
            return [children objectAtIndex:0];
        case 13:
        {
            CPRHSItem *i = [[[CPRHSItem alloc] init] autorelease];
            [i setAlternatives:[NSArray arrayWithObject:[NSArray arrayWithObject:[children objectAtIndex:0]]]];
            NSString *symbol = [(CPKeywordToken *)[children objectAtIndex:1] keyword];
            if ([symbol isEqualToString:@"*"])
            {
                [i setRepeats:YES];
                [i setMayNotExist:YES];
            }
            else if ([symbol isEqualToString:@"+"])
            {
                [i setRepeats:YES];
                [i setMayNotExist:NO];
            }
            else
            {
                [i setRepeats:NO];
                [i setMayNotExist:YES];
            }
            return i;
        }
        case 14:
            return [children objectAtIndex:0];
        case 15:
        {
            CPRHSItem *i = [[[CPRHSItem alloc] init] autorelease];
            [i setAlternatives:[children objectAtIndex:1]];
            [i setRepeats:NO];
            [i setMayNotExist:NO];
            return i;
        }
        case 16:
        case 17:
        case 18:
        case 19:
        case 20:
            return [children objectAtIndex:0];
            return [children objectAtIndex:0];
        case 21:
            return [CPGrammarSymbol nonTerminalWithName:[(CPIdentifierToken *)[children objectAtIndex:1] identifier]];
        case 22:
            return [CPGrammarSymbol terminalWithName:[(CPQuotedToken *)[children objectAtIndex:0] content]];
        default:
            return syntaxTree;
    }
}

- (CPRecoveryAction *)parser:(CPParser *)parser didEncounterErrorOnInput:(CPTokenStream *)inputStream expecting:(NSSet *)acceptableTokens
{
    CPToken *t = [inputStream peekToken];
    [self setErr:[NSError errorWithDomain:CPEBNFParserErrorDomain
                                     code:CPErrorCodeCouldNotParseEBNF
                                 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                           [NSString stringWithFormat:@"Could not parse EBNF for grammar.  %ld:%ld: Found %@, Expected %@.", (long)[t lineNumber] + 1, (long)[t columnNumber] + 1, t, acceptableTokens], NSLocalizedDescriptionKey,
                                           nil]]];
    return [CPRecoveryAction recoveryActionStop];
}

- (BOOL)tokeniser:(CPTokeniser *)tokeniser shouldConsumeToken:(CPToken *)token
{
    return YES;
}

- (NSArray *)tokeniser:(CPTokeniser *)tokeniser willProduceToken:(CPToken *)token
{
    if ([token isWhiteSpaceToken])
    {
        return [NSArray array];
    }
    return [NSArray arrayWithObject:token];
}

@end

@implementation CPGrammar

@synthesize start;

+ (id)grammarWithStart:(NSString *)start rules:(NSArray *)rules
{
    return [[[self alloc] initWithStart:start rules:rules] autorelease];
}

- (id)initWithStart:(NSString *)initStart rules:(NSArray *)initRules;
{
    self = [super init];
    
    if (nil != self)
    {
        [self setStart:initStart];
        [self setRules:initRules];
        [self setFollowCache:[NSMutableDictionary dictionary]];
    }
    
    return self;
}

+ (id)grammarWithStart:(NSString *)start backusNaurForm:(NSString *)bnf
{
    return [[[self alloc] initWithStart:start backusNaurForm:bnf] autorelease];
}

+ (id)grammarWithStart:(NSString *)start backusNaurForm:(NSString *)bnf error:(NSError **)error
{
    return [[[self alloc] initWithStart:start backusNaurForm:bnf error:error] autorelease];
}

- (id)initWithStart:(NSString *)initStart backusNaurForm:(NSString *)bnf
{
    NSError *err = nil;
    self = [self initWithStart:initStart backusNaurForm:bnf error:&err];
    if (nil == self)
    {
        NSLog(@"=== Core Parse Error ===");
        NSLog(@"%@", err);
    }
    return self;
}

- (id)initWithStart:(NSString *)initStart backusNaurForm:(NSString *)bnf error:(NSError **)error
{
    CPBNFParserDelegate *del = [[[CPBNFParserDelegate alloc] init] autorelease];
    CPTokeniser *tokeniser = [[[CPTokeniser alloc] init] autorelease];
    [tokeniser addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"::="]];
    [tokeniser addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"@"]];
    [tokeniser addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"<"]];
    [tokeniser addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@">"]];
    [tokeniser addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"("]];
    [tokeniser addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@")"]];
    [tokeniser addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"*"]];
    [tokeniser addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"+"]];
    [tokeniser addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"?"]];
    [tokeniser addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"|"]];
    [tokeniser addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@";"]];
    [tokeniser addTokenRecogniser:[CPNumberRecogniser integerRecogniser]];
    [tokeniser addTokenRecogniser:[CPQuotedRecogniser quotedRecogniserWithStartQuote:@"\"" endQuote:@"\"" escapeSequence:@"\\" name:@"String"]];
    [tokeniser addTokenRecogniser:[CPQuotedRecogniser quotedRecogniserWithStartQuote:@"'" endQuote:@"'" escapeSequence:@"\\" name:@"String"]];
    [tokeniser addTokenRecogniser:[CPIdentifierRecogniser identifierRecogniser]];
    [tokeniser addTokenRecogniser:[CPWhiteSpaceRecogniser whiteSpaceRecogniser]];
    [tokeniser setDelegate:del];
    CPTokenStream *tokenStream = [tokeniser tokenise:bnf];
    
    CPRule *ruleset1 = [CPRule ruleWithName:@"ruleset" rightHandSideElements:[NSArray arrayWithObjects:[CPGrammarSymbol nonTerminalWithName:@"ruleset"], [CPGrammarSymbol nonTerminalWithName:@"rule"], nil] tag:0];
    CPRule *ruleset2 = [CPRule ruleWithName:@"ruleset" rightHandSideElements:[NSArray arrayWithObjects:[CPGrammarSymbol nonTerminalWithName:@"rule"], nil] tag:1];
    
    CPRule *rule1 = [CPRule ruleWithName:@"rule" rightHandSideElements:[NSArray arrayWithObjects:[CPGrammarSymbol terminalWithName:@"Number"], [CPGrammarSymbol nonTerminalWithName:@"unNumbered"], nil] tag:2];
    CPRule *rule2 = [CPRule ruleWithName:@"rule" rightHandSideElements:[NSArray arrayWithObjects:[CPGrammarSymbol nonTerminalWithName:@"unNumbered"], nil] tag:3];
    
    CPRule *unNumbered = [CPRule ruleWithName:@"unNumbered" rightHandSideElements:[NSArray arrayWithObjects:[CPGrammarSymbol terminalWithName:@"Identifier"], [CPGrammarSymbol terminalWithName:@"::="], [CPGrammarSymbol nonTerminalWithName:@"rightHandSide"], [CPGrammarSymbol terminalWithName:@";"], nil] tag:4];
    
    CPRule *rightHandSide1 = [CPRule ruleWithName:@"rightHandSide" rightHandSideElements:[NSArray arrayWithObjects:[CPGrammarSymbol nonTerminalWithName:@"rightHandSide"], [CPGrammarSymbol terminalWithName:@"|"], [CPGrammarSymbol nonTerminalWithName:@"sumset"], nil] tag:5];
    CPRule *rightHandSide2 = [CPRule ruleWithName:@"rightHandSide" rightHandSideElements:[NSArray arrayWithObjects:[CPGrammarSymbol nonTerminalWithName:@"rightHandSide"], [CPGrammarSymbol terminalWithName:@"|"], nil] tag:6];
    CPRule *rightHandSide3 = [CPRule ruleWithName:@"rightHandSide" rightHandSideElements:[NSArray arrayWithObjects:[CPGrammarSymbol nonTerminalWithName:@"sumset"], nil] tag:7];
    
    CPRule *sumset1 = [CPRule ruleWithName:@"sumset" rightHandSideElements:[NSArray arrayWithObjects:[CPGrammarSymbol nonTerminalWithName:@"sumset"], [CPGrammarSymbol nonTerminalWithName:@"taggedRightHandSideItem"], nil] tag:8];
    CPRule *sumset2 = [CPRule ruleWithName:@"sumset" rightHandSideElements:[NSArray arrayWithObjects:[CPGrammarSymbol nonTerminalWithName:@"taggedRightHandSideItem"], nil] tag:9];
    
    CPRule *taggedRightHandSideItem1 = [CPRule ruleWithName:@"taggedRightHandSideItem" rightHandSideElements:[NSArray arrayWithObjects:[CPGrammarSymbol nonTerminalWithName:@"rightHandSideItem"], nil] tag:10];
    CPRule *taggedRightHandSideItem2 = [CPRule ruleWithName:@"taggedRightHandSideItem" rightHandSideElements:[NSArray arrayWithObjects:[CPGrammarSymbol terminalWithName:@"Identifier"], [CPGrammarSymbol terminalWithName:@"@"], [CPGrammarSymbol nonTerminalWithName:@"taggedRightHandSideItem"], nil] tag:11];
    
    CPRule *rightHandSideItem1 = [CPRule ruleWithName:@"rightHandSideItem" rightHandSideElements:[NSArray arrayWithObject:[CPGrammarSymbol nonTerminalWithName:@"unit"]] tag:12];
    CPRule *rightHandSideItem2 = [CPRule ruleWithName:@"rightHandSideItem" rightHandSideElements:[NSArray arrayWithObjects:[CPGrammarSymbol nonTerminalWithName:@"unit"], [CPGrammarSymbol nonTerminalWithName:@"repeatSymbol"], nil] tag:13];
    
    CPRule *unit1 = [CPRule ruleWithName:@"unit" rightHandSideElements:[NSArray arrayWithObject:[CPGrammarSymbol nonTerminalWithName:@"grammarSymbol"]] tag:14];
    CPRule *unit2 = [CPRule ruleWithName:@"unit" rightHandSideElements:[NSArray arrayWithObjects:[CPGrammarSymbol terminalWithName:@"("], [CPGrammarSymbol nonTerminalWithName:@"rightHandSide"], [CPGrammarSymbol terminalWithName:@")"], nil] tag:15];
    
    CPRule *repeatSymbol1 = [CPRule ruleWithName:@"repeatSymbol" rightHandSideElements:[NSArray arrayWithObject:[CPGrammarSymbol terminalWithName:@"*"]] tag:16];
    CPRule *repeatSymbol2 = [CPRule ruleWithName:@"repeatSymbol" rightHandSideElements:[NSArray arrayWithObject:[CPGrammarSymbol terminalWithName:@"+"]] tag:17];
    CPRule *repeatSymbol3 = [CPRule ruleWithName:@"repeatSymbol" rightHandSideElements:[NSArray arrayWithObject:[CPGrammarSymbol terminalWithName:@"?"]] tag:18];
    
    CPRule *grammarSymbol1 = [CPRule ruleWithName:@"grammarSymbol" rightHandSideElements:[NSArray arrayWithObjects:[CPGrammarSymbol nonTerminalWithName:@"nonterminal"], nil] tag:19];
    CPRule *grammarSymbol2 = [CPRule ruleWithName:@"grammarSymbol" rightHandSideElements:[NSArray arrayWithObjects:[CPGrammarSymbol nonTerminalWithName:@"terminal"], nil] tag:20];
    
    CPRule *nonterminal = [CPRule ruleWithName:@"nonterminal" rightHandSideElements:[NSArray arrayWithObjects:[CPGrammarSymbol terminalWithName:@"<"], [CPGrammarSymbol terminalWithName:@"Identifier"], [CPGrammarSymbol terminalWithName:@">"], nil] tag:21];
    
    CPRule *terminal = [CPRule ruleWithName:@"terminal" rightHandSideElements:[NSArray arrayWithObjects:[CPGrammarSymbol terminalWithName:@"String"], nil] tag:22];
    
    CPGrammar *bnfGrammar = [CPGrammar grammarWithStart:@"ruleset" rules:[NSArray arrayWithObjects:ruleset1, ruleset2, rule1, rule2, unNumbered, rightHandSide1, rightHandSide2, rightHandSide3, sumset1, sumset2, taggedRightHandSideItem1, taggedRightHandSideItem2, rightHandSideItem1, rightHandSideItem2, unit1, unit2, repeatSymbol1, repeatSymbol2, repeatSymbol3, grammarSymbol1, grammarSymbol2, nonterminal, terminal, nil]];
    CPParser *parser = [CPLALR1Parser parserWithGrammar:bnfGrammar];
    [parser setDelegate:del];
    
    NSMutableArray *initRules = [parser parse:tokenStream];
    
    if ([del err] != nil)
    {
        if (NULL != error)
        {
            *error = [[[del err] copy] autorelease];
        }
        [self release];
        return nil;
    }
    
    NSError *e = [self checkForMissingNonTerminalsInRules:initRules];
    if (nil != e)
    {
        if (NULL != error)
        {
            *error = e;
        }
        [self release];
        return nil;
    }
    
    NSArray *newRules = [self tidyRightHandSides:initRules error:error];
    if (nil == newRules)
    {
        [self release];
        return nil;
    }
    
    return [self initWithStart:initStart rules:newRules];
}

- (id)init
{
    return [self initWithStart:nil rules:[NSArray array]];
}

#define CPGrammarStartKey @"s"
#define CPGrammarRulesKey @"r"

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    
    if (nil != self)
    {
        [self setStart:[aDecoder decodeObjectForKey:CPGrammarStartKey]];
        [self setRules:[aDecoder decodeObjectForKey:CPGrammarRulesKey]];
    }
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:[self start] forKey:CPGrammarStartKey];
    [aCoder encodeObject:[self rules] forKey:CPGrammarRulesKey];
}

- (void)dealloc
{
    [start release];
    [self setRules:nil];
    
    [super dealloc];
}

- (NSSet *)allRules
{
        return [NSSet setWithArray:[self rules]];
}

- (NSError *)checkForMissingNonTerminalsInRules:(NSArray *)rules
{
    NSMutableSet *definedNonTerminals = [NSMutableSet setWithCapacity:[rules count]];
    for (CPRule *rule in rules)
    {
        [definedNonTerminals addObject:[rule name]];
    }
    
    for (CPRule *rule in rules)
    {
        for (id item in [rule rightHandSideElements])
        {
            if ([item isGrammarSymbol] && ![(CPGrammarSymbol *)item isTerminal] && ![definedNonTerminals containsObject:[(CPGrammarSymbol *)item name]])
            {
                return [NSError errorWithDomain:CPEBNFParserErrorDomain
                                           code:CPErrorCodeUndefinedNonTerminal
                                       userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                                 [NSString stringWithFormat:@"Could not find definition of %@, used in %@", [item name], rule], NSLocalizedDescriptionKey,
                                                 nil]];
            }
            else if ([item isRHSItem])
            {
                NSSet *usedNonTerminals = [(CPRHSItem *)item nonTerminalsUsed];
                if (![usedNonTerminals isSubsetOfSet:definedNonTerminals])
                {
                    NSMutableSet *mutableUsedNonTerminals = [[usedNonTerminals mutableCopy] autorelease];
                    [mutableUsedNonTerminals minusSet:definedNonTerminals];
                    return [NSError errorWithDomain:CPEBNFParserErrorDomain
                                               code:CPErrorCodeUndefinedNonTerminal
                                           userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                                     [NSString stringWithFormat:@"Could not find definition of %@, used in %@", [mutableUsedNonTerminals anyObject], rule], NSLocalizedDescriptionKey,
                                                     nil]];
                }
            }
        }
    }
    
    return nil;
}

- (NSArray *)allNonTerminalNames
{
    return [[self rulesByNonTerminal] allKeys];
}

- (void)addRule:(CPRule *)rule
{
    NSMutableDictionary *rs = [self rulesByNonTerminal];
    NSMutableArray *arr = [rs objectForKey:[rule name]];
    if (nil == arr)
    {
        arr = [NSMutableArray array];
        [rs setObject:arr forKey:[rule name]];
    }
    [arr addObject:rule];
}

- (NSArray *)rulesForNonTerminalWithName:(NSString *)nonTerminal
{
    return [[self rulesByNonTerminal] objectForKey:nonTerminal];
}

- (NSUInteger)hash
{
    return [[self start] hash] ^ [[self rules] hash];
}

- (BOOL)isGrammar
{
    return YES;
}

- (BOOL)isEqual:(id)object
{
    return ([object isGrammar] &&
            [((CPGrammar *)object)->start isEqualToString:start] &&
            [[(CPGrammar *)object rules] isEqualToArray:[self rules]]);
}

@end
