//
//  Parser.h
//  CoreParse
//
//  Created by Tom Davie on 04/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPGrammar.h"
#import "CPSyntaxTree.h"

#import "CPTokenStream.h"
#import "CPRecoveryAction.h"

@class CPParser;

/**
 * The CPParseResult protocol declares a method that a class must implement so that instances can be created as the result of parsing a token stream.
 */
@protocol CPParseResult <NSObject>

/**
 * Returns an object initialised with the contents of a syntax tree.
 * 
 * @param syntaxTree The syntax tree to initialise the object with.
 * 
 * @return An object created using the contents of the syntax tree.
 */
- (id)initWithSyntaxTree:(CPSyntaxTree *)syntaxTree;

@end

/**
 * The delegate of a CPParser must adopt the CPParserDelegate protocol.  This allows you to replace the produced syntax trees with data structures of your choice.
 * 
 * Significant processing can be performed in a parser delegate.  For example, a parser for numeric expressions could replace each syntax tree with an NSNumber representing
 * the resultant value of evaluating the expression.  This would allow you to parse, and compute the result of the expression in one pass.
 */
@protocol CPParserDelegate <NSObject>

@optional

/**
 * Should return an object to replace a produced syntax tree with.
 * 
 * You should not return `nil` from this method.  If you do not wish to change the syntax tree, simply return the same value as you are passed.
 * 
 * @warning Note that it is not guarenteed that this method will be called in the same order as the structures appear in your input stream.
 * 
 * @param parser     The parser which produced the syntax tree.
 * @param syntaxTree The syntax tree the parser has produced.
 * @return An object value to replace the syntax tree with.
 */
- (id)parser:(CPParser *)parser didProduceSyntaxTree:(CPSyntaxTree *)syntaxTree;

/**
 * Called when the parser encounters a token for which it can not shift, reduce or accept.
 * 
 * @param parser           The parser which produced the syntax tree.
 * @param inputStream      The input stream containing the token the parser could not cope with.
 * @return An action to take to recover from the parse error or nil.  If the action is nil, and the problematic token is a CPErrorToken
 *         the parse stack is unwound a step for the parent rule to deal with the error.
 * @bug Warning this method is deprecated, use -parser:didEncounterErrorOnInput:expecting: instead.
 */
- (CPRecoveryAction *)parser:(CPParser *)parser didEncounterErrorOnInput:(CPTokenStream *)inputStream __attribute__((deprecated("use -parser:didEncounterErrorOnInput:expecting: instead.")));

/**
 * Called when the parser encounters a token for which it can not shift, reduce or accept.
 * 
 * @param parser           The parser which produced the syntax tree.
 * @param inputStream      The input stream containing the token the parser could not cope with.
 * @param acceptableTokens A set of token names that would have allowed the parser to continue in its current state.
 * @return An action to take to recover from the parse error or nil.  If the action is nil, and the problematic token is a CPErrorToken
 *         the parse stack is unwound a step for the parent rule to deal with the error.
 */
- (CPRecoveryAction *)parser:(CPParser *)parser didEncounterErrorOnInput:(CPTokenStream *)inputStream expecting:(NSSet *)acceptableTokens;

@end

typedef struct
{
    unsigned int didProduceSyntaxTree:1;
    unsigned int didEncounterErrorOnInput:1;
    unsigned int didEncounterErrorOnInputExpecting:1;
    
} CPParserDelegateResponseCache;

/**
 * The CPParser class allows you to parse token streams.
 *
 * Parsers are built by constructing a grammar, and then using it to create a parser.  The parser delegate may be used to monitor and replace output from the parser.
 *
 * @warning Note that CPParser is an abstract superclass.  Use one of its subclasses to construct your parser.
 */
@interface CPParser : NSObject
{
@protected
    CPParserDelegateResponseCache delegateRespondsTo;
}

///---------------------------------------------------------------------------------------
/// @name Creating and Initialising a Parser
///---------------------------------------------------------------------------------------

/**
 * Creates a parser for a certain grammar.
 *
 * @param grammar The grammar on which to base the parser.
 * @return Returns a parser that parses the input grammar, or nil if no such parser could be created.
 */
+ (id)parserWithGrammar:(CPGrammar *)grammar;

/**
 * Initialises a parser for a certain grammar.
 *
 * @param grammar The grammar on which to base the parser.
 * @return Returns a parser that parses the input grammar, or nil if no such parser could be created.
 */
- (id)initWithGrammar:(CPGrammar *)grammar;

///---------------------------------------------------------------------------------------
/// @name Managing the Delegate 
///---------------------------------------------------------------------------------------

/**
 * The parser's delegate.
 */
@property (readwrite,assign, nonatomic) id<CPParserDelegate> delegate;

///---------------------------------------------------------------------------------------
/// @name Finding out about the parsed Grammar 
///---------------------------------------------------------------------------------------

/**
 * The parser's grammar.
 */
@property (readonly,retain) CPGrammar *grammar;

///---------------------------------------------------------------------------------------
/// @name Parsing a Token Stream.
///---------------------------------------------------------------------------------------

/**
 * Parses an input token stream.
 * 
 * Currently if errors are generated, `nil` is returned and the error Logged using NSLog.  This behaviour may change in the future to return the error in a more usable form.
 *
 * @param tokenStream The token stream to parse.
 * @return Returns the parsed syntax tree for the whole stream or `nil` if the token stream could not be parsed.
 */
- (id)parse:(CPTokenStream *)tokenStream;

@end
