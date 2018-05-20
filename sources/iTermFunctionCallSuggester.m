//
//  iTermFunctionCallSuggester.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import "iTermFunctionCallSuggester.h"

#import "iTermFunctionCallParser.h"
#import "iTermTruncatedQuotedRecognizer.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

typedef NS_ENUM(NSInteger, iTermFunctionCallSuggesterRule) {
    iTermFunctionCallSuggesterRuleCallIsIdentifierArglist,

    iTermFunctionCallSuggesterRuleArglistIsEOF,
    iTermFunctionCallSuggesterRuleArglistIsParenArgsParen,
    iTermFunctionCallSuggesterRuleArglistIsParenParen,
    iTermFunctionCallSuggesterRuleArglistIsParenArgsEOF,
    iTermFunctionCallSuggesterRuleArglistIsParenEOF,

    iTermFunctionCallSuggesterRuleArgsIsArg,
    iTermFunctionCallSuggesterRuleArgsIsArgCommaEOF,
    iTermFunctionCallSuggesterRuleArgsIsArgCommaArgs,

    iTermFunctionCallSuggesterRuleArgIsIdentifierColonExpression,
    iTermFunctionCallSuggesterRuleArgIsIdentifierColonEOF,
    iTermFunctionCallSuggesterRuleArgIsIdentifierEOF,

    iTermFunctionCallSuggesterRuleExpressionIsPath,
    iTermFunctionCallSuggesterRuleExpressionIsPathQuestionmark,
    iTermFunctionCallSuggesterRuleExpressionIsNumber,
    iTermFunctionCallSuggesterRuleExpressionIsString,
    iTermFunctionCallSuggesterRuleExpressionIsComposedCall,

    iTermFunctionCallSuggesterRulePathIsIdentifier,
    iTermFunctionCallSuggesterRulePathIsIdentifierDotEOF,
    iTermFunctionCallSuggesterRulePathIsIdentifierDotPath,

    iTermFunctionCallSuggesterRuleComposedcallIsIdentifierComposedarglist,

    iTermFunctionCallSuggesterRuleComposedarglistIsParenArgsParen,
    iTermFunctionCallSuggesterRuleComposedarglistIsParenArgsEOF,
    iTermFunctionCallSuggesterRuleComposedarglistIsParenEOF,
    iTermFunctionCallSuggesterRuleComposedarglistIsParenParen
};

@interface iTermFunctionCallSuggester()<CPParserDelegate, CPTokeniserDelegate>
@end

@implementation iTermFunctionCallSuggester {
    CPTokeniser *_tokenizer;
    CPLR1Parser *_parser;
    NSString *_prefix;
    NSDictionary<NSString *,NSArray<NSString *> *> *_functionSignatures;
    NSArray<NSString *> *_paths;
}

