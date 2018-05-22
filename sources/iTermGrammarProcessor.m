//
//  iTermGrammarProcessor.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/21/18.
//

#import "iTermGrammarProcessor.h"

@implementation iTermGrammarProcessor {
    NSMutableArray<NSString *> *_rules;
    NSMutableArray<iTermGrammarProcessorSyntaxTreeTransformBlock> *_blocks;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _rules = [NSMutableArray array];
        _blocks = [NSMutableArray array];
    }
    return self;
}

- (void)addProductionRule:(NSString *)bnf treeTransform:(iTermGrammarProcessorSyntaxTreeTransformBlock)transform {
    NSString *numberedRule = [NSString stringWithFormat:@"%@ %@;", @(_rules.count), bnf];
    [_rules addObject:numberedRule];
    [_blocks addObject:[transform copy]];
}

- (NSString *)backusNaurForm {
    return [_rules componentsJoinedByString:@"\n"];
}

- (id)transformSyntaxTree:(CPSyntaxTree *)syntaxTree {
    NSUInteger tag = [[syntaxTree rule] tag];
    if (tag >= _blocks.count) {
        return nil;
    }
    return _blocks[tag](syntaxTree);
}

@end
