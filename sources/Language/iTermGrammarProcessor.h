//
//  iTermGrammarProcessor.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/21/18.
//

#import <Foundation/Foundation.h>
#import <CoreParse/CoreParse.h>

// Associates production rules with syntax tree transforms. Combines production
// rules to make numbered BNF. Offers an interface to run a transform block for
// a syntax tree, whose tag gives the index of the rule.
@interface iTermGrammarProcessor : NSObject

// Concatenated rules with each prefixed by a unique number.
@property (nonatomic, readonly) NSString *backusNaurForm;

typedef id (^iTermGrammarProcessorSyntaxTreeTransformBlock)(CPSyntaxTree *);

- (void)addProductionRule:(NSString *)bnf
            treeTransform:(iTermGrammarProcessorSyntaxTreeTransformBlock)transform;

// Calls the block for the rule that matched the root fo this tree and returns
// its value.
- (id)transformSyntaxTree:(CPSyntaxTree *)syntaxTree;

@end