NSString *iTermNumberedBNFStringForDictionary(NSDictionary<NSNumber *, NSString *> *dict) {
    NSArray<NSNumber *> *sortedKeys = [dict.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSArray<NSString *> *entries = [sortedKeys mapWithBlock:^id(NSNumber *key) {
        return [NSString stringWithFormat:@"%-2d %@;", key.intValue, dict[key]];
    }];
    return [entries componentsJoinedByString:@"\n"];
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

        NSDictionary *bnfDict =
        @{
          @(iTermFunctionCallSuggesterRuleCallIsIdentifierArglist):
              @"call       ::= 'Identifier' <arglist>",
          @(iTermFunctionCallSuggesterRuleArglistIsEOF):
              @"arglist    ::= 'EOF'",
          @(iTermFunctionCallSuggesterRuleArglistIsParenArgsParen):
              @"arglist    ::= '(' <args> ')'",
          @(iTermFunctionCallSuggesterRuleArglistIsParenParen):
              @"arglist    ::= '(' ')'",
          @(iTermFunctionCallSuggesterRuleArglistIsParenArgsEOF):
              @"arglist    ::= '(' <args> 'EOF'",
          @(iTermFunctionCallSuggesterRuleArglistIsParenEOF):
              @"arglist    ::= '(' 'EOF'",
          @(iTermFunctionCallSuggesterRuleArgsIsArg):
              @"args       ::= <arg>",
          @(iTermFunctionCallSuggesterRuleArgsIsArgCommaEOF):
              @"args       ::= <arg> ',' 'EOF'",
          @(iTermFunctionCallSuggesterRuleArgsIsArgCommaArgs):
              @"args       ::= <arg> ',' <args>",
          @(iTermFunctionCallSuggesterRuleArgIsIdentifierColonExpression):
              @"arg        ::= 'Identifier' ':' <expression>",
          @(iTermFunctionCallSuggesterRuleArgIsIdentifierColonEOF):
              @"arg        ::= 'Identifier' ':' 'EOF'",
          @(iTermFunctionCallSuggesterRuleArgIsIdentifierEOF):
              @"arg        ::= 'Identifier' 'EOF'",
          @(iTermFunctionCallSuggesterRuleExpressionIsPath):
              @"expression ::= <path>",
          @(iTermFunctionCallSuggesterRuleExpressionIsPathQuestionmark):
              @"expression ::= <path> '?'",
          @(iTermFunctionCallSuggesterRuleExpressionIsNumber):
              @"expression ::= 'Number'",
          @(iTermFunctionCallSuggesterRuleExpressionIsString):
              @"expression ::= 'String'",
          @(iTermFunctionCallSuggesterRuleExpressionIsComposedCall):
              @"expression ::= <composed_call>",
          @(iTermFunctionCallSuggesterRulePathIsIdentifier):
              @"path       ::= 'Identifier'",
          @(iTermFunctionCallSuggesterRulePathIsIdentifierDotEOF):
              @"path       ::= 'Identifier' '.' 'EOF'",
          @(iTermFunctionCallSuggesterRulePathIsIdentifierDotPath):
              @"path       ::= 'Identifier' '.' <path>",
          @(iTermFunctionCallSuggesterRuleComposedcallIsIdentifierComposedarglist):
              @"composed_call ::= 'Identifier' <composed_arglist>",
          @(iTermFunctionCallSuggesterRuleComposedarglistIsParenArgsParen):
              @"composed_arglist ::= '(' <args> ')'",
          @(iTermFunctionCallSuggesterRuleComposedarglistIsParenArgsEOF):
              @"composed_arglist ::= '(' <args> 'EOF'",
          @(iTermFunctionCallSuggesterRuleComposedarglistIsParenEOF):
              @"composed_arglist ::= '(' 'EOF'",
          @(iTermFunctionCallSuggesterRuleComposedarglistIsParenParen):
              @"composed_arglist ::= '(' ')'"
          };
        NSString *bnf = iTermNumberedBNFStringForDictionary(bnfDict);

        NSError *error = nil;
        CPGrammar *grammar = [CPGrammar grammarWithStart:@"call"
                                          backusNaurForm:bnf
                                                   error:&error];
        _parser = [CPLR1Parser parserWithGrammar:grammar];
        _parser.delegate = self;
    }
    return self;
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
        return [anObject hasPrefix:prefix];
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
                return ![usedParameterNames containsObject:element];
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
    NSArray *children = [syntaxTree children];
    switch ([[syntaxTree rule] tag]) {
        case iTermFunctionCallSuggesterRuleCallIsIdentifierArglist: {  // call ::= 'Identifier' <arglist>
            return [self callWithName:[children[0] identifier] arglist:children[1]];
        }

        case iTermFunctionCallSuggesterRuleArglistIsEOF:  // arglist ::= 'EOF'
            return @{ @"partial-arglist": @YES };

        case iTermFunctionCallSuggesterRuleArglistIsParenArgsParen:  // arglist ::= '(' <args> ')'
        case iTermFunctionCallSuggesterRuleArglistIsParenParen:  // arglist ::= '(' ')'
        case iTermFunctionCallSuggesterRuleComposedarglistIsParenArgsParen:  // composed_arglist ::= '(' <args> ')'
        case iTermFunctionCallSuggesterRuleComposedarglistIsParenParen:  // composed_arglist ::= '(' ')'
            return @{ @"complete-arglist": @YES };

        case iTermFunctionCallSuggesterRuleArglistIsParenArgsEOF:  // arglist ::= '(' <args> 'EOF'
        case iTermFunctionCallSuggesterRuleComposedarglistIsParenArgsEOF:  // composed_arglist ::= '(' <args> 'EOF'
            return @{ @"partial-arglist": @YES,
                      @"args": children[1] };

        case iTermFunctionCallSuggesterRuleArglistIsParenEOF:  // arglist ::= '(' 'EOF'
        case iTermFunctionCallSuggesterRuleComposedarglistIsParenEOF:  // composed_arglist ::= '(' 'EOF'
            return @{ @"partial-arglist": @YES,
                      @"args": @[] };

        case iTermFunctionCallSuggesterRuleArgsIsArg:  // args ::= <arg>
            return @[ children[0] ];

        case iTermFunctionCallSuggesterRuleArgsIsArgCommaEOF:  // args ::= <arg> ',' 'EOF'
            return @[ children[0], @"," ];

        case iTermFunctionCallSuggesterRuleArgsIsArgCommaArgs:  // args ::= <arg> ',' <args>
            return [@[ children[0], @"," ] arrayByAddingObjectsFromArray:children[2]];

        case iTermFunctionCallSuggesterRuleArgIsIdentifierColonExpression:  // arg ::= 'Identifier' ':' <expression>
            return @{ @"identifier": [children[0] identifier],
                      @"colon": @YES,
                      @"expression": children[2] };

        case iTermFunctionCallSuggesterRuleArgIsIdentifierColonEOF:  // arg ::= 'Identifier' ':' 'EOF'
            return @{ @"identifier": [children[0] identifier],
                      @"colon": @YES };

        case iTermFunctionCallSuggesterRuleArgIsIdentifierEOF:  // arg ::= 'Identifier' 'EOF'
            return @{ @"identifier": [children[0] identifier] };

        case iTermFunctionCallSuggesterRuleExpressionIsPath:  // expression ::= <path>
            // Note that this expression, when path lacks a ., could be the start of a composed call
            // TODO
            return @{ @"path": children[0] };

        case iTermFunctionCallSuggesterRuleExpressionIsPathQuestionmark:  // expression ::= <path> '?'
            return @{ @"path": children[0],
                      @"terminated": @YES };

        case iTermFunctionCallSuggesterRuleExpressionIsNumber:  // expression ::= 'Number'
            return @{ @"literal": @YES };

        case iTermFunctionCallSuggesterRuleExpressionIsString:  // expression ::= 'String'
            return @{ @"literal": @YES };

        case iTermFunctionCallSuggesterRuleExpressionIsComposedCall:  // expression ::= <composed_call>
            return @{ @"call": children[0] };

        case iTermFunctionCallSuggesterRulePathIsIdentifier:  // path ::= 'Identifier'
            return [children[0] identifier];

        case iTermFunctionCallSuggesterRulePathIsIdentifierDotEOF:  // path ::= 'Identifier' '.' 'EOF'
            return [NSString stringWithFormat:@"%@.", [children[0] identifier]];

        case iTermFunctionCallSuggesterRulePathIsIdentifierDotPath:  // path ::= 'Identifier' '.' <path>
            return [NSString stringWithFormat:@"%@.%@", [children[0] identifier], children[1]];

        case iTermFunctionCallSuggesterRuleComposedcallIsIdentifierComposedarglist:  // composed_call ::= 'Identifier' '<arglist>'
            return [self callWithName:[children[0] identifier] arglist:children[1]];
    }
    return nil;
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

