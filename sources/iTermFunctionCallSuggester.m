//
//  iTermFunctionCallSuggester.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import "iTermFunctionCallSuggester.h"

#import "CPParser+Cache.h"
#import "iTermExpressionParser+Private.h"
#import "iTermGrammarProcessor.h"
#import "iTermSwiftyStringParser.h"
#import "iTermSwiftyStringRecognizer.h"
#import "iTermTruncatedQuotedRecognizer.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"

@interface iTermFunctionCallSuggester()<CPParserDelegate, CPTokeniserDelegate>
@end

@implementation iTermFunctionCallSuggester {
@protected
    CPLALR1Parser *_parser;
    NSDictionary<NSString *,NSArray<NSString *> *> *_functionSignatures;
    NSSet<NSString *> *(^_pathSource)(NSString *prefix);
    NSString *_prefix;
    CPTokeniser *_tokenizer;
    iTermGrammarProcessor *_grammarProcessor;
}

- (instancetype)initWithFunctionSignatures:(NSDictionary<NSString *,NSArray<NSString *> *> *)functionSignatures
                                pathSource:(NSSet<NSString *> *(^)(NSString *prefix))pathSource {
    self = [super init];
    if (self) {
        _functionSignatures = [functionSignatures copy];
        _pathSource = [pathSource copy];
        _tokenizer = [iTermExpressionParser newTokenizer];
        [self addTokenRecognizersToTokenizer:_tokenizer];
        _tokenizer.delegate = self;
        _grammarProcessor = [[iTermGrammarProcessor alloc] init];
        [self loadRulesAndTransforms];

        // NOTE:
        // CPSLRParser is a slightly faster parser but is not capable of dealing with the grammar
        // rules for functions in expressions. You need lookahead to distinguish function calls
        // from paths. "foo.bar(" is a valid beginning for a function call. "foo.bar.baz(" is not
        // because nested namespaces are not allowed. Without lookahead, the SLR parser has a
        // shift-reduce conflict because it can't distinguish
        // "funcname ::= Identifier '.' Identifier" from "path ::= Identifier ['.' path]". The
        // reason a funcname is not a path is that it can only have two parts.
        //
        // See the comments in the headers for the two parsers for more details about their costs.
        _parser = [CPLALR1Parser parserWithBNF:_grammarProcessor.backusNaurForm start:self.grammarStart];
        assert(_parser);
        _parser.delegate = self;
    }
    return self;
}

- (void)addTokenRecognizersToTokenizer:(CPTokeniser *)tokenizer {
    iTermSwiftyStringRecognizer *swiftyRecognizer =
    [[iTermSwiftyStringRecognizer alloc] initWithStartQuote:@"\""
                                                   endQuote:@"\""
                                             escapeSequence:@"\\"
                                              maximumLength:NSNotFound
                                                       name:@"SwiftyString"
                                         tolerateTruncation:YES];

    [iTermExpressionParser setEscapeReplacerInStringRecognizer:swiftyRecognizer];
    [_tokenizer addTokenRecogniser:swiftyRecognizer];
}

- (CPQuotedRecogniser *)stringRecognizer {
    return [iTermExpressionParser stringRecognizerWithClass:[iTermTruncatedQuotedRecognizer class]];
}

- (NSString *)grammarStart {
    return @"call";
}

