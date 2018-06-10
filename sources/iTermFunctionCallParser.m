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

@interface iTermParsedExpression()
@property (nonatomic, readwrite) NSString *sourceCode;
@property (nonatomic, readwrite) iTermScriptFunctionCall *functionCall;
@property (nonatomic, readwrite) NSError *error;
@property (nonatomic, readwrite) NSString *string;
@property (nonatomic, readwrite) NSNumber *number;
@property (nonatomic, readwrite) BOOL optional;
@end

@interface iTermFunctionArgument : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) iTermParsedExpression *expression;
@end

@implementation iTermParsedExpression
@end

@implementation iTermFunctionArgument
@end

@implementation iTermFunctionCallParser {
    @protected
    CPTokeniser *_tokenizer;
    CPParser *_parser;
    id (^_source)(NSString *);
    NSError *_error;
    NSString *_input;
    iTermGrammarProcessor *_grammarProcessor;
}

+ (instancetype)sharedInstance {
    static iTermFunctionCallParser *sCachedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sCachedInstance = [[iTermFunctionCallParser alloc] initPrivate];
    });
    return sCachedInstance;
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

- (id)initPrivate {
    self = [super init];
    if (self) {
        _tokenizer = [iTermFunctionCallParser newTokenizer];
        [_tokenizer addTokenRecogniser:[iTermFunctionCallParser stringRecognizerWithClass:[CPQuotedRecogniser class]]];
        _tokenizer.delegate = self;

        _grammarProcessor = [[iTermGrammarProcessor alloc] init];
        [self loadRulesAndTransforms];

        NSError *error = nil;
        CPGrammar *grammar = [CPGrammar grammarWithStart:@"expression"
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
                               id value = strongSelf->_source(path);
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
                               id value = strongSelf->_source(path);
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
    [_grammarProcessor addProductionRule:@"expression ::= 'String'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               iTermParsedExpression *expression = [[iTermParsedExpression alloc] init];
                               expression.string = [(CPQuotedToken *)syntaxTree.children[0] content];
                               return expression;
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

- (iTermParsedExpression *)parse:(NSString *)invocation source:(id (^)(NSString *))source {
    _input = [invocation copy];
    _source = [source copy];
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
    NSString *reason = [NSString stringWithFormat:@"Syntax error at index %@ of “%@”. Expected one of: %@",
                        @(inputStream.peekToken.characterNumber), _input, expectedString];
    _error = [NSError errorWithDomain:@"com.iterm2.parser"
                                 code:3
                             userInfo:@{ NSLocalizedDescriptionKey: reason }];
    return [CPRecoveryAction recoveryActionStop];
}

@end
