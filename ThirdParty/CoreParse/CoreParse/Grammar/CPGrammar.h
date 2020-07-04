//
//  Grammar.h
//  CoreParse
//
//  Created by Tom Davie on 13/02/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPGrammarSymbol.h"
#import "CPRule.h"

#define CPEBNFParserErrorDomain @"CPEBNFParserErrorDomain"

typedef enum
{
    CPErrorCodeCouldNotParseEBNF    = 1,
    CPErrorCodeDuplicateTag         = 2,
    CPErrorCodeUndefinedNonTerminal = 3,
} CPErrorCode;

/**
 * The CPGrammar class represents a context free grammar.  Grammars can be used later to construct parsers.
 */
@interface CPGrammar : NSObject <NSCoding>

///---------------------------------------------------------------------------------------
/// @name Creating and Initialising a Grammar
///---------------------------------------------------------------------------------------

/**
 * Creates a grammar based on a starting non-terminal and a list of rules.
 *
 * @param start The non-terminal that all parses must reduce to.
 * @param rules An array of CPRules to describe the grammar.
 * @return Returns a CPGrammar based on the rules and starting non-terminal.
 *
 * @see initWithStart:rules:
 * @see grammarWithStart:backusNaurForm:
 */
+ (id)grammarWithStart:(NSString *)start rules:(NSArray *)rules;

/**
 * Creates a grammar based on a starting non-terminal and some backus naur form.
 *
 * see initWithStart:backusNaurForm: for a description of the syntax used for BNF.
 * 
 * @param start The non-terminal that all parses must reduce to.
 * @param bnf   BNF for the grammar.
 * @return Returns a CPGrammar based on the BNF and starting non-terminal.
 *
 * @bug Warning this method is deprecated, use -grammarWithStart:backusNaurForm:error: instead.
 * @see grammarWithStart:backusNaurForm:error:
 */
+ (id)grammarWithStart:(NSString *)start backusNaurForm:(NSString *)bnf __attribute__((deprecated("will simply print any errors that occur, use +grammarWithStart:backusNaurForm:error: instead")));

/**
 * Creates a grammar based on a starting non-terminal and some backus naur form.
 *
 * see initWithStart:backusNaurForm: for a description of the syntax used for BNF.
 *
 * @param start The non-terminal that all parses must reduce to.
 * @param bnf   BNF for the grammar.
 * @param error A pointer to an error object which will be filled if the method returns nil.
 * @return Returns a CPGrammar based on the BNF and starting non-terminal.
 *
 * @see initWithStart:backusNaurForm:
 */
+ (id)grammarWithStart:(NSString *)start backusNaurForm:(NSString *)bnf error:(NSError **)error;

/**
 * Initialises a grammar based on a starting non-terminal and a list of rules.
 *
 * @param start The non-terminal that all parses must reduce to.
 * @param rules An array of CPRules to describe the grammar.
 * @return Returns a CPGrammar based on the rules and starting non-terminal.
 *
 * @see grammarWithStart:rules:
 * @see initWithStart:backusNaurForm:
 */
- (id)initWithStart:(NSString *)start rules:(NSArray *)rules;

/**
 * Initialises a grammar based on a starting non-terminal and some backus naur form.
 *
 * The BNF is expressed using rules in the form `nonTerminal ::= <subNonTerminal> "subTerminal" <subNonTerminal>;`.  Rules may optionally be prefixed with a number indicating their tag.
 * This allows you to quickly construct grammars in a readable form.
 * You may also use EBNF to construct grammars.  This allows you to use the symbols "*", "+", and "?" to indicate that a construction may appear 0 or more; 1 or more; and 0 or 1 times respectively.
 * You may also parenthesise subrules.
 * 
 * When you use any of the above EBNF constructs or parentheses, the parser will return the contents in an NSArray.
 *
 * You may use tags to identify sections of rules to be extracted in your result classes or parser delegate.  To do this, use the syntax `nonTerminal ::= foo@<subNonTerminal> bar@"subTerminal";`.  You may use multiple tags to identify the same section of a rule.  For example `range ::= min@'Number' '-' max@'Number' | min@'Number' '-' | '-' max@'Number' | min@max@'Number'`.
 * 
 * The grammar used for parsing the BNF can be expressed as follows:
 * 
 * <pre>
 * ruleset                 ::= &lt;rule&gt;+;
 *
 * rule                    ::= "Number"? &lt;unNumbered&gt;;
 *
 * unNumbered              ::= "Identifier" "::=" &lt;rightHandSide&gt; ";";
 *
 * rightHandSide           ::= (&lt;sumset&gt; "|")* &lt;sumset&gt;?;
 *
 * sumset                  ::= &lt;taggedRightHandSideItem&gt;+;
 *
 * taggedRightHandSideItem ::= ("Identifier" "@")? &lt;rightHandSideItem&gt;;
 *
 * rightHandSideItem       ::= &lt;unit&gt; &lt;repeatSymbol&gt;?;
 *
 * unit                    ::= &lt;gramarSymbol&gt; | "(" &lt;rightHandSide&gt; ")";
 *
 * repeatSymbol            ::= "*" | "+" | "?";
 *
 * grammarSymbol           ::= &lt;nonTerminal&gt; | &lt;terminal&gt;;
 *
 * nonTerminal             ::= "&lt;" "Identifier" "&gt;";
 *
 * terminal                ::= "String";
 * </pre>
 *
 * @param start The non-terminal that all parses must reduce to.
 * @param bnf   BNF for the grammar.
 * @return Returns a CPGrammar based on the BNF and starting non-terminal.
 *
 * @bug Warning this method is deprecated, use -initWithStart:backusNaurForm:error: instead.
 * @see initWithStart:backusNaurForm:error:
 */
