//
//  iTermExpressionParser.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import "iTermExpressionParser.h"
#import "iTermExpressionParser+Private.h"

#import "CPParser+Cache.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermGrammarProcessor.h"
#import "iTermParsedExpression+Tests.h"
#import "iTermScriptFunctionCall+Private.h"
#import "iTermScriptFunctionCall.h"
#import "iTermSwiftyStringParser.h"
#import "iTermSwiftyStringRecognizer.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

@implementation iTermFunctionArgument
@end

@implementation iTermExpressionParser {
    @protected
    CPTokeniser *_tokenizer;
    CPLALR1Parser *_parser;
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
        case iTermParsedExpressionTypeArrayLookup:
        case iTermParsedExpressionTypeVariableReference:
        case iTermParsedExpressionTypeSubexpression:
        case iTermParsedExpressionTypeIndirectValue:
        case iTermParsedExpressionTypeReference:
        case iTermParsedExpressionTypeString:
        case iTermParsedExpressionTypeArrayOfExpressions:
        case iTermParsedExpressionTypeArrayOfValues:
            if (error) {
                *error = [NSError errorWithDomain:@"com.iterm2.call"
                                             code:3
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Expected function call, not a value" }];
            }
            return nil;

        case iTermParsedExpressionTypeError:
            if (error) {
                *error = expression.error;
            }
            return nil;

        case iTermParsedExpressionTypeFunctionCall:
            return expression.functionCall.signature;

        case iTermParsedExpressionTypeFunctionCalls:
            if (error) {
                *error = [NSError errorWithDomain:@"com.iterm2.call"
                                             code:3
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Expected single function call" }];
            }
            return nil;

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
        sCachedInstance = [[iTermExpressionParser alloc] initWithStart:@"callsequence"];
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

// Note that iTermFunctionCallSuggester also uses this.
+ (CPTokeniser *)newTokenizer {
    CPTokeniser *tokenizer;
    tokenizer = [[CPTokeniser alloc] init];

    // Multi-character operators MUST come before single-character ones
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"=="]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"!="]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"<="]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@">="]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"&&"]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"||"]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"<"]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@">"]];

    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"("]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@")"]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@":"]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@","]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"."]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"?"]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"["]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"]"]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@";"]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"&"]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"+"]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"-"]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"*"]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"/"]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"!"]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"true"]];
    [tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"false"]];
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

        _parser = [CPLALR1Parser parserWithBNF:_grammarProcessor.backusNaurForm start:start];
        assert(_parser);
        _parser.delegate = self;
    }
    return self;
}

