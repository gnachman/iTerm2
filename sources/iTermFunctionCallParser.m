//
//  iTermFunctionCallParser.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import "iTermFunctionCallParser.h"

#import "iTermGrammarProcessor.h"
#import "iTermScriptFunctionCall.h"
#import "iTermScriptFunctionCall+Private.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

@implementation iTermFunctionCallParser {
    @protected
    CPTokeniser *_tokenizer;
    CPParser *_parser;
    id (^_source)(NSString *);
    NSError *_error;
    NSString *_input;
    iTermGrammarProcessor *_grammarProcessor;
}

+ (id<CPTokenRecogniser>)stringRecognizerWithClass:(Class)theClass {
    CPQuotedRecogniser *stringRecogniser = [theClass quotedRecogniserWithStartQuote:@"\""
                                                                           endQuote:@"\""
                                                                     escapeSequence:@"\\"
                                                                               name:@"String"];
    [stringRecogniser setEscapeReplacer:^ NSString * (NSString *str, NSUInteger *loc) {
        if (str.length > *loc) {
            switch ([str characterAtIndex:*loc]) {
                case 'b':
                    *loc = *loc + 1;
                    return @"\b";
                case 'f':
                    *loc = *loc + 1;
                    return @"\f";
                case 'n':
                    *loc = *loc + 1;
                    return @"\n";
                case 'r':
                    *loc = *loc + 1;
                    return @"\r";
                case 't':
                    *loc = *loc + 1;
                    return @"\t";
                default:
                    break;
            }
        }
        return nil;
    }];
    return stringRecogniser;
}

+ (CPTokeniser *)newTokenizer {
    CPTokeniser *tokenizer;
    tokenizer = [[CPTokeniser alloc] init];

    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"("]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@")"]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@":"]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@","]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"."]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"?"]];
    [tokenizer addTokenRecogniser:[CPNumberRecogniser numberRecogniser]];
    [tokenizer addTokenRecogniser:[CPWhiteSpaceRecogniser whiteSpaceRecogniser]];
    [tokenizer addTokenRecogniser:[CPIdentifierRecogniser identifierRecogniser]];

    return tokenizer;
}

- (id)init {
    self = [super init];
    if (self) {
        _tokenizer = [iTermFunctionCallParser newTokenizer];
        [_tokenizer addTokenRecogniser:[iTermFunctionCallParser stringRecognizerWithClass:[CPQuotedRecogniser class]]];
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
                               iTermScriptFunctionCall *call = [[iTermScriptFunctionCall alloc] init];
                               call.name = [(CPIdentifierToken *)syntaxTree.children[0] identifier];
                               for (NSDictionary *arg in syntaxTree.children[1]) {
                                   if (arg[@"value"]) {
                                       [call addParameterWithName:arg[@"name"] value:arg[@"value"]];
                                   } else if (arg[@"call"]) {
                                       [call addParameterWithName:arg[@"name"] value:arg[@"call"]];
                                   } else if (arg[@"error"]) {
                                       call.error = [NSError errorWithDomain:@"com.iterm2.parser"
                                                                        code:1
                                                                    userInfo:@{ NSLocalizedDescriptionKey: arg[@"error"] }];
                                   }
                               }
                               return call;
                           }];
    [_grammarProcessor addProductionRule:@"arglist ::= '(' <args> ')'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[1];
                           }];
    [_grammarProcessor addProductionRule:@"arglist ::= '(' ')'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @[];
                           }];
    [_grammarProcessor addProductionRule:@"args ::= <arg>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @[ syntaxTree.children[0] ];
                           }];
    [_grammarProcessor addProductionRule:@"args ::= <arg> ',' <args>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [@[ syntaxTree.children[0] ] arrayByAddingObjectsFromArray:syntaxTree.children[2]];
                           }];
    [_grammarProcessor addProductionRule:@"arg ::= 'Identifier' ':' <expression>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               iTermFunctionCallParser *strongSelf = weakSelf;
                               if (!strongSelf) {
                                   return nil;
                               }
                               //   argdict = {"name":NSString, "value":@{"literal": id}} |
                               //             {"name":NSString, "error":NSString}
                               NSString *argName = [(CPIdentifierToken *)syntaxTree.children[0] identifier];
                               id expression = syntaxTree.children[2];
                               iTermScriptFunctionCall *call = [iTermScriptFunctionCall castFrom:expression];
                               if (call.error) {
                                   return @{ @"name": argName,
                                             @"error": [NSString stringWithFormat:@"Expression \"%@\" had an error: %@", expression, call.error.localizedDescription] };
                               } else if (call) {
                                   return @{ @"name": argName, @"value": call };
                               }

                               NSDictionary *dict = [NSDictionary castFrom:expression];
                               NSString *str = [NSString castFrom:expression];
                               BOOL optional = [str hasSuffix:@"?"];
                               if (optional) {
                                   expression = [str substringWithRange:NSMakeRange(0, str.length - 1)];
                               }
                               id obj = dict[@"literal"];
                               if (!obj) {
                                   obj = strongSelf->_source(expression);
                               }
                               if (!obj) {
                                   if (optional) {
                                       return @{ @"name": argName, @"value": [NSNull null] };
                                   } else {
                                       return @{ @"name": argName,
                                                 @"error": [NSString stringWithFormat:@"Expression \"%@\" unresolvable", expression] };
                                   }
                               } else {
                                   return @{ @"name": argName, @"value": obj };
                               }
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= <path>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[0];
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= <path> '?'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [syntaxTree.children[0] stringByAppendingString:@"?"];
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= 'Number'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"literal": [(CPNumberToken *)syntaxTree.children[0] number] };
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= 'String'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"literal": [(CPQuotedToken *)syntaxTree.children[0] content] };
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= <call>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[0];
                           }];
    [_grammarProcessor addProductionRule:@"path ::= 'Identifier'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [(CPIdentifierToken *)syntaxTree.children[0] identifier];
                           }];
    [_grammarProcessor addProductionRule:@"path ::= 'Identifier' '.' <path>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [NSString stringWithFormat:@"%@.%@",
                                       [(CPIdentifierToken *)syntaxTree.children[0] identifier],
                                       syntaxTree.children[2]];
                           }];
}

- (iTermScriptFunctionCall *)parse:(NSString *)invocation source:(id (^)(NSString *))source {
    _input = [invocation copy];
    _source = [source copy];
    CPTokenStream *tokenStream = [_tokenizer tokenise:invocation];
    iTermScriptFunctionCall *call = (iTermScriptFunctionCall *)[_parser parse:tokenStream];
    if (call) {
        return call;
    }

    call = [[iTermScriptFunctionCall alloc] init];
    if (_error) {
        call.error = _error;
    } else {
        call.error = [NSError errorWithDomain:@"com.iterm2.parser"
                                         code:2
                                     userInfo:@{ NSLocalizedDescriptionKey: @"Syntax error" }];
    }

    return call;
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
    NSArray *quotedExpected = [acceptableTokens.allObjects mapWithBlock:^id(id anObject) {
        return [NSString stringWithFormat:@"“%@”", anObject];
    }];
    NSString *expectedString = [quotedExpected componentsJoinedByString:@", "];
    NSString *reason = [NSString stringWithFormat:@"Syntax error at index %@ of “%@”. Expected one of: %@",
                        @(inputStream.peekToken.characterNumber), _input, expectedString];
    _error = [NSError errorWithDomain:@"com.iterm2.parser"
                                 code:3
                             userInfo:@{ NSLocalizedDescriptionKey: reason }];
    return [CPRecoveryAction recoveryActionStop];
}

@end