- (void)loadRulesAndTransforms {
    __weak __typeof(self) weakSelf = self;
    [_grammarProcessor addProductionRule:@"call ::= <funcname> <arglist>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [weakSelf callWithName:syntaxTree.children[0]
                                                     arglist:syntaxTree.children[1]];
                           }];
    [_grammarProcessor addProductionRule:@"call ::= 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [weakSelf callWithName:@""
                                                     arglist:@{ @"partial-arglist": @YES }];
                           }];

    [_grammarProcessor addProductionRule:@"funcname ::= 'Identifier'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [syntaxTree.children[0] identifier];
                           }];
    [_grammarProcessor addProductionRule:@"funcname ::= 'Identifier' '.' 'Identifier'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [NSString stringWithFormat:@"%@.%@",
                                       [syntaxTree.children[0] identifier],
                                       [syntaxTree.children[2] identifier]];
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
    [_grammarProcessor addProductionRule:@"expression ::= <path> '[' 'Number' ']'"
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
    [_grammarProcessor addProductionRule:@"expression ::= 'SwiftyString'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               iTermSwiftyStringToken *token = [iTermSwiftyStringToken castFrom:syntaxTree.children[0]];
                               if (token.truncated && !token.endsWithLiteral) {
                                   return @{ @"truncated_interpolation": token.truncatedPart };
                               } else {
                                   return @{ @"literal": @YES };
                               }
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= <composed_call>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"call": syntaxTree.children[0] };
                           }];

    // Array literals
    [_grammarProcessor addProductionRule:@"expression ::= '[' <comma_delimited_expressions> 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [syntaxTree.children[1] dictionaryBySettingObject:@YES forKey:@"inside-truncated-array-literal"];
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= '[' <comma_delimited_expressions> ']'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"literal": @YES };
                           }];
    [_grammarProcessor addProductionRule:@"comma_delimited_expressions ::= <expression>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[0];
                           }];
    [_grammarProcessor addProductionRule:@"comma_delimited_expressions ::= <expression> ',' <comma_delimited_expressions>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children.lastObject;
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
                                       syntaxTree.children[2]];
                           }];
    [_grammarProcessor addProductionRule:@"composed_call ::= <funcname> <composed_arglist>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [weakSelf callWithName:syntaxTree.children[0]
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
    if (prefix.length == 0) {
        // Zero-prefix suggest. This is a special case to avoid an annoying shift-reduce conflict
        // and because I expect it will need fancier ranking.
        return [self pathsAndFunctionSuggestionsWithPrefix:@"" legalPaths:[_pathSource(@"") allObjects]];
    }
    _prefix = prefix;
    CPTokenStream *tokenStream = [_tokenizer tokenise:prefix];
    id result = [_parser parse:tokenStream];
    return [self parsedResult:result forString:prefix];
}

