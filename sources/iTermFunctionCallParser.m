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
#import "iTermVariableScope.h"
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
    switch (self.expressionType) {
        case iTermParsedExpressionTypeInterpolatedString:
            value = [[self.interpolatedStringParts mapWithBlock:^id(id anObject) {
                return [anObject description];
            }] componentsJoinedByString:@""];
            break;
        case iTermParsedExpressionTypeFunctionCall:
            value = self.functionCall.description;
            break;
        case iTermParsedExpressionTypeNil:
            value = @"nil";
            break;
        case iTermParsedExpressionTypeError:
            value = self.error.description;
            break;
        case iTermParsedExpressionTypeNumber:
            value = [self.number stringValue];
            break;
        case iTermParsedExpressionTypeString:
            value = self.string;
            break;
        case iTermParsedExpressionTypeArray:
            value = [[self.array mapWithBlock:^id(id anObject) {
                return [anObject description];
            }] componentsJoinedByString:@" "];
            break;
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
    return ([NSObject object:self.object isEqualToObject:other.object] &&
            self.expressionType == other.expressionType &&
            self.optional == other.optional);
}

+ (instancetype)parsedString:(NSString *)string {
    return [[self alloc] initWithString:string optional:NO];
}

- (instancetype)initWithString:(NSString *)string optional:(BOOL)optional {
    self = [super init];
    if (self) {
        _expressionType = iTermParsedExpressionTypeString;
        _optional = optional;
        _object = string;
    }
    return self;
}

- (instancetype)initWithFunctionCall:(iTermScriptFunctionCall *)functionCall {
    self = [super init];
    if (self) {
        _expressionType = iTermParsedExpressionTypeFunctionCall;
        _object = functionCall;
    }
    return self;
}

- (instancetype)initWithErrorCode:(int)code reason:(NSString *)localizedDescription {
    self = [super init];
    if (self) {
        _expressionType = iTermParsedExpressionTypeError;
        _object = [NSError errorWithDomain:@"com.iterm2.parser"
                                      code:code
                                  userInfo:@{ NSLocalizedDescriptionKey: localizedDescription ?: @"Unknown error" }];
    }
    return self;
}

// Object may be NSString, NSNumber, or NSArray. If it is not, an error will be created with the
// given reason.
- (instancetype)initWithObject:(id)object errorReason:(NSString *)errorReason {
    if ([object isKindOfClass:[NSString class]]) {
        return [self initWithString:object optional:NO];
    }
    if ([object isKindOfClass:[NSNumber class]]) {
        return [self initWithNumber:object];
    }
    if ([object isKindOfClass:[NSArray class]]) {
        return [self initWithArray:object];
    }
    return [self initWithErrorCode:7 reason:errorReason];
}

- (instancetype)initWithOptionalObject:(id)object {
    if (object) {
        self = [self initWithObject:object errorReason:[NSString stringWithFormat:@"Invalid type: %@", [object class]]];
    } else {
        self = [super init];
    }
    if (self) {
        _optional = YES;
    }
    return self;
}

- (instancetype)initWithArray:(NSArray *)array {
    self = [super init];
    if (self) {
        _expressionType = iTermParsedExpressionTypeArray;
        _object = array;
    }
    return self;
}

- (instancetype)initWithNumber:(NSNumber *)number {
    self = [super init];
    if (self) {
        _expressionType = iTermParsedExpressionTypeNumber;
        _object = number;
    }
    return self;
}

- (instancetype)initWithError:(NSError *)error {
    self = [super init];
    if (self) {
        _expressionType = iTermParsedExpressionTypeError;
        _object = error;
    }
    return self;
}

- (instancetype)initWithInterpolatedStringParts:(NSArray *)parts {
    self = [super init];
    if (self) {
        _expressionType = iTermParsedExpressionTypeInterpolatedString;
        _object = parts;
    }
    return self;
}

- (NSArray *)array {
    assert([_object isKindOfClass:[NSArray class]]);
    return _object;
}

- (NSString *)string {
    assert([_object isKindOfClass:[NSString class]]);
    return _object;
}

