//
//  CPRule.h
//  CoreParse
//
//  Created by Tom Davie on 05/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 * The CPRule class represents a context free rule.
 *
 * Rules are used to specify how your language is structured - each rule specifies that the non-terminal on their left
 * can be constructed by finding the sequence specified on the right hand side.
 * 
 * Rules are added to CPGrammars to construct a language to parse.
 *
 * During parsing, a CPParser will inform its delegate of which CPRule it has matched to form a reduction.  The tag
 * property is provided to allow you to easily identify which rule has been matched.
 */
@interface CPRule : NSObject <NSCoding>

///---------------------------------------------------------------------------------------
/// @name Creating and Initialising a Rule
///---------------------------------------------------------------------------------------

/**
 * Creates a rule based on a non-terminal name and an array of grammar symbols to make up the right hand side.
 *
 * @param name                  The non-terminal the rule reduces.
 * @param rightHandSideElements An array of CPGrammarSymbols that make up the right hand side of the rule.
 * @return Returns a CPRule based on the right hand side and non-terminal name.
 *
 * @see ruleWithName:rightHandSideElements:tag:
 * @see ruleWithName:rightHandSideElements:representitiveClass:
 * @see initWithName:rightHandSideElements:
 */
+ (id)ruleWithName:(NSString *)name rightHandSideElements:(NSArray *)rightHandSideElements;

/**
 * Creates a rule based on a non-terminal name and an array of grammar symbols to make up the right hand side.
 * Also specifies a tag by which the rule can be identified in a parser delegate
 *
 * @param name                  The non-terminal the rule reduces.
 * @param rightHandSideElements An array of CPGrammarSymbols that make up the right hand side of the rule.
 * @param tag                   A tag to identify the rule by.
 * @return Returns a CPRule based on the right hand side and non-terminal name.
 *
 * @see ruleWithName:rightHandSideElements:
 * @see ruleWithName:rightHandSideElements:representitiveClass:
 * @see initWithName:rightHandSideElements:tag:
 */
+ (id)ruleWithName:(NSString *)name rightHandSideElements:(NSArray *)rightHandSideElements tag:(NSUInteger)tag;

/**
 * Creates a rule based on a non-terminal name and an array of grammar symbols to make up the right hand side.
 * Also specifies the class to allocate to represent this rule.
 *
 * @param name                  The non-terminal the rule reduces.
 * @param rightHandSideElements An array of CPGrammarSymbols that make up the right hand side of the rule.
 * @param representitiveClass   The class used to represent this rule.
 * @return Returns a CPRule based on the right hand side and non-terminal name.
 *
 * @see ruleWithName:rightHandSideElements:
 * @see ruleWithName:rightHandSideElements:tag:
 * @see initWithName:rightHandSideElements:representitiveClass:
 */
+ (id)ruleWithName:(NSString *)name rightHandSideElements:(NSArray *)rightHandSideElements representitiveClass:(Class)representitiveClass;

/**
 * Initialises a rule based on a non-terminal name and an array of grammar symbols to make up the right hand side.
 *
 * @param name                  The non-terminal the rule reduces.
 * @param rightHandSideElements An array of CPGrammarSymbols that make up the right hand side of the rule.
 * @return Returns a CPRule based on the right hand side and non-terminal name.
 *
 * @see initWithName:rightHandSideElements:tag:
 * @see ruleWithName:rightHandSideElements:
 */
- (id)initWithName:(NSString *)name rightHandSideElements:(NSArray *)rightHandSideElements;

/**
 * Initialises a rule based on a non-terminal name and an array of grammar symbols to make up the right hand side.
 * Also specifies a tag by which the rule can be identified in a parser delegate
 *
 * @param name                  The non-terminal the rule reduces.
 * @param rightHandSideElements An array of CPGrammarSymbols that make up the right hand side of the rule.
 * @param tag                   A tag to identify the rule by.
 * @return Returns a CPRule based on the right hand side and non-terminal name.
 *
 * @see initWithName:rightHandSideElements:
 * @see ruleWithName:rightHandSideElements:tag:
 */
- (id)initWithName:(NSString *)name rightHandSideElements:(NSArray *)rightHandSideElements tag:(NSUInteger)tag;

/**
 * Initialises a rule based on a non-terminal name and an array of grammar symbols to make up the right hand side.
 * Also specifies the class to allocate to represent this rule.
 *
 * @param name                  The non-terminal the rule reduces.
 * @param rightHandSideElements An array of CPGrammarSymbols that make up the right hand side of the rule.
 * @param representitiveClass   The class used to represent this rule.
 * @return Returns a CPRule based on the right hand side and non-terminal name.
 *
 * @see initWithName:rightHandSideElements:
 * @see initWithName:rightHandSideElements:tag:
 * @see ruleWithName:rightHandSideElements:representitiveClass:
 */
- (id)initWithName:(NSString *)name rightHandSideElements:(NSArray *)rightHandSideElements representitiveClass:(Class)representitiveClass;

///---------------------------------------------------------------------------------------
/// @name Configuring a Rule
///---------------------------------------------------------------------------------------

/**
 * Specifies the name of the non-terminal this rule describes.
 */
@property (readwrite, retain) NSString *name;

/**
 * Specifies the right hand side of the rule.
 * 
 * Elements of this array must be CPGrammarSymbols.
 */
@property (readwrite, copy  ) NSArray *rightHandSideElements;

/**
 * A tag used to identify the rule in the parser delegate.
 */
@property (readwrite, assign) NSUInteger tag;

/**
 * The class used to represent syntax trees based off this rule.
 */
@property (readwrite, assign) Class representitiveClass;

@end

@interface NSObject (CPIsRule)

- (BOOL)isRule;

@end
