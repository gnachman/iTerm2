//
//  iTermExpressionParser.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import "iTermExpressionParser.h"
#import "iTermExpressionParser+Private.h"

#import "iTermGrammarProcessor.h"
#import "iTermParsedExpression+Tests.h"
#import "iTermScriptFunctionCall+Private.h"
#import "iTermScriptFunctionCall.h"
#import "iTermSwiftyStringParser.h"
#import "iTermSwiftyStringRecognizer.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

@implementation iTermFunctionArgument
@end

@implementation iTermExpressionParser {
    @protected
    CPTokeniser *_tokenizer;
    CPParser *_parser;
    iTermVariableScope *_scope;
    NSError *_error;
    NSString *_input;
    iTermGrammarProcessor *_grammarProcessor;
}

+ (NSString *)signatureForFunctionCallInvocation:(NSString *)invocation
                                           error:(out NSError *__autoreleasing *)error {
    iTermVariableRecordingScope *permissiveScope = [[iTermVariableRecordingScope alloc] initWithScope:[[iTermVariableScope alloc] init]];
    permissiveScope.neverReturnNil = YES;
    iTermParsedExpression *expression = [[iTermExpressionParser callParser] parse:invocation
                                                                            scope:permissiveScope];
    switch (expression.expressionType) {
        case iTermParsedExpressionTypeNumber:
        case iTermParsedExpressionTypeString:
        case iTermParsedExpressionTypeArrayOfExpressions:
        case iTermParsedExpressionTypeArrayOfValues:
            if (error) {
                *error = [NSError errorWithDomain:@"com.iterm2.call"
                                             code:3
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Expected function call, not a literal" }];
            }
            return nil;

        case iTermParsedExpressionTypeError:
            if (error) {
                *error = expression.error;
            }
            return nil;

        case iTermParsedExpressionTypeFunctionCall:
            return expression.functionCall.signature;

        case iTermParsedExpressionTypeNil:
            if (error) {
                *error = [NSError errorWithDomain:@"com.iterm2.call"
                                             code:3
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Expected function call, not nil" }];
            }
            return nil;
        case iTermParsedExpressionTypeInterpolatedString:
            if (error) {
                *error = [NSError errorWithDomain:@"com.iterm2.call"
                                             code:3
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Expected function call, not an interpolated string" }];
            }
            return nil;
    }
    assert(NO);
}


+ (instancetype)expressionParser {
    static iTermExpressionParser *sCachedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sCachedInstance = [[iTermExpressionParser alloc] initWithStart:@"expression"];
    });
    return sCachedInstance;
}

+ (instancetype)callParser {
    static iTermExpressionParser *sCachedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sCachedInstance = [[iTermExpressionParser alloc] initWithStart:@"call"];
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
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"["]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"]"]];
    [tokenizer addTokenRecogniser:[CPNumberRecogniser numberRecogniser]];
    [tokenizer addTokenRecogniser:[CPWhiteSpaceRecogniser whiteSpaceRecogniser]];
    [tokenizer addTokenRecogniser:[CPIdentifierRecogniser identifierRecogniser]];

    return tokenizer;
}

