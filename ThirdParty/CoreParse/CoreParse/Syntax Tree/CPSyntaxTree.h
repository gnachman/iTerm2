//
//  CPSyntaxTree.h
//  CoreParse
//
//  Created by Tom Davie on 04/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPRule.h"

/**
 * The CPSyntaxTree class represents a node in a syntax tree.
 * 
 * Syntax trees carry the rule that was matched to create the tree and the child elements that in order match up with the right hand side of the rule.
 */
@interface CPSyntaxTree : NSObject

///---------------------------------------------------------------------------------------
/// @name Creating and Initialising a Syntax Tree
///---------------------------------------------------------------------------------------

/**
 * Creates a syntax tree based on a rule and some child trees.
 *
 * @param nonTerminal The rule that was matched to create this tree node.
 * @param children    The child trees that represent the components of the right hand side of the rule.
 * @return Returns a syntax tree with apropriate children, and matching a specified rule.
 *
 * @bug Warning this method is deprecated, use -syntaxTreeWithRule:children:tagValues: instead.
 * @see syntaxTreeWithRule:children:tagValues
 */
+ (id)syntaxTreeWithRule:(CPRule *)nonTerminal children:(NSArray *)children __attribute__((deprecated("use +syntaxTreeWithRule:children:tagValues: instead.")));

/**
 * Initialises a syntax tree based on a rule and some child trees.
 *
 * @param nonTerminal The rule that was matched to create this tree node.
 * @param children    The child trees that represent the components of the right hand side of the rule.
 * @return Returns a syntax tree with apropriate children, and matching a specified rule.
 *
 * @bug Warning this method is deprecated, use -initWithRule:children:tagValues: instead.
 * @see initWithRule:children:tagValues:
 */
- (id)initWithRule:(CPRule *)nonTerminal children:(NSArray *)children __attribute__((deprecated("use +initWithRule:children:tagValues: instead.")));

/**
 * Creates a syntax tree based on a rule and some child trees.
 *
 * @param nonTerminal The rule that was matched to create this tree node.
 * @param children    The child trees that represent the components of the right hand side of the rule.
 * @param tagValues   The values of each tag beneath the rule.
 * @return Returns a syntax tree with apropriate children, and matching a specified rule.
 *
 * @see initWithRule:children:tagValues:
 */
+ (id)syntaxTreeWithRule:(CPRule *)nonTerminal children:(NSArray *)children tagValues:(NSDictionary *)tagValues;

/**
 * Initialises a syntax tree based on a rule and some child trees.
 *
 * @param nonTerminal The rule that was matched to create this tree node.
 * @param children    The child trees that represent the components of the right hand side of the rule.
 * @param tagValues   The values of each tag beneath the rule.
 * @return Returns a syntax tree with apropriate children, and matching a specified rule.
 *
 * @see syntaxTreeWithRule:children:tagValues
 */
- (id)initWithRule:(CPRule *)nonTerminal children:(NSArray *)children tagValues:(NSDictionary *)tagValues;

///---------------------------------------------------------------------------------------
/// @name Configuring a Syntax Tree
///---------------------------------------------------------------------------------------

/**
 * The rule matched to create this syntax tree.
 */
@property (readonly,retain) CPRule *rule;

/**
 * The children that match the right hand side of the matched rule.
 */
@property (readonly,copy) NSArray *children;

/**
 * The values of any tags found on the right hand side of the rule.
 */
@property (readonly,copy) NSDictionary *tagValues;

/**
 * Returns the value of a specific tag.
 *
 * @param tagName The name of the tag you want the value of.
 * @return The sub syntax tree associated with that tag.
 */
- (id)valueForTag:(NSString *)tagName;

/**
 * Returns the child at a specific index.
 * 
 * @param idx The index of the child you want to retrieve.
 * @return The child at that index.
 */
- (id)childAtIndex:(NSUInteger)idx;

@end

@interface NSObject (CPIsSyntaxTree)

- (BOOL)isSyntaxTree;

@end
