//
//  iTermFunctionCallSuggester.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import "iTermFunctionCallSuggester.h"

#import "CPParser+Cache.h"
#import "DebugLogging.h"
#import "iTermExpressionParser+Private.h"
#import "iTermGrammarProcessor.h"
#import "iTermSwiftyStringParser.h"
#import "iTermSwiftyStringRecognizer.h"
#import "iTermTruncatedQuotedRecognizer.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"

@interface iTermFunctionCallSuggester()<CPParserDelegate, CPTokeniserDelegate>
@property (nonatomic, readonly) CPLALR1Parser *parser;
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
        [_tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"="]];

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

- (void)dealloc {
    [_parser it_releaseParser];
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
    return @"callsequence";
}

- (void)loadRulesAndTransforms {
    __weak __typeof(self) weakSelf = self;
    [_grammarProcessor addProductionRule:@"callsequence ::= <incompletecall>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return syntaxTree.children.lastObject;
    }];
    [_grammarProcessor addProductionRule:@"callsequence ::= <completecall> ';' <callsequence>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return syntaxTree.children.lastObject;
    }];

    [_grammarProcessor addProductionRule:@"incompletecall ::= <funcname> <arglist>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [weakSelf callWithName:syntaxTree.children[0]
                                                     arglist:syntaxTree.children[1]];
                           }];
    [_grammarProcessor addProductionRule:@"completecall ::= <funcname> <completearglist>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [weakSelf callWithName:syntaxTree.children[0]
                                                     arglist:syntaxTree.children[1]];
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

    [_grammarProcessor addProductionRule:@"completearglist ::= '(' <args> ')'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"complete-arglist": @YES };
                           }];
    [_grammarProcessor addProductionRule:@"completearglist ::= '(' ')'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"complete-arglist": @YES };
                           }];

    [_grammarProcessor addProductionRule:@"arglist ::= 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"partial-arglist": @YES };
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
    [_grammarProcessor addProductionRule:@"arg ::= <completearg>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        return syntaxTree.children[0];
                           }];
    [_grammarProcessor addProductionRule:@"completearg ::= 'Identifier' ':' '&' <path>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
        NSDictionary *expr = @{ @"path": syntaxTree.children[3] };
        return @{ @"identifier": [syntaxTree.children[0] identifier],
                  @"colon": @YES,
                  @"expression": expr };
    }];
    [_grammarProcessor addProductionRule:@"completearg ::= 'Identifier' ':' <expression>"
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
    // MARK: Hierarchical expression grammar (using right recursion to avoid LALR conflicts)
    // expression → Subexpression (top-level entry point)
    [_grammarProcessor addProductionRule:@"expression ::= <Subexpression>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[0];
                           }];

    // Subexpression → ConditionalExpression
    [_grammarProcessor addProductionRule:@"Subexpression ::= <ConditionalExpression>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[0];
                           }];

    // MARK: Conditional expressions (ternary and optional marker)
    // ConditionalExpression → LogicalOrExpr (base case)
    [_grammarProcessor addProductionRule:@"ConditionalExpression ::= <LogicalOrExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[0];
                           }];

    // ConditionalExpression → LogicalOrExpr '?' (optional marker, terminated)
    [_grammarProcessor addProductionRule:@"ConditionalExpression ::= <LogicalOrExpr> '?'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"terminated": @YES };
                           }];

    // ConditionalExpression → LogicalOrExpr '?' ConditionalExpression ':' ConditionalExpression (complete ternary)
    [_grammarProcessor addProductionRule:@"ConditionalExpression ::= <LogicalOrExpr> '?' <ConditionalExpression> ':' <ConditionalExpression>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               // Return the false branch expression for suggestions
                               return syntaxTree.children[4];
                           }];

    // ConditionalExpression → LogicalOrExpr '?' ConditionalExpression ':' EOF (incomplete false branch)
    [_grammarProcessor addProductionRule:@"ConditionalExpression ::= <LogicalOrExpr> '?' <ConditionalExpression> ':' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"operator_pending": @YES };
                           }];

    // MARK: Logical OR (using right recursion)
    // LogicalOrExpr → LogicalAndExpr (base case)
    [_grammarProcessor addProductionRule:@"LogicalOrExpr ::= <LogicalAndExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[0];
                           }];

    // LogicalOrExpr → LogicalAndExpr '||' LogicalOrExpr (right-recursive)
    [_grammarProcessor addProductionRule:@"LogicalOrExpr ::= <LogicalAndExpr> '||' <LogicalOrExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[2];
                           }];

    // LogicalOrExpr → LogicalAndExpr '||' EOF (incomplete, need RHS)
    [_grammarProcessor addProductionRule:@"LogicalOrExpr ::= <LogicalAndExpr> '||' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"operator_pending": @YES };
                           }];

    // MARK: Logical AND (using right recursion)
    // LogicalAndExpr → EqualityExpr (base case)
    [_grammarProcessor addProductionRule:@"LogicalAndExpr ::= <EqualityExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[0];
                           }];

    // LogicalAndExpr → EqualityExpr '&&' LogicalAndExpr (right-recursive)
    [_grammarProcessor addProductionRule:@"LogicalAndExpr ::= <EqualityExpr> '&&' <LogicalAndExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[2];
                           }];

    // LogicalAndExpr → EqualityExpr '&&' EOF (incomplete, need RHS)
    [_grammarProcessor addProductionRule:@"LogicalAndExpr ::= <EqualityExpr> '&&' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"operator_pending": @YES };
                           }];

    // MARK: Equality (using right recursion)
    // EqualityExpr → RelationalExpr (base case)
    [_grammarProcessor addProductionRule:@"EqualityExpr ::= <RelationalExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[0];
                           }];

    // EqualityExpr → RelationalExpr '==' EqualityExpr (right-recursive equality)
    [_grammarProcessor addProductionRule:@"EqualityExpr ::= <RelationalExpr> '==' <EqualityExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[2];
                           }];

    // EqualityExpr → RelationalExpr '!=' EqualityExpr (right-recursive inequality)
    [_grammarProcessor addProductionRule:@"EqualityExpr ::= <RelationalExpr> '!=' <EqualityExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[2];
                           }];

    // EqualityExpr → RelationalExpr '==' EOF (incomplete, need RHS)
    [_grammarProcessor addProductionRule:@"EqualityExpr ::= <RelationalExpr> '==' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"operator_pending": @YES };
                           }];

    // EqualityExpr → RelationalExpr '!=' EOF (incomplete, need RHS)
    [_grammarProcessor addProductionRule:@"EqualityExpr ::= <RelationalExpr> '!=' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"operator_pending": @YES };
                           }];

    // MARK: Relational (using right recursion)
    // RelationalExpr → AddExpr (base case)
    [_grammarProcessor addProductionRule:@"RelationalExpr ::= <AddExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[0];
                           }];

    // RelationalExpr → AddExpr '<' RelationalExpr (right-recursive less than)
    [_grammarProcessor addProductionRule:@"RelationalExpr ::= <AddExpr> '<' <RelationalExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[2];
                           }];

    // RelationalExpr → AddExpr '>' RelationalExpr (right-recursive greater than)
    [_grammarProcessor addProductionRule:@"RelationalExpr ::= <AddExpr> '>' <RelationalExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[2];
                           }];

    // RelationalExpr → AddExpr '<=' RelationalExpr (right-recursive less than or equal)
    [_grammarProcessor addProductionRule:@"RelationalExpr ::= <AddExpr> '<=' <RelationalExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[2];
                           }];

    // RelationalExpr → AddExpr '>=' RelationalExpr (right-recursive greater than or equal)
    [_grammarProcessor addProductionRule:@"RelationalExpr ::= <AddExpr> '>=' <RelationalExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[2];
                           }];

    // RelationalExpr → AddExpr '<' EOF (incomplete, need RHS)
    [_grammarProcessor addProductionRule:@"RelationalExpr ::= <AddExpr> '<' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"operator_pending": @YES };
                           }];

    // RelationalExpr → AddExpr '>' EOF (incomplete, need RHS)
    [_grammarProcessor addProductionRule:@"RelationalExpr ::= <AddExpr> '>' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"operator_pending": @YES };
                           }];

    // RelationalExpr → AddExpr '<=' EOF (incomplete, need RHS)
    [_grammarProcessor addProductionRule:@"RelationalExpr ::= <AddExpr> '<=' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"operator_pending": @YES };
                           }];

    // RelationalExpr → AddExpr '>=' EOF (incomplete, need RHS)
    [_grammarProcessor addProductionRule:@"RelationalExpr ::= <AddExpr> '>=' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"operator_pending": @YES };
                           }];

    // MARK: Addition/Subtraction (using right recursion)
    // AddExpr → MulExpr (base case)
    [_grammarProcessor addProductionRule:@"AddExpr ::= <MulExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[0];
                           }];

    // AddExpr → MulExpr '+' AddExpr (right-recursive addition)
    [_grammarProcessor addProductionRule:@"AddExpr ::= <MulExpr> '+' <AddExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[2];
                           }];

    // AddExpr → MulExpr '-' AddExpr (right-recursive subtraction)
    [_grammarProcessor addProductionRule:@"AddExpr ::= <MulExpr> '-' <AddExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[2];
                           }];

    // AddExpr → MulExpr '+' EOF (incomplete, need RHS)
    [_grammarProcessor addProductionRule:@"AddExpr ::= <MulExpr> '+' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"operator_pending": @YES };
                           }];

    // AddExpr → MulExpr '-' EOF (incomplete, need RHS)
    [_grammarProcessor addProductionRule:@"AddExpr ::= <MulExpr> '-' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"operator_pending": @YES };
                           }];

    // MARK: Multiplication/Division (using right recursion)
    // MulExpr → UnaryExpr (base case)
    [_grammarProcessor addProductionRule:@"MulExpr ::= <UnaryExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[0];
                           }];

    // MulExpr → UnaryExpr '*' MulExpr (right-recursive multiplication)
    [_grammarProcessor addProductionRule:@"MulExpr ::= <UnaryExpr> '*' <MulExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[2];
                           }];

    // MulExpr → UnaryExpr '/' MulExpr (right-recursive division)
    [_grammarProcessor addProductionRule:@"MulExpr ::= <UnaryExpr> '/' <MulExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[2];
                           }];

    // MulExpr → UnaryExpr '*' EOF (incomplete, need RHS)
    [_grammarProcessor addProductionRule:@"MulExpr ::= <UnaryExpr> '*' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"operator_pending": @YES };
                           }];

    // MulExpr → UnaryExpr '/' EOF (incomplete, need RHS)
    [_grammarProcessor addProductionRule:@"MulExpr ::= <UnaryExpr> '/' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"operator_pending": @YES };
                           }];

    // MARK: Unary expressions (for consistency with iTermExpressionParser)
    // UnaryExpr → PrimaryExpression
    [_grammarProcessor addProductionRule:@"UnaryExpr ::= <PrimaryExpression>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[0];
                           }];

    // UnaryExpr → '!' UnaryExpr (logical NOT, right-recursive)
    [_grammarProcessor addProductionRule:@"UnaryExpr ::= '!' <UnaryExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[1];
                           }];

    // UnaryExpr → '!' EOF (incomplete, need operand)
    [_grammarProcessor addProductionRule:@"UnaryExpr ::= '!' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"operator_pending": @YES };
                           }];

    // UnaryExpr → '-' UnaryExpr (unary negation, right-recursive)
    [_grammarProcessor addProductionRule:@"UnaryExpr ::= '-' <UnaryExpr>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[1];
                           }];

    // UnaryExpr → '-' EOF (incomplete, need operand)
    [_grammarProcessor addProductionRule:@"UnaryExpr ::= '-' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"operator_pending": @YES };
                           }];

    // MARK: Primary expressions (highest precedence)
    // PrimaryExpression → Number
    [_grammarProcessor addProductionRule:@"PrimaryExpression ::= 'Number'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"literal": @YES };
                           }];

    // PrimaryExpression → true (boolean literal)
    [_grammarProcessor addProductionRule:@"PrimaryExpression ::= 'true'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"literal": @YES };
                           }];

    // PrimaryExpression → false (boolean literal)
    [_grammarProcessor addProductionRule:@"PrimaryExpression ::= 'false'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"literal": @YES };
                           }];

    // PrimaryExpression → indirect_value (path with optional array index)
    [_grammarProcessor addProductionRule:@"PrimaryExpression ::= <indirect_value>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[0];
                           }];

    // PrimaryExpression → composed_call (function call)
    [_grammarProcessor addProductionRule:@"PrimaryExpression ::= <composed_call>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"call": syntaxTree.children[0] };
                           }];

    // PrimaryExpression → SwiftyString
    [_grammarProcessor addProductionRule:@"PrimaryExpression ::= 'SwiftyString'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               iTermSwiftyStringToken *token = [iTermSwiftyStringToken castFrom:syntaxTree.children[0]];
                               if (token.truncated && !token.endsWithLiteral) {
                                   return @{ @"truncated_interpolation": token.truncatedPart };
                               } else {
                                   return @{ @"literal": @YES };
                               }
                           }];

    // PrimaryExpression → '(' Subexpression ')' (complete parenthesized)
    [_grammarProcessor addProductionRule:@"PrimaryExpression ::= '(' <Subexpression> ')'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[1];
                           }];

    // PrimaryExpression → '(' Subexpression EOF (incomplete parenthesized)
    [_grammarProcessor addProductionRule:@"PrimaryExpression ::= '(' <Subexpression> 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[1];
                           }];

    // PrimaryExpression → '(' EOF (empty parentheses, need expression)
    [_grammarProcessor addProductionRule:@"PrimaryExpression ::= '(' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"operator_pending": @YES };
                           }];

    // MARK: Indirect values (paths with optional array indexing)
    // indirect_value → path (simple path)
    [_grammarProcessor addProductionRule:@"indirect_value ::= <path>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"path": syntaxTree.children[0] };
                           }];

    // indirect_value → path '[' Subexpression ']' (complete array index)
    [_grammarProcessor addProductionRule:@"indirect_value ::= <path> '[' <Subexpression> ']'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"path": syntaxTree.children[0] };
                           }];

    // indirect_value → path '[' Subexpression EOF (incomplete array index expression)
    [_grammarProcessor addProductionRule:@"indirect_value ::= <path> '[' <Subexpression> 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[2];
                           }];

    // indirect_value → path '[' EOF (empty array index, need expression)
    [_grammarProcessor addProductionRule:@"indirect_value ::= <path> '[' 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"operator_pending": @YES };
                           }];

    // MARK: Array literals
    [_grammarProcessor addProductionRule:@"PrimaryExpression ::= '[' <comma_delimited_expressions> 'EOF'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return [syntaxTree.children[1] dictionaryBySettingObject:@YES forKey:@"inside-truncated-array-literal"];
                           }];
    [_grammarProcessor addProductionRule:@"PrimaryExpression ::= '[' <comma_delimited_expressions> ']'"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return @{ @"literal": @YES };
                           }];
    [_grammarProcessor addProductionRule:@"comma_delimited_expressions ::= <Subexpression>"
                           treeTransform:^id(CPSyntaxTree *syntaxTree) {
                               return syntaxTree.children[0];
                           }];
    [_grammarProcessor addProductionRule:@"comma_delimited_expressions ::= <Subexpression> ',' <comma_delimited_expressions>"
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
// @{ @"operator_pending": @YES } - after arithmetic operator, ternary colon, or open paren
- (NSArray<NSString *> *)suggestedExpressions:(NSDictionary *)expression
                             nextArgumentName:(NSString *)nextArgumentName
                             valuesMustBeArgs:(BOOL)valuesMustBeArgs {
    if (expression == nil || expression[@"literal"] || expression[@"terminated"]) {
        return @[];
    } else if (expression[@"operator_pending"]) {
        // After arithmetic operator, ternary ':', or open paren - suggest all paths and functions
        NSArray<NSString *> *legalPaths = [_pathSource(@"") allObjects];
        return [self pathsAndFunctionSuggestionsWithPrefix:@"" legalPaths:legalPaths];
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
        //
        // Use iTermExpressionSuggester (not iTermFunctionCallSuggester) because the
        // truncated part could be a simple path, not necessarily a function call.
        iTermExpressionSuggester *inner = [[iTermExpressionSuggester alloc] initWithFunctionSignatures:_functionSignatures
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
        NSArray<NSString *> *suggestions = [self pathsAndFunctionSuggestionsWithPrefix:expression[@"path"]
                                                                            legalPaths:legalPaths];
        return suggestions;
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
    DLog(@"Error with input stream %@ when expecting one of %@", inputStream, acceptableTokens);
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
        if (remaining < 0) {
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


@implementation iTermExpressionSuggester

- (NSString *)grammarStart {
    return @"expression";
}

- (NSArray<NSString *> *)parsedResult:(id)result forString:(NSString *)prefix {
    NSArray<NSString *> *suggestions = [self suggestedExpressions:[NSDictionary castFrom:result]
                                                 nextArgumentName:nil
                                                 valuesMustBeArgs:NO];
    return [suggestions mapWithBlock:^id _Nullable(NSString *suffix) {
        return [prefix stringByAppendingString:suffix];
    }];
}

@end
