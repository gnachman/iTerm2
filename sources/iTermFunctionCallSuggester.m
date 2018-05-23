//
//  iTermFunctionCallSuggester.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import "iTermFunctionCallSuggester.h"

#import "iTermFunctionCallParser.h"
#import "iTermGrammarProcessor.h"
#import "iTermTruncatedQuotedRecognizer.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

@interface iTermFunctionCallSuggester()<CPParserDelegate, CPTokeniserDelegate>
@end

@implementation iTermFunctionCallSuggester {
    CPTokeniser *_tokenizer;
    CPLR1Parser *_parser;
    NSString *_prefix;
    NSDictionary<NSString *,NSArray<NSString *> *> *_functionSignatures;
    NSArray<NSString *> *_paths;
    iTermGrammarProcessor *_grammarProcessor;
}

- (instancetype)initWithFunctionSignatures:(NSDictionary<NSString *,NSArray<NSString *> *> *)functionSignatures
                                     paths:(NSArray<NSString *> *)paths {
    self = [super init];
    if (self) {
        _functionSignatures = [functionSignatures copy];
        _paths = [paths copy];
        _tokenizer = [iTermFunctionCallParser newTokenizer];
        [_tokenizer addTokenRecogniser:[iTermFunctionCallParser stringRecognizerWithClass:[iTermTruncatedQuotedRecognizer class]]];
        _tokenizer.delegate = self;
        _grammarProcessor = [[iTermGrammarProcessor alloc] init];
        [self loadRulesAndTransforms];

        NSError *error = nil;
        CPGrammar *grammar = [CPGrammar grammarWithStart:@"call"
                                          backusNaurForm:_grammarProcessor.backusNaurForm
                                                   error:&error];
        _parser = [CPSLRParser parserWithGrammar:grammar];
        assert(_parser);
        _parser.delegate = self;
    }
    return self;
}

- (void)loadRulesAndTransforms {
    __weak __typeof(self) weakSelf = self;
    [_grammarProcessor addProductionRule:@"call ::= 'Identifier' <arglist>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [weakSelf callWithName:[syntaxTree.children[0] identifier]
                                                     arglist:syntaxTree.children[1]];
                           }];
    [_grammarProcessor addProductionRule:@"call ::= 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [weakSelf callWithName:@""
                                                     arglist:@{ @"partial-arglist": @YES }];
                           }];
    [_grammarProcessor addProductionRule:@"arglist ::= 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"partial-arglist": @YES };
                           }];
    [_grammarProcessor addProductionRule:@"arglist ::= '(' <args> ')'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"complete-arglist": @YES };
                           }];
    [_grammarProcessor addProductionRule:@"arglist ::= '(' ')'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"complete-arglist": @YES };
                           }];
    [_grammarProcessor addProductionRule:@"arglist ::= '(' <args> 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"partial-arglist": @YES,
                                         @"args": syntaxTree.children[1] };
                           }];
    [_grammarProcessor addProductionRule:@"arglist ::= '(' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"partial-arglist": @YES,
                                         @"args": @[] };
                           }];
    [_grammarProcessor addProductionRule:@"args ::= <arg>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @[ syntaxTree.children[0] ];
                           }];
    [_grammarProcessor addProductionRule:@"args ::= <arg> ',' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @[ syntaxTree.children[0], @"," ];
                           }];
    [_grammarProcessor addProductionRule:@"args ::= <arg> ',' <args>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [@[ syntaxTree.children[0], @"," ] arrayByAddingObjectsFromArray:syntaxTree.children[2]];
                           }];
    [_grammarProcessor addProductionRule:@"arg ::= 'Identifier' ':' <expression>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"identifier": [syntaxTree.children[0] identifier],
                                         @"colon": @YES,
                                         @"expression": syntaxTree.children[2] };
                           }];
    [_grammarProcessor addProductionRule:@"arg ::= 'Identifier' ':' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"identifier": [syntaxTree.children[0] identifier],
                                         @"colon": @YES };
                           }];
    [_grammarProcessor addProductionRule:@"arg ::= 'Identifier' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"identifier": [syntaxTree.children[0] identifier] };
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= <path>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"path": syntaxTree.children[0] };
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= <path> '?'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"path": syntaxTree.children[0],
                                         @"terminated": @YES };
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= 'Number'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"literal": @YES };
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= 'String'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"literal": @YES };
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= <composed_call>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"call": syntaxTree.children[0] };
                           }];
    [_grammarProcessor addProductionRule:@"path ::= 'Identifier'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [syntaxTree.children[0] identifier];
                           }];
    [_grammarProcessor addProductionRule:@"path ::= 'Identifier' '.' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [NSString stringWithFormat:@"%@.", [syntaxTree.children[0] identifier]];
                           }];
    [_grammarProcessor addProductionRule:@"path ::= 'Identifier' '.' <path>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [NSString stringWithFormat:@"%@.%@",
                                       [syntaxTree.children[0] identifier],
                                       syntaxTree.children[1]];
                           }];
    [_grammarProcessor addProductionRule:@"composed_call ::= 'Identifier' <composed_arglist>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [weakSelf callWithName:[syntaxTree.children[0] identifier]
                                                     arglist:syntaxTree.children[1]];
                           }];
    [_grammarProcessor addProductionRule:@"composed_arglist ::= '(' <args> ')'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"complete-arglist": @YES };
                           }];
    [_grammarProcessor addProductionRule:@"composed_arglist ::= '(' <args> 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"partial-arglist": @YES,
                                         @"args": syntaxTree.children[1] };
                           }];
    [_grammarProcessor addProductionRule:@"composed_arglist ::= '(' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"partial-arglist": @YES,
                                         @"args": @[] };
                           }];
    [_grammarProcessor addProductionRule:@"composed_arglist ::= '(' ')'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"complete-arglist": @YES };
                           }];
}