- (void)dealloc {
    [_parser it_releaseParser];
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

- (iTermParsedExpression *)callSequenceWithCalls:(NSArray *)calls {
    return [[iTermParsedExpression alloc] initWithFunctionCalls:calls];
}


- (iTermParsedExpression *)parsedExpressionForFunctionCallWithFullyQualifiedName:(NSString *)fqName
                                                                         arglist:(NSArray<iTermFunctionArgument *> *)argsArray
                                                                           error:(out NSError **)error {
    NSString *name;
    NSString *namespace;
    iTermFunctionCallSplitFullyQualifiedName(fqName, &namespace, &name);
    iTermScriptFunctionCall *call = [[iTermScriptFunctionCall alloc] init];
    call.name = name;
    call.namespace = namespace;
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
                                            expression:(iTermParsedExpression *)expression
                                       passByReference:(BOOL)passByReference {
    iTermFunctionArgument *arg = [[iTermFunctionArgument alloc] init];
    arg.name = name;
    arg.expression = expression;
    arg.passByReference = passByReference;
    return arg;
}

- (iTermParsedExpression *)parsedExpressionWithReferenceToPath:(NSString *)path {
    if (![_scope userWritableContainerExistsForPath:path]) {
        return [[iTermParsedExpression alloc] initWithErrorCode:3 reason:[NSString stringWithFormat:@"Can’t form reference to non-existent or read-only container for variable %@", path]];
    }
    iTermVariableReference *ref = [[iTermVariableReference alloc] initWithPath:path
                                                                        vendor:_scope];
    return [[iTermParsedExpression alloc] initWithReference:ref];
}

- (iTermParsedExpression *)parsedExpressionWithIndirectValue:(iTermIndirectValue *)indirectValue {
    if (indirectValue.error) {
        return [[iTermParsedExpression alloc] initWithErrorCode:3 reason:indirectValue.error];
    }

    if ([indirectValue.value conformsToProtocol:@protocol(iTermExpressionParserPlaceholder)]) {
        return [[iTermParsedExpression alloc] initWithPlaceholder:(id<iTermExpressionParserPlaceholder>)indirectValue.value
                                                         optional:YES];
    }

    // The fallbackError is used only when value is not legit.
    NSString *fallbackError;
    fallbackError = [NSString stringWithFormat:@"Reference to undefined variable \"%@\". Change it to \"%@?\" to treat the undefined value as null.", indirectValue.path, indirectValue.path];
    return [[[iTermParsedExpression alloc] initWithObject:indirectValue.value
                                              errorReason:fallbackError] optionalized];
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
             iTermParsedExpression *combined = [[iTermParsedExpression alloc] initWithString:concatenated];
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
    return [self parsedExpressionWithInterpolatedString:swifty escapingFunction:nil scope:scope strict:NO];
}

+ (iTermParsedExpression *)parsedExpressionWithInterpolatedString:(NSString *)swifty
                                                 escapingFunction:(NSString *(^)(NSString *string))escapingFunction
                                                            scope:(iTermVariableScope *)scope
                                                           strict:(BOOL)strict {
    __block BOOL allLiterals = YES;
    __block NSError *error = nil;
    NSMutableArray *interpolatedParts = [NSMutableArray array];
    [swifty enumerateSwiftySubstrings:^(NSUInteger index, NSString *substring, BOOL isLiteral, BOOL *stop) {
        if (isLiteral) {
            NSString *escapedString = [substring it_stringByExpandingBackslashEscapedCharacters];
            [interpolatedParts addObject:[[iTermParsedExpression alloc] initWithString:escapedString]];
            return;
        }
        allLiterals = NO;

        iTermExpressionParser *parser = [[iTermExpressionParser alloc] initWithStart:@"expression"];
        iTermParsedExpression *expression = [parser parse:substring
                                                    scope:scope];
        if (expression.expressionType == iTermParsedExpressionTypeString && escapingFunction) {
            NSString *escapedString = escapingFunction(expression.string);
            [interpolatedParts addObject:[[iTermParsedExpression alloc] initWithString:escapedString]];
            return;
        }
        if (!strict &&
            [iTermAdvancedSettingsModel laxNilPolicyInInterpolatedStrings] &&
            expression.expressionType == iTermParsedExpressionTypeError) {
            // If the expression was a variable reference, replace it with empty string. This works
            // around the annoyance of remembering to add question marks in interpolated strings,
            // where you know the result you want is always an empty string.
            iTermParsedExpression *expressionWithPlaceholders = [parser parse:substring
                                                                        scope:[[iTermVariablePlaceholderScope alloc] init]];
            if ([expressionWithPlaceholders.object conformsToProtocol:@protocol(iTermExpressionParserPlaceholder)]) {
                expression = [[iTermParsedExpression alloc] initWithString:@""];
            }
        }
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

    if (allLiterals) {
        return [[iTermParsedExpression alloc] initWithString:[swifty it_stringByExpandingBackslashEscapedCharacters]];
    }
    return [self parsedExpressionWithInterpolatedStringParts:interpolatedParts];
}

- (iTermIndirectValue *)indirectValueWithPath:(NSString *)path
                                        index:(iTermSubexpression *)indexExpression {
    if ([path isEqualToString:@"null"] && !indexExpression) {
        return [[iTermIndirectValue alloc] initWithPath:path];
    }
    if (_scope.usePlaceholders) {
        id placeholder;
        if (indexExpression) {
            placeholder = [[iTermExpressionParserArrayDereferencePlaceholder alloc] initWithPath:path
                                                                                 indexExpression:indexExpression];
        } else {
            placeholder = [[iTermExpressionParserVariableReferencePlaceholder alloc] initWithPath:path];
        }
        return [[iTermIndirectValue alloc] initWithValue:placeholder
                                                    path:path];
    }
    id untypedValue = [_scope valueForVariableName:path];
    if (!untypedValue) {
        return [[iTermIndirectValue alloc] initWithPath:path];
    }

    if (!indexExpression) {
        // This is a plain variable reference, e.g. \(name)
        return [[iTermIndirectValue alloc] initWithValue:untypedValue path:path];
    }

    // Succeed iff this is an array dereference, like \(user.myarray[1])
    NSArray *array = [NSArray castFrom:untypedValue];
    if (!array) {
        NSString *reason = [NSString stringWithFormat:@"Variable “%@” is of type %@, not array", path, NSStringFromClass([untypedValue class])];
        return [[iTermIndirectValue alloc] initWithError:reason path:path];
    }

    if (indexExpression.requiresAsyncEvaluation) {
        return [[iTermIndirectValue alloc] initWithArray:array indexExpression:indexExpression];
    } else {
        NSError *error;
        NSNumber *indexValue = [indexExpression synchronousValueWithSideEffectsAllowed:NO scope:_scope error:&error];
        if (error) {
            NSString *reason = [NSString stringWithFormat:@"Error evaluating index expression: %@", error.localizedDescription];
            return [[iTermIndirectValue alloc] initWithError:reason path:path];
        }
        const NSInteger index = indexValue.integerValue;
        if (index < 0 || index >= array.count) {
            NSString *reason = [NSString stringWithFormat:@"Index %@ out of range of “%@”, which has %@ value%@", @(index), path, @(array.count), array.count == 1 ? @"" : @"s"];
            return [[iTermIndirectValue alloc] initWithError:reason path:path];
        }
        return [[iTermIndirectValue alloc] initWithValue:array[index] path:path];
    }
}

- (void)loadRulesAndTransforms {
    __weak __typeof(self) weakSelf = self;

    [_grammarProcessor addProductionRule:@"callsequence ::= <callsequence> ';' <call>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermParsedExpression *callSequence = syntaxTree.children[0];
        iTermParsedExpression *call = syntaxTree.children[2];
        if (call.expressionType == iTermParsedExpressionTypeError) {
            return call;
        }
        if (callSequence.expressionType == iTermParsedExpressionTypeError) {
            return callSequence;
        }
        // Handle both single FunctionCall and FunctionCalls array
        NSArray *existingCalls;
        if (callSequence.expressionType == iTermParsedExpressionTypeFunctionCall) {
            existingCalls = @[callSequence.functionCall];
        } else {
            existingCalls = callSequence.functionCalls;
        }
        return [weakSelf callSequenceWithCalls:[existingCalls arrayByAddingObject:call.functionCall]];
    }];
    [_grammarProcessor addProductionRule:@"callsequence ::= <call>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        // Return the single call directly (not wrapped in array)
        return syntaxTree.children[0];
    }];

    [_grammarProcessor addProductionRule:@"call ::= <path> <arglist>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        NSError *error = nil;
        iTermParsedExpression *result = [weakSelf parsedExpressionForFunctionCallWithFullyQualifiedName:(NSString *)syntaxTree.children[0]
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
    [_grammarProcessor addProductionRule:@"arg ::= 'Identifier' ':' '&' <path>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        NSString *path = syntaxTree.children[3];
        iTermParsedExpression *ref = [weakSelf parsedExpressionWithReferenceToPath:path];
        if ([path isEqualToString:@"null"]) {
            NSError *error = [NSError errorWithDomain:@"com.iterm2.parser"
                                                 code:2
                                             userInfo:@{ NSLocalizedDescriptionKey: @"&null is never allowed" }];
            return [[iTermParsedExpression alloc] initWithError:error];
        }
        [weakSelf indirectValueWithPath:path index:nil];  // just for the recording scope side-effect
        return [weakSelf newFunctionArgumentWithName:[(CPIdentifierToken *)syntaxTree.children[0] identifier]
                                          expression:ref
                                     passByReference:YES];
    }];
    [_grammarProcessor addProductionRule:@"arg ::= 'Identifier' ':' <expression>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return [weakSelf newFunctionArgumentWithName:[(CPIdentifierToken *)syntaxTree.children[0] identifier]
                                          expression:syntaxTree.children[2]
                                     passByReference:NO];
    }];
    [_grammarProcessor addProductionRule:@"expression ::= <Subexpression>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        // Pass through the parsed expression - it's already properly typed
        // (could be Subexpression, IndirectValue, etc.)
        return syntaxTree.children[0];
    }];

    [_grammarProcessor addProductionRule:@"Subexpression ::= <ConditionalExpression>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return syntaxTree.children[0];
    }];
    [_grammarProcessor addProductionRule:@"ConditionalExpression ::= <LogicalOrExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        // Deoptionalize here for expressions without trailing ?.
        // This converts undefined variables (Nil with fallbackError) to errors.
        return [syntaxTree.children[0] deoptionalized];
    }];
    // Left-factored to resolve conflict between optional (path?) and ternary (expr ? a : b)
    // Using EBNF ? syntax: the ternary part (expr : expr) is optional.
    // When it's absent, we have an optional marker (foo?).
    // When present, we have a ternary (foo ? bar : baz).
    [_grammarProcessor addProductionRule:@"ConditionalExpression ::= <LogicalOrExpr> '?' (<ConditionalExpression> ':' <ConditionalExpression>)?"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermParsedExpression *condition = syntaxTree.children[0];
        // When optional group is absent: children = [AddExpr, '?']
        // When optional group is present: children = [AddExpr, '?', groupSyntaxTree]
        // where groupSyntaxTree.children = [trueExpr, ':', falseExpr]
        if (syntaxTree.children.count <= 2) {
            // Optional case: path?
            return [condition optionalized];
        } else {
            // Check if the optional group is present (non-empty array)
            NSArray *outerArr = syntaxTree.children[2];
            if (outerArr.count == 0) {
                // Optional case: path? (the group was matched but is empty)
                return [condition optionalized];
            }
            // Ternary case: condition ? trueExpr : falseExpr
            // CoreParse returns [[trueExpr, ':', falseExpr]] - nested array
            NSArray *innerArr = outerArr[0];
            iTermParsedExpression *trueExpr = innerArr[0];
            iTermParsedExpression *falseExpr = innerArr[2];
            iTermSubexpression *subexpression = [[iTermSubexpression alloc] initCondition:[condition asSubexpression]
                                                                                             whenTrue:[trueExpr asSubexpression]
                                                                                            otherwise:[falseExpr asSubexpression]];
            return [[iTermParsedExpression alloc] initWithSubexpression:subexpression];
        }
    }];

    // LogicalOrExpr: handles || operator
    [_grammarProcessor addProductionRule:@"LogicalOrExpr ::= <LogicalOrExpr> '||' <LogicalAndExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermSubexpression *subexpression = [[iTermSubexpression alloc] init:[syntaxTree.children[0] asSubexpression]
                                                                                logicalOr:[syntaxTree.children[2] asSubexpression]];
        return [[iTermParsedExpression alloc] initWithSubexpression:subexpression];
    }];
    [_grammarProcessor addProductionRule:@"LogicalOrExpr ::= <LogicalAndExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return syntaxTree.children[0];
    }];

    // LogicalAndExpr: handles && operator
    [_grammarProcessor addProductionRule:@"LogicalAndExpr ::= <LogicalAndExpr> '&&' <EqualityExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermSubexpression *subexpression = [[iTermSubexpression alloc] init:[syntaxTree.children[0] asSubexpression]
                                                                               logicalAnd:[syntaxTree.children[2] asSubexpression]];
        return [[iTermParsedExpression alloc] initWithSubexpression:subexpression];
    }];
    [_grammarProcessor addProductionRule:@"LogicalAndExpr ::= <EqualityExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return syntaxTree.children[0];
    }];

    // EqualityExpr: handles == and != operators
    [_grammarProcessor addProductionRule:@"EqualityExpr ::= <EqualityExpr> '==' <RelationalExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermSubexpression *subexpression = [[iTermSubexpression alloc] init:[syntaxTree.children[0] asSubexpression]
                                                                                  equalTo:[syntaxTree.children[2] asSubexpression]];
        return [[iTermParsedExpression alloc] initWithSubexpression:subexpression];
    }];
    [_grammarProcessor addProductionRule:@"EqualityExpr ::= <EqualityExpr> '!=' <RelationalExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermSubexpression *subexpression = [[iTermSubexpression alloc] init:[syntaxTree.children[0] asSubexpression]
                                                                               notEqualTo:[syntaxTree.children[2] asSubexpression]];
        return [[iTermParsedExpression alloc] initWithSubexpression:subexpression];
    }];
    [_grammarProcessor addProductionRule:@"EqualityExpr ::= <RelationalExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return syntaxTree.children[0];
    }];

    // RelationalExpr: handles <, >, <=, >= operators
    [_grammarProcessor addProductionRule:@"RelationalExpr ::= <RelationalExpr> '<' <AddExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermSubexpression *subexpression = [[iTermSubexpression alloc] init:[syntaxTree.children[0] asSubexpression]
                                                                                 lessThan:[syntaxTree.children[2] asSubexpression]];
        return [[iTermParsedExpression alloc] initWithSubexpression:subexpression];
    }];
    [_grammarProcessor addProductionRule:@"RelationalExpr ::= <RelationalExpr> '>' <AddExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermSubexpression *subexpression = [[iTermSubexpression alloc] init:[syntaxTree.children[0] asSubexpression]
                                                                              greaterThan:[syntaxTree.children[2] asSubexpression]];
        return [[iTermParsedExpression alloc] initWithSubexpression:subexpression];
    }];
    [_grammarProcessor addProductionRule:@"RelationalExpr ::= <RelationalExpr> '<=' <AddExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermSubexpression *subexpression = [[iTermSubexpression alloc] init:[syntaxTree.children[0] asSubexpression]
                                                                         lessThanOrEqual:[syntaxTree.children[2] asSubexpression]];
        return [[iTermParsedExpression alloc] initWithSubexpression:subexpression];
    }];
    [_grammarProcessor addProductionRule:@"RelationalExpr ::= <RelationalExpr> '>=' <AddExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermSubexpression *subexpression = [[iTermSubexpression alloc] init:[syntaxTree.children[0] asSubexpression]
                                                                      greaterThanOrEqual:[syntaxTree.children[2] asSubexpression]];
        return [[iTermParsedExpression alloc] initWithSubexpression:subexpression];
    }];
    [_grammarProcessor addProductionRule:@"RelationalExpr ::= <AddExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return syntaxTree.children[0];
    }];

    [_grammarProcessor addProductionRule:@"AddExpr ::= <AddExpr> '+' <MulExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermSubexpression *subexpression = [[iTermSubexpression alloc] init:[syntaxTree.children[0] asSubexpression]
                                                                                    plus:[syntaxTree.children[2] asSubexpression]];
        return [[iTermParsedExpression alloc] initWithSubexpression:subexpression];
    }];
    [_grammarProcessor addProductionRule:@"AddExpr ::= <AddExpr> '-' <MulExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermSubexpression *subexpression = [[iTermSubexpression alloc] init:[syntaxTree.children[0] asSubexpression]
                                                                                   minus:[syntaxTree.children[2] asSubexpression]];
        return [[iTermParsedExpression alloc] initWithSubexpression:subexpression];
    }];
    [_grammarProcessor addProductionRule:@"AddExpr ::= <MulExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return syntaxTree.children[0];
    }];

    [_grammarProcessor addProductionRule:@"MulExpr ::= <MulExpr> '*' <UnaryExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermSubexpression *subexpression = [[iTermSubexpression alloc] init:[syntaxTree.children[0] asSubexpression]
                                                                                   times:[syntaxTree.children[2] asSubexpression]];
        return [[iTermParsedExpression alloc] initWithSubexpression:subexpression];
    }];
    [_grammarProcessor addProductionRule:@"MulExpr ::= <MulExpr> '/' <UnaryExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermSubexpression *subexpression = [[iTermSubexpression alloc] init:[syntaxTree.children[0] asSubexpression]
                                                                               dividedBy:[syntaxTree.children[2] asSubexpression]];
        return [[iTermParsedExpression alloc] initWithSubexpression:subexpression];
    }];
    [_grammarProcessor addProductionRule:@"MulExpr ::= <UnaryExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return syntaxTree.children[0];
    }];

    // UnaryExpr: handles unary ! (logical NOT)
    [_grammarProcessor addProductionRule:@"UnaryExpr ::= <PostfixExpression>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return syntaxTree.children[0];
    }];

    [_grammarProcessor addProductionRule:@"UnaryExpr ::= '!' <UnaryExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermSubexpression *subexpression =
            [[iTermSubexpression alloc] initLogicalNot:[syntaxTree.children[1] asSubexpression]];
        return [[iTermParsedExpression alloc] initWithSubexpression:subexpression];
    }];

    [_grammarProcessor addProductionRule:@"UnaryExpr ::= '-' <UnaryExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermSubexpression *subexpression =
            [[iTermSubexpression alloc] initNegated:[syntaxTree.children[1] asSubexpression]];
        return [[iTermParsedExpression alloc] initWithSubexpression:subexpression];
    }];

    [_grammarProcessor addProductionRule:@"PostfixExpression ::= <PrimaryExpression>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return syntaxTree.children[0];
    }];
    [_grammarProcessor addProductionRule:@"PrimaryExpression ::= <NumericLiteral>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return syntaxTree.children[0];
    }];
    [_grammarProcessor addProductionRule:@"PrimaryExpression ::= <indirect_value>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermIndirectValue *indirectValue = syntaxTree.children[0];
        // Don't deoptionalize here - let ConditionalExpression handle it.
        // This allows foo? to stay optional until the ? is processed.
        return [weakSelf parsedExpressionWithIndirectValue:indirectValue];
    }];
    [_grammarProcessor addProductionRule:@"PrimaryExpression ::= <call>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        // Pass through function call - will be converted to Subexpression
        // by arithmetic operations as needed
        return syntaxTree.children[0];
    }];
    [_grammarProcessor addProductionRule:@"PrimaryExpression ::= '(' <Subexpression> ')'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return syntaxTree.children[1];
    }];



    [_grammarProcessor addProductionRule:@"NumericLiteral ::= 'Number'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        CPNumberToken *number = syntaxTree.children[0];
        return [[iTermParsedExpression alloc] initWithSubexpression:[[iTermSubexpression alloc] initWithNumber:number.numberValue]];
    }];

    [_grammarProcessor addProductionRule:@"PrimaryExpression ::= 'true'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return [[iTermParsedExpression alloc] initWithSubexpression:[[iTermSubexpression alloc] initWithNumber:@YES]];
    }];
    [_grammarProcessor addProductionRule:@"PrimaryExpression ::= 'false'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return [[iTermParsedExpression alloc] initWithSubexpression:[[iTermSubexpression alloc] initWithNumber:@NO]];
    }];
    [_grammarProcessor addProductionRule:@"PrimaryExpression ::= 'SwiftyString'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        NSString *swifty = [(CPQuotedToken *)syntaxTree.children[0] content];
        return [weakSelf parsedExpressionWithInterpolatedString:swifty];
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
    // Note: expression ::= <call> removed because calls are now reachable via
    // expression -> Subexpression -> ... -> PrimaryExpression -> call

    [_grammarProcessor addProductionRule:@"indirect_value ::= <path>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return [weakSelf indirectValueWithPath:syntaxTree.children[0]
                                         index:nil];
    }];
    [_grammarProcessor addProductionRule:@"indirect_value ::= <path> '[' <Subexpression> ']'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermParsedExpression *numberParsedExpression = syntaxTree.children[2];
        iTermSubexpression *indexExpression = [numberParsedExpression asSubexpression];
        if (!indexExpression) {
            // Cannot convert index to numeric expression (e.g., NSNull, string, array)
            NSString *path = syntaxTree.children[0];
            NSString *errorMsg = [NSString stringWithFormat:@"Array index for \"%@\" must be a number, not %@",
                                  path, NSStringFromClass([numberParsedExpression.object class])];
            return [[iTermIndirectValue alloc] initWithError:errorMsg path:path];
        }
        return [weakSelf indirectValueWithPath:syntaxTree.children[0]
                                         index:indexExpression];
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