- (NSNumber *)number {
    assert([_object isKindOfClass:[NSNumber class]]);
    return _object;
}

- (NSError *)error {
    assert([_object isKindOfClass:[NSError class]]);
    return _object;
}

- (iTermScriptFunctionCall *)functionCall {
    assert([_object isKindOfClass:[iTermScriptFunctionCall class]]);
    return _object;
}

- (NSArray *)interpolatedStringParts {
    assert([_object isKindOfClass:[NSArray class]]);
    return _object;
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

+ (NSString *)signatureForTopLevelInvocation:(NSString *)invocation {
    iTermFunctionCallParser *parser = [iTermFunctionCallParser callParser];
    iTermVariableScope *scope = [[iTermVariableRecordingScope alloc] initWithScope:[[iTermVariableScope alloc] init]];
    scope.neverReturnNil = YES;
    iTermParsedExpression *expression = [parser parse:invocation scope:scope];
    if (expression.expressionType == iTermParsedExpressionTypeFunctionCall) {
        return expression.functionCall.signature;
    }
    if (expression.expressionType == iTermParsedExpressionTypeError) {
        return [NSString stringWithFormat:@"Erroneous invocation %@", invocation];
    }
    assert(NO);
    return @"";
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
                               iTermScriptFunctionCall *call = [[iTermScriptFunctionCall alloc] init];
                               call.name = (NSString *)syntaxTree.children[0];
                               NSArray<iTermFunctionArgument *> *argsArray = syntaxTree.children[1];
                               for (iTermFunctionArgument *arg in argsArray) {
                                   if (arg.expression.expressionType == iTermParsedExpressionTypeError) {
                                       return arg.expression.error;
                                   }
                                   assert(arg.expression.optional || arg.expression.object);
                                   if (arg.expression.expressionType == iTermParsedExpressionTypeInterpolatedString) {
                                       [call addParameterWithName:arg.name
                                                            value:arg.expression];
                                   } else {
                                       [call addParameterWithName:arg.name
                                                            value:arg.expression.object ?: [NSNull null]];
                                   }
                               }
                               return [[iTermParsedExpression alloc] initWithFunctionCall:call];
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
    [_grammarProcessor addProductionRule:@"expression ::= <path_or_dereferenced_array>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               iTermFunctionCallParser *strongSelf = weakSelf;
                               if (!strongSelf) {
                                   return nil;
                               }
                               iTermTriple *triple = syntaxTree.children[0];
                               if (triple.secondObject) {
                                   return [[iTermParsedExpression alloc] initWithErrorCode:3 reason:triple.secondObject];
                               }
                               id value = triple.firstObject;
                               return [[iTermParsedExpression alloc] initWithObject:value
                                                                        errorReason:[NSString stringWithFormat:@"Reference to undefined variable “%@”. Use ? to convert undefined values to null.", triple.thirdObject]];
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= <path_or_dereferenced_array> '?'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               iTermFunctionCallParser *strongSelf = weakSelf;
                               if (!strongSelf) {
                                   return nil;
                               }
                               iTermTriple *triple = syntaxTree.children[0];
                               if (triple.secondObject) {
                                   return [[iTermParsedExpression alloc] initWithErrorCode:3 reason:triple.secondObject];
                               }
                               id value = triple.firstObject;
                               return [[iTermParsedExpression alloc] initWithOptionalObject:value];
                           }];
    [_grammarProcessor addProductionRule:@"expression ::= 'Number'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [[iTermParsedExpression alloc] initWithNumber:[(CPNumberToken *)syntaxTree.children[0] number]];
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
                                   if (expression.expressionType == iTermParsedExpressionTypeError) {
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
    [_grammarProcessor addProductionRule:@"path_or_dereferenced_array ::= <path>"  // -> (value, error string, path); value of NSNull means undefined.
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               iTermFunctionCallParser *strongSelf = weakSelf;
                               if (!strongSelf) {
                                   return nil;
                               }
                               NSString *path = syntaxTree.children[0];
                               id untypedValue = [strongSelf->_scope valueForVariableName:path];
                               if (!untypedValue) {
                                   return [iTermTriple tripleWithObject:nil andObject:nil object:path];
                               }
                               return [iTermTriple tripleWithObject:untypedValue andObject:nil object:path];
                           }];
    [_grammarProcessor addProductionRule:@"path_or_dereferenced_array ::= <path> '[' 'Number' ']'"  // -> (value, error string, path); value of NSNull means undefined.
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               iTermFunctionCallParser *strongSelf = weakSelf;
                               if (!strongSelf) {
                                   return nil;
                               }

                               NSString *path = syntaxTree.children[0];
                               CPNumberToken *numberToken = syntaxTree.children[2];
                               const NSInteger index = numberToken.number.integerValue;

                               id untypedValue = [strongSelf->_scope valueForVariableName:path];
                               if (!untypedValue) {
                                   return [iTermTriple tripleWithObject:nil andObject:nil object:path];
                               }
                               NSArray *array = [NSArray castFrom:untypedValue];
                               if (!array) {
                                   NSString *reason = [NSString stringWithFormat:@"Variable “%@” is of type %@, not array", path, NSStringFromClass([untypedValue class])];
                                   return [iTermTriple tripleWithObject:nil andObject:reason object:path];
                               }
                               if (index < 0 || index >= array.count) {
                                   NSString *reason = [NSString stringWithFormat:@"Index %@ out of range of “%@”, which %@ values", @(index), path, @(array.count)];
                                   return [iTermTriple tripleWithObject:nil andObject:reason object:path];
                               }
                               return [iTermTriple tripleWithObject:array[index] andObject:nil object:path];
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
    while (parts.count) {
        id previous = coalesced.lastObject;
        id object = parts.firstObject;
        [parts removeObjectAtIndex:0];

        id value = object;
        iTermParsedExpression *inner = [iTermParsedExpression castFrom:object];
        if (inner) {
            switch (inner.expressionType) {
                case iTermParsedExpressionTypeError:
                    return [[iTermParsedExpression alloc] initWithError:inner.error];
                case iTermParsedExpressionTypeNumber:
                    value = inner.number.stringValue;
                    break;
                case iTermParsedExpressionTypeNil:
                case iTermParsedExpressionTypeString:
                case iTermParsedExpressionTypeArray:
                    value = inner.object;
                    break;
                case iTermParsedExpressionTypeInterpolatedString: {
                    NSArray *innerParts = inner.interpolatedStringParts;
                    for (NSInteger i = 0; i < innerParts.count; i++) {
                        [parts insertObject:innerParts[i] atIndex:i];
                    }
                    value = nil;
                    break;
                }
                case iTermParsedExpressionTypeFunctionCall:
                    break;
            }
        }
        if ([value isKindOfClass:[NSString class]] &&
            [previous isKindOfClass:[NSString class]]) {
            [coalesced removeLastObject];
            [coalesced addObject:[previous stringByAppendingString:value]];
        } else if (value) {
            [coalesced addObject:value];
        }
    }

    if (coalesced.count != 1) {
        return [[iTermParsedExpression alloc] initWithInterpolatedStringParts:coalesced];
    }

    id onlyObject = coalesced.firstObject;
    if ([onlyObject isKindOfClass:[NSString class]]) {
        return [[iTermParsedExpression alloc] initWithString:onlyObject optional:NO];
    }

    assert([onlyObject isKindOfClass:[iTermParsedExpression class]]);
    return onlyObject;
}

- (iTermParsedExpression *)parse:(NSString *)invocation scope:(iTermVariableScope *)scope {
    _input = [invocation copy];
    _scope = scope;
    CPTokenStream *tokenStream = [_tokenizer tokenise:invocation];
    id result = [_parser parse:tokenStream];
    if ([result isKindOfClass:[NSError class]]) {
        return [[iTermParsedExpression alloc] initWithError:result];
    }
    iTermParsedExpression *expression = [iTermParsedExpression castFrom:result];
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