- (NSArray<NSString *> *)suggestionsForString:(NSString *)prefix {
    if ([prefix hasSuffix:@" "]) {
        return @[];
    }
    _prefix = prefix;
    CPTokenStream *tokenStream = [_tokenizer tokenise:prefix];
    NSArray<NSString *> *result = [_parser parse:tokenStream];
    return [result mapWithBlock:^id(NSString *s) {
        return [prefix stringByAppendingString:s];
    }];
}

#pragma mark - Private

- (NSArray<NSString *> *)usedParameterNamesInPartialArgList:(NSArray *)partialArgList {
    return [partialArgList mapWithBlock:^id(id object) {
        if ([object isEqual:@","]) {
            return nil;
        } else {
            NSDictionary *dict = object;
            return [dict[@"identifier"] stringByAppendingString:@":"];
        }
    }];
}

- (NSArray<NSString *> *)argumentNamesForFunction:(NSString *)function {
    return _functionSignatures[function];
}

#pragma mark - Suggestion Generation

- (NSArray<NSString *> *)suggestionsForFunctionName:(NSString *)prefix {
    NSArray<NSString *> *registeredFunctions = _functionSignatures.allKeys;
    return [[registeredFunctions filteredArrayUsingBlock:^BOOL(NSString *anObject) {
        return [anObject hasPrefix:prefix] || prefix.length == 0;
    }] mapWithBlock:^id(NSString *s) {
        NSString *firstArgName  = [[self argumentNamesForFunction:s].firstObject stringByAppendingString:@":"] ?: @")";
        return [NSString stringWithFormat:@"%@(%@",
                [s substringFromIndex:prefix.length],
                firstArgName];
    }];
}

// partialArgList is an array alternating between arg-dicts and @",".
// an arg-dict has an identifier, maybe a colon, and maybe an expression.
- (NSArray<NSString *> *)suggestedNextArgumentForExistingArgs:(NSArray *)partialArgList
                                                     function:(NSString *)function {
    if (partialArgList == nil) {
        // No open paren yet
        return [self suggestionsForFunctionName:function];
    }

    NSArray<NSString *> *usedParameterNames = [self usedParameterNamesInPartialArgList:partialArgList];

    id lastArg = partialArgList.lastObject;
    NSString *prefix;
    if (![lastArg isEqual:@","]) {
        NSDictionary *argDict = lastArg;
        if (argDict[@"colon"]) {
            NSString *nextArgumentName = [[self argumentNamesForFunction:function] objectPassingTest:^BOOL(NSString *element, NSUInteger index, BOOL *stop) {
                return ![usedParameterNames containsObject:[element stringByAppendingString:@":"]];
            }];
            nextArgumentName = [nextArgumentName stringByAppendingString:@":"];
            NSArray *suggestions = [self suggestedExpressions:argDict[@"expression"]
                                             nextArgumentName:nextArgumentName];
            return suggestions;
        }
        prefix = argDict[@"identifier"] ?: @"";
    } else {
        prefix = @"";
    }

    if (lastArg && ![lastArg isEqual:@","]) {
        usedParameterNames = [usedParameterNames arrayByRemovingLastObject];
    }
    return [self suggestedParameterNamesForFunction:function
                                          excluding:usedParameterNames
                                             prefix:prefix];
}

