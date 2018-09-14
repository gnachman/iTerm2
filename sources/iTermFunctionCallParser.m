//
//  iTermFunctionCallParser.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import "iTermFunctionCallParser.h"

#import "iTermGrammarProcessor.h"
#import "iTermParsedExpression+Tests.h"
#import "iTermScriptFunctionCall+Private.h"
#import "iTermScriptFunctionCall.h"
#import "iTermSwiftyStringParser.h"
#import "iTermSwiftyStringRecognizer.h"
#import "iTermVariables.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

@interface iTermFunctionArgument : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) iTermParsedExpression *expression;
@end

@implementation iTermParsedExpression

- (NSString *)description {
    NSString *value = nil;
    if (self.functionCall) {
        value = self.functionCall.description;
    } else if (self.error) {
        value = self.error.description;
    } else if (self.string) {
        value = self.string;
    } else if (self.interpolatedStringParts) {
        value = [[self.interpolatedStringParts mapWithBlock:^id(id anObject) {
            return [anObject description];
        }] componentsJoinedByString:@""];
    } else if (self.number) {
        value = [self.number stringValue];
    }
    if (self.optional) {
        value = [value stringByAppendingString:@"?"];
    }
    return [NSString stringWithFormat:@"<Expr %@>", value];
}

- (BOOL)isEqual:(id)object {
    iTermParsedExpression *other = [iTermParsedExpression castFrom:object];
    if (!other) {
        return NO;
    }
    return ([NSObject object:self.functionCall isEqualToObject:other.functionCall] &&
            [NSObject object:self.error isEqualToObject:other.error] &&
            [NSObject object:self.string isEqualToObject:other.string] &&
            [NSObject object:self.number isEqualToObject:other.number] &&
            [NSObject object:self.interpolatedStringParts isEqualToObject:other.interpolatedStringParts] &&
            self.optional == other.optional);
}

+ (instancetype)parsedString:(NSString *)string {
    iTermParsedExpression *expr = [[self alloc] init];
    expr.string = string;
    return expr;
}

@end

@implementation iTermFunctionArgument
@end

@implementation iTermFunctionCallParser {
    @protected
    CPTokeniser *_tokenizer;
    CPParser *_parser;
    iTermVariableScope *_scope;
    NSError *_error;
    NSString *_input;
    iTermGrammarProcessor *_grammarProcessor;
}

+ (instancetype)expressionParser {
    static iTermFunctionCallParser *sCachedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sCachedInstance = [[iTermFunctionCallParser alloc] initWithStart:@"expression"];
    });
    return sCachedInstance;
}

+ (instancetype)callParser {
    static iTermFunctionCallParser *sCachedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sCachedInstance = [[iTermFunctionCallParser alloc] initWithStart:@"call"];
    });
    return sCachedInstance;
}

