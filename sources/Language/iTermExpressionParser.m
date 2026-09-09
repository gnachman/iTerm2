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
                                         userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedStringWithDefaultValue(@"ExpressionParser.ExpectedFunctionCallNotValue", nil, [NSBundle mainBundle], @"Expected function call, not a value", @"Error when a function call was expected but a value was found") }];
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
                                         userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedStringWithDefaultValue(@"ExpressionParser.ExpectedSingleFunctionCall", nil, [NSBundle mainBundle], @"Expected single function call", @"Error when a single function call was expected but multiple were found") }];
            }
            return nil;

        case iTermParsedExpressionTypeNil:
            if (error) {
                *error = [NSError errorWithDomain:@"com.iterm2.call"
                                             code:3
                                         userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedStringWithDefaultValue(@"ExpressionParser.ExpectedFunctionCallNotNil", nil, [NSBundle mainBundle], @"Expected function call, not nil", @"Error when a function call was expected but nil was found") }];
            }
            return nil;
        case iTermParsedExpressionTypeInterpolatedString:
            if (error) {
                *error = [NSError errorWithDomain:@"com.iterm2.call"
                                             code:3
                                         userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedStringWithDefaultValue(@"ExpressionParser.ExpectedFunctionCallNotInterpolatedString", nil, [NSBundle mainBundle], @"Expected function call, not an interpolated string", @"Error when a function call was expected but an interpolated string was found") }];
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

    // OptionalPath must come first — matches "name?" (no space before ?)
    // as a single token, before identifier or ? keyword recognizers can split it.
    [tokenizer addTokenRecogniser:[iTermOptionalPathRecognizer recognizer]];

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
        return [[iTermParsedExpression alloc] initWithErrorCode:3 reason:[NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ExpressionParser.CantFormReference", nil, [NSBundle mainBundle], @"Can’t form reference to non-existent or read-only container for variable %@", @"Error when a reference cannot be formed for a variable; placeholder is the path"), path]];
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

    // The 'null' literal is a valid Nil expression with no fallback error.
    if ([indirectValue.path isEqualToString:@"null"] && indirectValue.value == nil) {
        return [[iTermParsedExpression alloc] initWithExpressionType:iTermParsedExpressionTypeNil
                                                              object:nil
                                                            optional:NO];
    }

    // For undefined variables, set a fallback error but do NOT auto-optionalize.
    // The user must write "var?" explicitly to treat undefined as null.
    // The ConditionalExpression '?' rule will optionalize when appropriate.
    NSString *fallbackError;
    fallbackError = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ExpressionParser.ReferenceToUndefinedVariable", nil, [NSBundle mainBundle], @"Reference to undefined variable “%1$@”. Change it to “%2$@?” to treat the undefined value as null.", @"Error when referencing an undefined variable; both placeholders are the variable path"), indirectValue.path, indirectValue.path];
    return [[iTermParsedExpression alloc] initWithObject:indirectValue.value
                                              errorReason:fallbackError];
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
    return [self parsedExpressionWithInterpolatedString:swifty
                                       escapingFunction:escapingFunction
                                                  scope:scope
                                                 strict:strict
                             annotateUndefinedVariables:NO];
}

+ (iTermParsedExpression *)parsedExpressionWithInterpolatedString:(NSString *)swifty
                                                 escapingFunction:(NSString *(^)(NSString *string))escapingFunction
                                                            scope:(iTermVariableScope *)scope
                                                           strict:(BOOL)strict
                                       annotateUndefinedVariables:(BOOL)annotateUndefinedVariables {
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
        const BOOL laxNilPolicy = (!strict && [iTermAdvancedSettingsModel laxNilPolicyInInterpolatedStrings]);
        if ((annotateUndefinedVariables || laxNilPolicy) &&
            expression.expressionType == iTermParsedExpressionTypeError) {
            // The expression failed to evaluate. If it was a bare variable reference (as opposed to,
            // say, a syntax error or a failing function call), that means it referenced an undefined
            // variable. Reparsing against a placeholder scope tells us whether it was a reference.
            iTermParsedExpression *expressionWithPlaceholders = [parser parse:substring
                                                                        scope:[[iTermVariablePlaceholderScope alloc] init]];
            if ([expressionWithPlaceholders.object conformsToProtocol:@protocol(iTermExpressionParserPlaceholder)]) {
                if (annotateUndefinedVariables) {
                    // Make the undefined reference obvious inline instead of hiding it. This helps
                    // when authoring interpolated strings (e.g. status bar components) where a blank
                    // result is indistinguishable from a typo.
                    NSString *path = [substring stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    NSString *annotation = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ExpressionParser.UndefAnnotation", nil, [NSBundle mainBundle], @"[undef: %@]", @"Inline annotation shown for an undefined variable reference; placeholder is the path"), path];
                    expression = [[iTermParsedExpression alloc] initWithString:annotation];
                } else {
                    // laxNilPolicy: replace the reference with empty string. This works around the
                    // annoyance of remembering to add question marks in interpolated strings, where
                    // you know the result you want is always an empty string.
                    expression = [[iTermParsedExpression alloc] initWithString:@""];
                }
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
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ExpressionParser.VariableNotArray", nil, [NSBundle mainBundle], @"Variable “%1$@” is of type %2$@, not array", @"Error when indexing a variable that is not an array; placeholders are the path and the actual type"), path, NSStringFromClass([untypedValue class])];
        return [[iTermIndirectValue alloc] initWithError:reason path:path];
    }

    if (indexExpression.requiresAsyncEvaluation) {
        return [[iTermIndirectValue alloc] initWithArray:array indexExpression:indexExpression];
    } else {
        NSError *error;
        NSNumber *indexValue = [indexExpression synchronousValueWithSideEffectsAllowed:NO scope:_scope error:&error];
        if (error) {
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ExpressionParser.ErrorEvaluatingIndex", nil, [NSBundle mainBundle], @"Error evaluating index expression: %@", @"Error when an array index expression fails to evaluate; placeholder is the error description"), error.localizedDescription];
            return [[iTermIndirectValue alloc] initWithError:reason path:path];
        }
        const NSInteger index = indexValue.integerValue;
        if (index < 0 || index >= array.count) {
            NSString *reason = (array.count == 1)
                ? [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ExpressionParser.IndexOutOfRangeOneValue", nil, [NSBundle mainBundle], @"Index %1$@ out of range of “%2$@”, which has 1 value", @"Expression parser error; %1$@ is the index, %2$@ is the path"), @(index), path]
                : [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ExpressionParser.IndexOutOfRange", nil, [NSBundle mainBundle], @"Index %1$@ out of range of “%2$@”, which has %3$@ values", @"Expression parser error; %1$@ is the index, %2$@ is the path, %3$@ is the number of values"), @(index), path, @(array.count)];
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
                                             userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedStringWithDefaultValue(@"ExpressionParser.NullNeverAllowed", nil, [NSBundle mainBundle], @"&null is never allowed", @"Error when &null is used as a pass-by-reference argument") }];
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
    // Rule 1: Passthrough — no trailing ?. Deoptionalize to convert undefined vars to errors.
    [_grammarProcessor addProductionRule:@"ConditionalExpression ::= <LogicalOrExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return [syntaxTree.children[0] deoptionalized];
    }];

    // Rule 2: Plain ternary — expr ? trueExpr : falseExpr
    [_grammarProcessor addProductionRule:@"ConditionalExpression ::= <LogicalOrExpr> '?' <ConditionalExpression> ':' <ConditionalExpression>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermParsedExpression *condition = syntaxTree.children[0];
        iTermParsedExpression *trueExpr = syntaxTree.children[2];
        iTermParsedExpression *falseExpr = syntaxTree.children[4];
        iTermSubexpression *subexpression = [[iTermSubexpression alloc] initCondition:[condition asSubexpression]
                                                                                         whenTrue:[trueExpr asSubexpression]
                                                                                        otherwise:[falseExpr asSubexpression]];
        return [[iTermParsedExpression alloc] initWithSubexpression:subexpression];
    }];

    // Standalone optional with space — expr ? (no ternary branch).
    // The preferred form is "expr?" (no space), which is handled by the OptionalPath token
    // at the PrimaryExpression level. This rule provides backward compatibility for "expr ?"
    // with a space.
    [_grammarProcessor addProductionRule:@"ConditionalExpression ::= <LogicalOrExpr> '?'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return [syntaxTree.children[0] optionalized];
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

    // OptionalPath token: "name?" or "user.path?" (no space before ?).
    // Handled at PrimaryExpression level so it can participate in ==, !=, etc.
    [_grammarProcessor addProductionRule:@"PrimaryExpression ::= 'OptionalPath'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        iTermOptionalPathToken *token = syntaxTree.children[0];
        NSString *path = token.identifier;
        iTermIndirectValue *indirectValue = [weakSelf indirectValueWithPath:path index:nil];
        iTermParsedExpression *expr = [weakSelf parsedExpressionWithIndirectValue:indirectValue];
        return [expr optionalized];
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
            NSString *errorMsg = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ExpressionParser.ArrayIndexMustBeNumber", nil, [NSBundle mainBundle], @"Array index for “%1$@” must be a number, not %2$@", @"Error when an array index is not a number; placeholders are the path and the actual type"),
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
                                     userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedStringWithDefaultValue(@"ExpressionParser.SyntaxError", nil, [NSBundle mainBundle], @"Syntax error", @"Error when an expression cannot be parsed") }];
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
        // Localization unneeded
        return [NSString stringWithFormat:@"“%@”", anObject];
    }];
    NSString *expectedString = [quotedExpected componentsJoinedByString:@", "];
    NSString *reason = (quotedExpected.count > 1)
        ? [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ExpressionParser.SyntaxErrorExpectedOneOf", nil, [NSBundle mainBundle], @"Syntax error at index %1$@ of “%2$@”. Expected one of: %3$@", @"Expression parser error; %1$@ is the index, %2$@ is the input, %3$@ is the list of expected tokens"), @(inputStream.peekToken.characterNumber), _input, expectedString]
        : [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ExpressionParser.SyntaxErrorExpected", nil, [NSBundle mainBundle], @"Syntax error at index %1$@ of “%2$@”. Expected: %3$@", @"Expression parser error; %1$@ is the index, %2$@ is the input, %3$@ is the expected token"), @(inputStream.peekToken.characterNumber), _input, expectedString];
    _error = [NSError errorWithDomain:@"com.iterm2.parser"
                                 code:3
                             userInfo:@{ NSLocalizedDescriptionKey: reason }];
    return [CPRecoveryAction recoveryActionStop];
}

@end