// An expression dictionary is one of
// @{ @"path": @"partial path" }
// @{ @"path": @"complete path", @"terminated": @YES }
// @{ @"literal": @YES }
// @{ @"call": @[ suggestions ] };
- (NSArray<NSString *> *)suggestedExpressions:(NSDictionary *)expression
                             nextArgumentName:(NSString *)nextArgumentName {
    if (expression[@"literal"] || expression[@"terminated"]) {
        return @[];
    } else if (expression[@"call"]) {
        return expression[@"call"];
    } else {
        NSArray<NSString *> *legalPaths = _paths;
        if (nextArgumentName == nil) {
            legalPaths = [legalPaths mapWithBlock:^id(NSString *anObject) {
                return [anObject stringByAppendingString:@")"];
            }];
        } else {
            legalPaths = [legalPaths mapWithBlock:^id(NSString *anObject) {
                return [anObject stringByAppendingFormat:@", %@:", nextArgumentName];
            }];
        }

        NSArray<NSString *> *functionNames = _functionSignatures.allKeys;
        functionNames = [functionNames mapWithBlock:^id(NSString *anObject) {
            NSString *firstArgName  = [self argumentNamesForFunction:anObject].firstObject ?: @")";
            firstArgName = [firstArgName stringByAppendingString:@":"];
            return [anObject stringByAppendingFormat:@"(%@", firstArgName];
        }];

        NSArray<NSString *> *options = [legalPaths arrayByAddingObjectsFromArray:functionNames];
        NSString *prefix = expression[@"path"];
        return [[options filteredArrayUsingBlock:^BOOL(NSString *anObject) {
            return prefix.length == 0 || [anObject hasPrefix:prefix];
        }] mapWithBlock:^id(NSString *s) {
            return [s substringFromIndex:prefix.length];
        }];
    }
}

- (NSArray<NSString *> *)suggestedParameterNamesForFunction:(NSString *)function
                                                  excluding:(NSArray<NSString *> *)exclusions
                                                     prefix:(NSString *)prefix {
    NSArray<NSString *> *legalNames = [[self argumentNamesForFunction:function] mapWithBlock:^id(NSString *anObject) {
        return [anObject stringByAppendingString:@":"];
    }];
    if (!legalNames) {
        return @[];
    }
    NSArray *suggestions = [[legalNames filteredArrayUsingBlock:^BOOL(NSString *anObject) {
        return ![exclusions containsObject:anObject] && (prefix.length == 0 || [anObject hasPrefix:prefix]);
    }] mapWithBlock:^id(NSString *s) {
        return [s substringFromIndex:prefix.length];
    }];
    return suggestions;
}

- (id)callWithName:(NSString *)function arglist:(id)maybeArglistDict {
    NSDictionary *arglist = [NSDictionary castFrom:maybeArglistDict];
    if (arglist[@"partial-arglist"]) {
        return [self suggestedNextArgumentForExistingArgs:arglist[@"args"]
                                                 function:function];
    }
    return @[];
}

#pragma mark - CPTokeniserDelegate

- (BOOL)tokeniser:(CPTokeniser *)tokeniser shouldConsumeToken:(CPToken *)token {
    return YES;
}

- (void)tokeniser:(CPTokeniser *)tokeniser requestsToken:(CPToken *)token pushedOntoStream:(CPTokenStream *)stream {
    if ([token isWhiteSpaceToken]) {
        return;
    }

    [stream pushToken:token];
}

#pragma mark - CPParserDelegate

- (id)parser:(CPParser *)parser didProduceSyntaxTree:(CPSyntaxTree *)syntaxTree {
    return [_grammarProcessor transformSyntaxTree:syntaxTree];
}

- (CPRecoveryAction *)parser:(CPParser *)parser
    didEncounterErrorOnInput:(CPTokenStream *)inputStream
                   expecting:(NSSet *)acceptableTokens {
    if (inputStream.peekToken == nil && [acceptableTokens containsObject:@"EOF"]) {
        return [CPRecoveryAction recoveryActionWithAdditionalToken:[CPEOFToken eof]];
    }
    return [CPRecoveryAction recoveryActionStop];
}

@end