+ (void)setEscapeReplacerInStringRecognizer:(id)stringRecogniser {
    [stringRecogniser setEscapeReplacer:^ NSString * (NSString *str, NSUInteger *loc) {
        if (str.length > *loc) {
            switch ([str characterAtIndex:*loc]) {
                case 'b':
                    *loc = *loc + 1;
                    return @"\b";
                case 'f':
                    *loc = *loc + 1;
                    return @"\f";
                case 'a':
                    *loc = *loc + 1;
                    return @"\x07";
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
}

+ (id<CPTokenRecogniser>)stringRecognizerWithClass:(Class)theClass {
    CPQuotedRecogniser *stringRecogniser = [theClass quotedRecogniserWithStartQuote:@"\""
                                                                           endQuote:@"\""
                                                                     escapeSequence:@"\\"
                                                                               name:@"String"];
    [self setEscapeReplacerInStringRecognizer:stringRecogniser];
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

- (id)initWithStart:(NSString *)start {
    self = [super init];
    if (self) {
        _tokenizer = [iTermFunctionCallParser newTokenizer];
        [self addSwiftyStringRecognizers];
        _tokenizer.delegate = self;

        _grammarProcessor = [[iTermGrammarProcessor alloc] init];
        [self loadRulesAndTransforms];

        NSError *error = nil;
        CPGrammar *grammar = [CPGrammar grammarWithStart:start
                                          backusNaurForm:_grammarProcessor.backusNaurForm
                                                   error:&error];
        _parser = [CPSLRParser parserWithGrammar:grammar];
        assert(_parser);
        _parser.delegate = self;
    }
    return self;
}

- (void)addSwiftyStringRecognizers {
    iTermSwiftyStringRecognizer *left =
        [[iTermSwiftyStringRecognizer alloc] initWithStartQuote:@"\""
                                                       endQuote:@"\""
                                                 escapeSequence:@"\\"
                                                  maximumLength:NSNotFound
                                                           name:@"SwiftyString"
                                             tolerateTruncation:NO];

    [self.class setEscapeReplacerInStringRecognizer:left];
    [_tokenizer addTokenRecogniser:left];
}

- (void)loadRulesAndTransforms {
    __weak __typeof(self) weakSelf = self;
    [_grammarProcessor addProductionRule:@"call ::= <path> <arglist>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               iTermParsedExpression *expression = [[iTermParsedExpression alloc] init];
                               iTermScriptFunctionCall *call = [[iTermScriptFunctionCall alloc] init];
                               call.name = (NSString *)syntaxTree.children[0];
                               NSArray<iTermFunctionArgument *> *argsArray = syntaxTree.children[1];
                               for (iTermFunctionArgument *arg in argsArray) {
                                   if (arg.expression.string) {
                                       [call addParameterWithName:arg.name value:arg.expression.string];
                                   } else if (arg.expression.number) {
                                       [call addParameterWithName:arg.name value:arg.expression.number];
                                   } else if (arg.expression.functionCall) {
                                       [call addParameterWithName:arg.name value:arg.expression.functionCall];
                                   } else if (arg.expression.error) {
                                       return arg.expression;
                                   } else if (arg.expression.optional) {
                                       [call addParameterWithName:arg.name value:[NSNull null]];
                                   } else if (arg.expression.interpolatedStringParts) {
                                       [call addParameterWithName:arg.name value:arg.expression];
                                   } else {
                                       assert(false);
                                   }
                               }
                               expression.functionCall = call;
                               return expression;
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
                               iTermFunctionArgument *arg = [[iTermFunctionArgument alloc] init];
                               arg.name = [(CPIdentifierToken *)syntaxTree.children[0] identifier];
                               arg.expression = syntaxTree.children[2];
                               return arg;
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= <path>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               iTermFunctionCallParser *strongSelf = weakSelf;
                               if (!strongSelf) {
                                   return nil;
                               }
                               iTermParsedExpression *expression = [[iTermParsedExpression alloc] init];
                               NSString *path = syntaxTree.children[0];
                               id value = [strongSelf->_scope valueForVariableName:path];
                               expression.string = [NSString castFrom:value];
                               expression.number = [NSNumber castFrom:value];
                               if (!expression.string && !expression.number) {
                                   NSString *reason = [NSString stringWithFormat:@"Reference to undefined variable %@", path];
                                   expression.error = [NSError errorWithDomain:@"com.iterm2.parser"
                                                                          code:1
                                                                      userInfo:@{ NSLocalizedDescriptionKey: reason }];
                               }
                               return expression;
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= <path> '?'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               iTermFunctionCallParser *strongSelf = weakSelf;
                               if (!strongSelf) {
                                   return nil;
                               }
                               iTermParsedExpression *expression = [[iTermParsedExpression alloc] init];
                               NSString *path = syntaxTree.children[0];
                               id value = [strongSelf->_scope valueForVariableName:path];
                               expression.string = [NSString castFrom:value];
                               expression.number = [NSNumber castFrom:value];
                               expression.optional = YES;
                               return expression;
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= 'Number'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               iTermParsedExpression *expression = [[iTermParsedExpression alloc] init];
                               expression.number = [(CPNumberToken *)syntaxTree.children[0] number];
                               return expression;
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= 'SwiftyString'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               iTermFunctionCallParser *strongSelf = weakSelf;
                               if (!strongSelf) {
                                   return nil;
                               }
                               NSString *swifty = [(CPQuotedToken *)syntaxTree.children[0] content];
                               NSMutableArray *interpolatedParts = [NSMutableArray array];
                               [swifty enumerateSwiftySubstrings:^(NSUInteger index, NSString *substring, BOOL isLiteral, BOOL *stop) {
                                   if (isLiteral) {
                                       [interpolatedParts addObject:[substring it_stringByExpandingBackslashEscapedCharacters]];
                                       return;
                                   }

                                   iTermFunctionCallParser *parser = [[iTermFunctionCallParser alloc] initWithStart:@"expression"];
                                   iTermParsedExpression *expression = [parser parse:substring
                                                                               scope:strongSelf->_scope];
                                   [interpolatedParts addObject:expression];
                                   if (expression.error) {
                                       *stop = YES;
                                       return;
                                   }
                               }];

                               return [strongSelf expressionWithCoalescedInterpolatedStringParts:interpolatedParts];
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

- (iTermParsedExpression *)expressionWithCoalescedInterpolatedStringParts:(NSArray *)interpolatedParts {
    NSMutableArray *coalesced = [NSMutableArray array];
    NSMutableArray *parts = [interpolatedParts mutableCopy];
    NSError *error = nil;
    while (parts.count) {
        id previous = coalesced.lastObject;
        id object = parts.firstObject;
        [parts removeObjectAtIndex:0];

        id value = object;
        iTermParsedExpression *inner = [iTermParsedExpression castFrom:object];
        if (inner.string) {
            value = inner.string;
        } else if (inner.number) {
            value = inner.number.stringValue;
        } else if (inner.error) {
            error = inner.error;
            break;
        } else if (inner.interpolatedStringParts) {
            NSArray *innerParts = inner.interpolatedStringParts;
            for (NSInteger i = 0; i < innerParts.count; i++) {
                [parts insertObject:innerParts[i] atIndex:i];
            }
            value = nil;
        }
        if ([value isKindOfClass:[NSString class]] &&
            [previous isKindOfClass:[NSString class]]) {
            [coalesced removeLastObject];
            [coalesced addObject:[previous stringByAppendingString:value]];
        } else if (value) {
            [coalesced addObject:value];
        }
    }

    iTermParsedExpression *result = [[iTermParsedExpression alloc] init];
    if (error) {
        result.error = error;
        return result;
    }
    if (coalesced.count == 1) {
        if ([coalesced.firstObject isKindOfClass:[NSString class]]) {
            result.string = coalesced.firstObject;
            return result;
        } else {
            assert([coalesced.firstObject isKindOfClass:[iTermParsedExpression class]]);
            return coalesced.firstObject;
        }
    }
    result.interpolatedStringParts = coalesced;
    return result;
}

- (iTermParsedExpression *)parse:(NSString *)invocation scope:(iTermVariableScope *)scope {
    _input = [invocation copy];
    _scope = scope;
    CPTokenStream *tokenStream = [_tokenizer tokenise:invocation];
    iTermParsedExpression *expression = (iTermParsedExpression *)[_parser parse:tokenStream];
    if (expression) {
        return expression;
    }

    expression = [[iTermParsedExpression alloc] init];
    if (_error) {
        expression.error = _error;
    } else {
        expression.error = [NSError errorWithDomain:@"com.iterm2.parser"
                                               code:2
                                           userInfo:@{ NSLocalizedDescriptionKey: @"Syntax error" }];
    }

    return expression;
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
    NSString *reason = [NSString stringWithFormat:@"Syntax error at index %@ of “%@”. Expected%@: %@",
                        @(inputStream.peekToken.characterNumber), _input,
                        quotedExpected.count > 1 ? @" one of" : @"",
                        expectedString];
    _error = [NSError errorWithDomain:@"com.iterm2.parser"
                                 code:3
                             userInfo:@{ NSLocalizedDescriptionKey: reason }];
    return [CPRecoveryAction recoveryActionStop];
}

@end