- (id)initWithStart:(NSString *)start {
    self = [super init];
    if (self) {
        _tokenizer = [iTermExpressionParser newTokenizer];
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

- (iTermParsedExpression *)parsedExpressionForFunctionCallWithName:(NSString *)name
                                                           arglist:(NSArray<iTermFunctionArgument *> *)argsArray
                                                             error:(out NSError **)error {
    iTermScriptFunctionCall *call = [[iTermScriptFunctionCall alloc] init];
    call.name = name;
    for (iTermFunctionArgument *arg in argsArray) {
        if (arg.expression.expressionType == iTermParsedExpressionTypeError) {
            if (error) {
                *error = arg.expression.error;
            }
            return nil;
        }
        [call addParameterWithName:arg.name
                  parsedExpression:arg.expression];
    }

    if (error) {
        *error = nil;
    }
    return [[iTermParsedExpression alloc] initWithFunctionCall:call];
}

- (iTermFunctionArgument *)newFunctionArgumentWithName:(NSString *)name
                                            expression:(iTermParsedExpression *)expression {
    iTermFunctionArgument *arg = [[iTermFunctionArgument alloc] init];
    arg.name = name;
    arg.expression = expression;
    return arg;
}

- (iTermParsedExpression *)parsedExpressionWithValue:(id)value
                                         errorReason:(NSString *)errorReason
                                                path:(NSString *)path
                                            optional:(BOOL)optional {
    if (errorReason) {
        return [[iTermParsedExpression alloc] initWithErrorCode:3 reason:errorReason];
    }

    // The fallbackError is used only when value is not legit.
    NSString *fallbackError;
    if (optional) {
        return [[iTermParsedExpression alloc] initWithOptionalObject:value];
    } else {
        fallbackError = [NSString stringWithFormat:@"Reference to undefined variable “%@”. Use ? to convert undefined values to null.", path];
        return [[iTermParsedExpression alloc] initWithObject:value
                                                 errorReason:fallbackError];
    }
}

+ (iTermParsedExpression *)parsedExpressionWithInterpolatedStringParts:(NSArray<iTermParsedExpression *> *)interpolatedParts {
    NSArray<iTermParsedExpression *> *coalesced =
    [interpolatedParts reduceWithFirstValue:@[]
                                      block:
     ^id(NSArray<iTermParsedExpression *> *arraySoFar, iTermParsedExpression *expression) {
         if (expression.expressionType == iTermParsedExpressionTypeString &&
             arraySoFar.lastObject &&
             arraySoFar.lastObject.expressionType == iTermParsedExpressionTypeString) {
             NSString *concatenated = [arraySoFar.lastObject.string stringByAppendingString:expression.string];
             iTermParsedExpression *combined = [[iTermParsedExpression alloc] initWithString:concatenated
                                                                                    optional:NO];
             return [[arraySoFar subarrayToIndex:arraySoFar.count - 1] arrayByAddingObject:combined];
         }
         return [arraySoFar arrayByAddingObject:expression];
     }];
    return [[iTermParsedExpression alloc] initWithInterpolatedStringParts:coalesced];
}

- (iTermParsedExpression *)parsedExpressionWithInterpolatedString:(NSString *)swifty {
    return [self.class parsedExpressionWithInterpolatedString:swifty scope:_scope];
}

+ (iTermParsedExpression *)parsedExpressionWithInterpolatedString:(NSString *)swifty
                                                            scope:(iTermVariableScope *)scope {
    __block NSError *error = nil;
    NSMutableArray *interpolatedParts = [NSMutableArray array];
    [swifty enumerateSwiftySubstrings:^(NSUInteger index, NSString *substring, BOOL isLiteral, BOOL *stop) {
        if (isLiteral) {
            NSString *escapedString = [substring it_stringByExpandingBackslashEscapedCharacters];
            [interpolatedParts addObject:[[iTermParsedExpression alloc] initWithString:escapedString
                                                                              optional:NO]];
            return;
        }

        iTermExpressionParser *parser = [[iTermExpressionParser alloc] initWithStart:@"expression"];
        iTermParsedExpression *expression = [parser parse:substring
                                                    scope:scope];
        [interpolatedParts addObject:expression];
        if (expression.expressionType == iTermParsedExpressionTypeError) {
            error = expression.error;
            *stop = YES;
            return;
        }
    }];

    if (error) {
        return [[iTermParsedExpression alloc] initWithError:error];
    }

    return [self parsedExpressionWithInterpolatedStringParts:interpolatedParts];
}

- (iTermTriple<id, NSString *, NSString *> *)pathOrDereferencedArrayFromPath:(NSString *)path
                                                                       index:(NSNumber *)indexNumber {
    id untypedValue = [_scope valueForVariableName:path];
    if (!untypedValue) {
        return [iTermTriple tripleWithObject:nil andObject:nil object:path];
    }

    if (!indexNumber) {
        return [iTermTriple tripleWithObject:untypedValue andObject:nil object:path];
    }

    NSArray *array = [NSArray castFrom:untypedValue];
    if (!array) {
        NSString *reason = [NSString stringWithFormat:@"Variable “%@” is of type %@, not array", path, NSStringFromClass([untypedValue class])];
        return [iTermTriple tripleWithObject:nil andObject:reason object:path];
    }

    NSInteger index = indexNumber.integerValue;
    if (index < 0 || index >= array.count) {
        NSString *reason = [NSString stringWithFormat:@"Index %@ out of range of “%@”, which %@ values", @(index), path, @(array.count)];
        return [iTermTriple tripleWithObject:nil andObject:reason object:path];
    }

    return [iTermTriple tripleWithObject:array[index] andObject:nil object:path];
}

- (void)loadRulesAndTransforms {
    __weak __typeof(self) weakSelf = self;
    [_grammarProcessor addProductionRule:@"call ::= <path> <arglist>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               NSError *error = nil;
                               iTermParsedExpression *result = [weakSelf parsedExpressionForFunctionCallWithName:(NSString *)syntaxTree.children[0]
                                                                                                         arglist:syntaxTree.children[1]
                                                                                                           error:&error];
                               if (error) {
                                   return [[iTermParsedExpression alloc] initWithError:error];
                               }
                               return result;
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
                               return [weakSelf newFunctionArgumentWithName:[(CPIdentifierToken *)syntaxTree.children[0] identifier]
                                                                 expression:syntaxTree.children[2]];
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= <path_or_dereferenced_array>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               iTermTriple *triple = syntaxTree.children[0];
                               return [weakSelf parsedExpressionWithValue:triple.firstObject
                                                              errorReason:triple.secondObject
                                                                     path:triple.thirdObject
                                                                 optional:NO];
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= <path_or_dereferenced_array> '?'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               iTermTriple *triple = syntaxTree.children[0];
                               return [weakSelf parsedExpressionWithValue:triple.firstObject
                                                              errorReason:triple.secondObject
                                                                     path:triple.thirdObject
                                                                 optional:YES];
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= 'Number'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [[iTermParsedExpression alloc] initWithNumber:[(CPNumberToken *)syntaxTree.children[0] number]];
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= '[' ']'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [[iTermParsedExpression alloc] initWithArrayOfExpressions:@[]];
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= '[' <comma_delimited_expressions> ']'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [[iTermParsedExpression alloc] initWithArrayOfExpressions:syntaxTree.children[1]];
                           }];
    [_grammarProcessor addProductionRule:@"comma_delimited_expressions ::= <expression>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @[ syntaxTree.children[0] ];
                           }];
    [_grammarProcessor addProductionRule:@"comma_delimited_expressions ::= <expression> ',' <comma_delimited_expressions>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               id firstExpression = syntaxTree.children[0];
                               NSArray *tail = syntaxTree.children[2];
                               return [@[firstExpression] arrayByAddingObjectsFromArray:tail];
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= 'SwiftyString'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               NSString *swifty = [(CPQuotedToken *)syntaxTree.children[0] content];
                               return [weakSelf parsedExpressionWithInterpolatedString:swifty];
                           }];

    [_grammarProcessor addProductionRule:@"expression ::= <call>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[0];
                           }];
    [_grammarProcessor addProductionRule:@"path_or_dereferenced_array ::= <path>"  // -> (value, error string, path); value of NSNull means undefined.
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [weakSelf pathOrDereferencedArrayFromPath:syntaxTree.children[0]
                                                                          index:nil];
                           }];
    [_grammarProcessor addProductionRule:@"path_or_dereferenced_array ::= <path> '[' 'Number' ']'"  // -> (value, error string, path); value of NSNull means undefined.
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               CPNumberToken *numberToken = syntaxTree.children[2];
                               return [weakSelf pathOrDereferencedArrayFromPath:syntaxTree.children[0]
                                                                          index:numberToken.number];
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

- (iTermParsedExpression *)parse:(NSString *)invocation scope:(iTermVariableScope *)scope {
    _input = [invocation copy];
    _scope = scope;
    CPTokenStream *tokenStream = [_tokenizer tokenise:invocation];

    iTermParsedExpression *expression = [_parser parse:tokenStream];
    if (expression) {
        return expression;
    }

    if (_error) {
        return [[iTermParsedExpression alloc] initWithError:_error];
    }

    NSError *error = [NSError errorWithDomain:@"com.iterm2.parser"
                                         code:2
                                     userInfo:@{ NSLocalizedDescriptionKey: @"Syntax error" }];
    return [[iTermParsedExpression alloc] initWithError:error];
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