- (id)initWithStart:(NSString *)start backusNaurForm:(NSString *)bnf __attribute__((deprecated("will simply print any errors that occur, use -initWithStart:backusNaurForm:error: instead")));

/**
 * Initialises a grammar based on a starting non-terminal and some backus naur form.
 *
 * The BNF is expressed using rules in the form `nonTerminal ::= <subNonTerminal> "subTerminal" <subNonTerminal>;`.  Rules may optionally be prefixed with a number indicating their tag.
 * This allows you to quickly construct grammars in a readable form.
 * You may also use EBNF to construct grammars.  This allows you to use the symbols "*", "+", and "?" to indicate that a construction may appear 0 or more; 1 or more; and 0 or 1 times respectively.
 * You may also parenthesise subrules.
 *
 * When you use any of the above EBNF constructs or parentheses, the parser will return the contents in an NSArray.
 *
 * You may use tags to identify sections of rules to be extracted in your result classes or parser delegate.  To do this, use the syntax `nonTerminal ::= foo@<subNonTerminal> bar@"subTerminal";`.  You may use multiple tags to identify the same section of a rule.  For example `range ::= min@'Number' '-' max@'Number' | min@'Number' '-' | '-' max@'Number' | min@max@'Number'`.
 *
 * The grammar used for parsing the BNF can be expressed as follows:
 *
 * <pre>
 * ruleset                 ::= &lt;rule&gt;+;
 *
 * rule                    ::= "Number"? &lt;unNumbered&gt;;
 *
 * unNumbered              ::= "Identifier" "::=" &lt;rightHandSide&gt; ";";
 *
 * rightHandSide           ::= (&lt;sumset&gt; "|")* &lt;sumset&gt;?;
 *
 * sumset                  ::= &lt;taggedRightHandSideItem&gt;+;
 *
 * taggedRightHandSideItem ::= ("Identifier" "@")? &lt;rightHandSideItem&gt;;
 *
 * rightHandSideItem       ::= &lt;unit&gt; &lt;repeatSymbol&gt;?;
 *
 * unit                    ::= &lt;gramarSymbol&gt; | "(" &lt;rightHandSide&gt; ")";
 *
 * repeatSymbol            ::= "*" | "+" | "?";
 *
 * grammarSymbol           ::= &lt;nonTerminal&gt; | &lt;terminal&gt;;
 *
 * nonTerminal             ::= "&lt;" "Identifier" "&gt;";
 *
 * terminal                ::= "String";
 * </pre>
 *
 * @param start The non-terminal that all parses must reduce to.
 * @param bnf   BNF for the grammar.
 * @param error A pointer to an error object which will be filled if the method returns nil.
 * @return Returns a CPGrammar based on the BNF and starting non-terminal.
 *
 * @see initWithStart:rules:
 * @see grammarWithStart:backusNaurForm:
 */
- (id)initWithStart:(NSString *)start backusNaurForm:(NSString *)bnf error:(NSError **)error;

///---------------------------------------------------------------------------------------
/// @name Configuring a Grammar
///---------------------------------------------------------------------------------------

/**
 * The set of rules in the grammar.
 * 
 * @return Returns the set of rules used to describe the grammar.
 */
- (NSSet *)allRules;

/**
 * Adds a rule to the grammar.
 * 
 * @param rule The rule to add.
 */
- (void)addRule:(CPRule *)rule;

///---------------------------------------------------------------------------------------
/// @name Retreiving Grammar Rules
///---------------------------------------------------------------------------------------

/**
 * All the non-terminals that the grammar can expand.
 *
 * @return An array of non-terminal names that are explained by the grammar.
 */
- (NSArray *)allNonTerminalNames;

/**
 * The rules relevant when attempting to match a non-terminal.
 *
 * @param nonTerminalName The name of the non-terminal to find rules to match.
 * @return Returns all rules that match a particular non-terminal.
 */
- (NSArray *)rulesForNonTerminalWithName:(NSString *)nonTerminalName;

/**
 * The starting symbol for the grammar.
 */
@property (readwrite,retain) NSString *start;

@end
