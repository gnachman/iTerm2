//
//  iTermScriptFunctionCall.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/18/18.
//

#import "iTermScriptFunctionCall.h"

#import "iTermAPIHelper.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

#import <CoreParse/CoreParse.h>

@interface iTermScriptFunctionCall()

@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong, readwrite) NSError *error;

- (void)addParameterWithName:(NSString *)name value:(id)value;

@end

@interface iTermFunctionCallParser : NSObject<CPParserDelegate, CPTokeniserDelegate>
@end

@implementation iTermFunctionCallParser {
    CPTokeniser *_tokenizer;
    CPParser *_parser;
    id (^_source)(NSString *);
    NSError *_error;
    NSString *_input;
}

+ (id<CPTokenRecogniser>)stringRecognizer {
    CPQuotedRecogniser *stringRecogniser = [CPQuotedRecogniser quotedRecogniserWithStartQuote:@"\""
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

- (id)init {
    self = [super init];
    if (self) {
        _tokenizer = [[CPTokeniser alloc] init];

        [_tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"("]];
        [_tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@")"]];
        [_tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@":"]];
        [_tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@","]];
        [_tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"."]];
        [_tokenizer addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"?"]];
        [_tokenizer addTokenRecogniser:[CPNumberRecogniser numberRecogniser]];
        [_tokenizer addTokenRecogniser:[CPWhiteSpaceRecogniser whiteSpaceRecogniser]];
        [_tokenizer addTokenRecogniser:[CPIdentifierRecogniser identifierRecogniser]];
        [_tokenizer addTokenRecogniser:[iTermFunctionCallParser stringRecognizer]];
        [_tokenizer setDelegate:self];

        NSString *bnf =
        @"0  call       ::= 'Identifier' <arglist>;"
        @"1  arglist    ::= '(' <args> ')';"
        @"2  args       ::= <arg>;"
        @"3  args       ::= <arg> ',' <args>;"
        @"4  arg        ::= 'Identifier' ':' <expression>;"
        @"5  expression ::= <path>;"
        @"6  expression ::= <path> '?';"
        @"7  expression ::= 'Number';"
        @"8  expression ::= 'String';"
        @"9  path       ::= 'Identifier';"
        @"10 path       ::= 'Identifier' '.' <path>;";
        NSError *error = nil;
        CPGrammar *grammar = [CPGrammar grammarWithStart:@"call"
                                          backusNaurForm:bnf
                                                   error:&error];
        _parser = [CPSLRParser parserWithGrammar:grammar];
        _parser.delegate = self;
    }
    return self;
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

- (id)parser:(CPParser *)parser didProduceSyntaxTree:(CPSyntaxTree *)syntaxTree {
    NSArray *children = [syntaxTree children];
    switch ([[syntaxTree rule] tag]) {
        case 0: { // <call> ::= 'Identifier' <arglist> -> iTermScriptFunctionCall*
            iTermScriptFunctionCall *call = [[iTermScriptFunctionCall alloc] init];
            call.name = [(CPIdentifierToken *)children[0] identifier];
            for (NSDictionary *arg in children[1]) {
                if (arg[@"value"]) {
                    [call addParameterWithName:arg[@"name"] value:arg[@"value"]];
                } else if (arg[@"error"]) {
                    call.error = [NSError errorWithDomain:@"com.iterm2.parser"
                                                     code:1
                                                 userInfo:@{ NSLocalizedDescriptionKey: arg[@"error"] }];
                }
            }
            return call;
        }

        case 1: {  // arglist ::= '(' <args> ')' -> @[ argdict, ... ]
            return children[1];
        }

        case 2: {  // args ::= <arg> -> @[ argdict ]
            return @[ children[0] ];
        }

        case 3: {  // args ::= <arg> ',' <args> -> @[ argdict, ... ]
            return [@[ children[0] ] arrayByAddingObjectsFromArray:children[2]];
        }

        case 4: {
            // arg ::= 'Identifier' ':' <expression> -> argdict
            //   argdict = {"name":NSString, "value":@{"literal": id}} |
            //             {"name":NSString, "error":NSString}
            NSString *argName = [(CPIdentifierToken *)children[0] identifier];
            id expression = children[2];
            NSDictionary *dict = [NSDictionary castFrom:expression];
            NSString *str = [NSString castFrom:expression];
            BOOL optional = [str hasSuffix:@"?"];
            if (optional) {
                expression = [str substringWithRange:NSMakeRange(0, str.length - 1)];
            }
            id obj = dict[@"literal"];
            if (!obj) {
                obj = _source(expression);
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
        }

        case 5: {  // expression ::= <path> -> NSString
            return children[0];
        }

        case 6: {  // expression ::= <path> '?' -> NSString
            return [children[0] stringByAppendingString:@"?"];
        }

        case 7: {  // expression ::= 'Number' -> @{"literal": id}
            return @{ @"literal": [(CPNumberToken *)children[0] number] };
        }

        case 8: {  // expression ::= 'String' -> @{"literal": id}
            return @{ @"literal": [(CPQuotedToken *)children[0] content] };
        }

        case 9: {  // path ::= 'Identifier' -> NSString
            return [(CPIdentifierToken *)children[0] identifier];
        }

        case 10: {  // path ::= 'Identifier' '.' <path> -> NSString
            return [NSString stringWithFormat:@"%@.%@",
                    [(CPIdentifierToken *)children[0] identifier],
                    children[2]];
        }
    }
    return nil;
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


@implementation iTermScriptFunctionCall {
    NSMutableDictionary<NSString *, id> *_parameters;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _parameters = [NSMutableDictionary dictionary];
    }
    return self;
}

+ (void)callFunction:(NSString *)invocation
              source:(id (^)(NSString *))source
          completion:(void (^)(id, NSError *))completion {
    iTermScriptFunctionCall *call = [[[iTermFunctionCallParser alloc] init] parse:invocation
                                                                           source:source];
    [call callWithCompletion:completion];
}

- (void)addParameterWithName:(NSString *)name value:(id)value {
    _parameters[name] = value;
}

- (void)callWithCompletion:(void (^)(id, NSError *))completion {
    if (self.error) {
        completion(nil, self.error);
    } else {
        [[iTermAPIHelper sharedInstance] dispatchRPCWithName:self.name
                                                   arguments:_parameters
                                                  completion:completion];
    }
}

@end