- (NSArray<NSString *> *)parsedResult:(id)result forString:(NSString *)prefix {
    return [[NSArray castFrom:result] mapWithBlock:^id(NSString *s) {
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
            NSArray *suggestions = [self suggestedExpressions:argDict[@"expression"]
                                             nextArgumentName:nextArgumentName
                                             valuesMustBeArgs:YES];
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
// @{ @"truncated_interpolation": @"truncated expression" }
// @{ @"call": @[ suggestions ] };
- (NSArray<NSString *> *)suggestedExpressions:(NSDictionary *)expression
                             nextArgumentName:(NSString *)nextArgumentName
                             valuesMustBeArgs:(BOOL)valuesMustBeArgs {
    if (expression == nil || expression[@"literal"] || expression[@"terminated"]) {
        return @[];
    } else if (expression[@"call"]) {
        return expression[@"call"];
    } else if (expression[@"truncated_interpolation"]) {
        // Some half-written expression inside an interpolated string. For example:
        //    Foo\(bar(
        // The truncated_interpolation's value would be bar(
        //
        // It could be something nutty like
        //    Foo\(bar("baz\(blatz(
        // The truncated_interpolation's value would be bar("baz\(blatz(
        // A few recursions later you should get suggestions for blatz's arguments.
        iTermFunctionCallSuggester *inner = [[iTermFunctionCallSuggester alloc] initWithFunctionSignatures:_functionSignatures
                                                                                                pathSource:_pathSource];
        return [inner suggestionsForString:expression[@"truncated_interpolation"]];
    } else {
        NSArray<NSString *> *legalPaths = [_pathSource(expression[@"path"]) allObjects];
        const BOOL insideTruncatedArrayLiteral = [expression[@"inside-truncated-array-literal"] boolValue];
        if (valuesMustBeArgs && !insideTruncatedArrayLiteral) {
            if (nextArgumentName == nil) {
                legalPaths = [legalPaths mapWithBlock:^id(NSString *anObject) {
                    if ([anObject hasSuffix:@"."]) {
                        return anObject;
                    }
                    return [anObject stringByAppendingString:@")"];
                }];
            } else {
                legalPaths = [legalPaths mapWithBlock:^id(NSString *anObject) {
                    return [anObject stringByAppendingFormat:@", %@:", nextArgumentName];
                }];
            }
        }
        return [self pathsAndFunctionSuggestionsWithPrefix:expression[@"path"]
                                                legalPaths:legalPaths];
    }
}

- (NSArray<NSString *> *)pathsAndFunctionSuggestionsWithPrefix:(NSString *)prefix
                                                    legalPaths:(NSArray<NSString *> *)legalPaths {
    NSArray<NSString *> *functionNames = _functionSignatures.allKeys;
    functionNames = [functionNames mapWithBlock:^id(NSString *anObject) {
        NSString *firstArgName  = [self argumentNamesForFunction:anObject].firstObject ?: @")";
        firstArgName = [firstArgName stringByAppendingString:@":"];
        return [anObject stringByAppendingFormat:@"(%@", firstArgName];
    }];

    NSArray<NSString *> *options = [legalPaths arrayByAddingObjectsFromArray:functionNames];
    return [[options filteredArrayUsingBlock:^BOOL(NSString *anObject) {
        return prefix.length == 0 || [anObject hasPrefix:prefix];
    }] mapWithBlock:^id(NSString *s) {
        return [s substringFromIndex:prefix.length];
    }];
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

@implementation iTermSwiftyStringSuggester

- (NSString *)grammarStart {
    return @"expression";
}

- (NSArray<NSString *> *)suggestionsForString:(NSString *)prefix {
    if ([prefix hasSuffix:@" "]) {
        return @[];
    }
    _prefix = prefix;

    iTermSwiftyStringParser *parser = [[iTermSwiftyStringParser alloc] initWithString:prefix];
    parser.tolerateTruncation = YES;
    NSInteger index = [parser enumerateSwiftySubstringsWithBlock:nil];
    if (index > prefix.length ||
        index == NSNotFound ||
        !parser.wasTruncated ||
        parser.wasTruncatedInLiteral) {
        return @[];
    }
    NSString *truncatedExpression = [prefix substringFromIndex:index];
    NSArray<NSString *> *undecoratedSuggestions;

    undecoratedSuggestions = [super suggestionsForString:truncatedExpression];
    NSArray<NSString *> *allSuggestions = [undecoratedSuggestions mapWithBlock:^id(NSString *tail) {
        return [prefix stringByAppendingString:tail];
    }];
    NSArray<NSString *> *suggestionsUpToFirstPeriod = [allSuggestions mapWithBlock:^id(NSString *string) {
        NSInteger remaining = string.length;
        remaining -= prefix.length;
        if (remaining <= 0) {
            return nil;
        }
        NSInteger index = [string rangeOfString:@"." options:0 range:NSMakeRange(prefix.length, remaining)].location;
        if (index == NSNotFound) {
            return string;
        } else {
            return [string substringToIndex:index];
        }
    }];
    return [[suggestionsUpToFirstPeriod sortedArrayUsingSelector:@selector(compare:)] reduceWithFirstValue:@[] block:^id(NSArray *uniqueValues, NSString *string) {
        if (uniqueValues.count < 50 &&
            ![NSObject object:uniqueValues.lastObject isEqualToObject:string]) {
            return [uniqueValues arrayByAddingObject:string];
        } else {
            return uniqueValues;
        }
    }];
}

- (NSArray<NSString *> *)parsedResult:(id)result forString:(NSString *)prefix {
    NSArray<NSString *> *suggestions = [self suggestedExpressions:[NSDictionary castFrom:result]
                                                 nextArgumentName:nil
                                                 valuesMustBeArgs:NO];
    return suggestions;
}

@end

