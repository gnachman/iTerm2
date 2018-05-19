//
//  iTermScriptFunctionCall.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/18/18.
//

#import "iTermScriptFunctionCall.h"

#import "iTermAPIHelper.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
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
        @"2  arglist    ::= '(' ')';"
        @"3  args       ::= <arg>;"
        @"4  args       ::= <arg> ',' <args>;"
        @"5  arg        ::= 'Identifier' ':' <expression>;"
        @"6  expression ::= <path>;"
        @"7  expression ::= <path> '?';"
        @"8  expression ::= 'Number';"
        @"9  expression ::= 'String';"
        @"10 expression ::= <call>;"
        @"11 path       ::= 'Identifier';"
        @"12 path       ::= 'Identifier' '.' <path>;";
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
                } else if (arg[@"call"]) {
                    [call addParameterWithName:arg[@"name"] value:arg[@"call"]];
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

        case 2: {  // arglist ::= '(' ')' -> @[ argdict, ... ]
            return @[];
        }

        case 3: {  // args ::= <arg> -> @[ argdict ]
            return @[ children[0] ];
        }

        case 4: {  // args ::= <arg> ',' <args> -> @[ argdict, ... ]
            return [@[ children[0] ] arrayByAddingObjectsFromArray:children[2]];
        }

        case 5: {
            // arg ::= 'Identifier' ':' <expression> -> argdict
            //   argdict = {"name":NSString, "value":@{"literal": id}} |
            //             {"name":NSString, "error":NSString}
            NSString *argName = [(CPIdentifierToken *)children[0] identifier];
            id expression = children[2];
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

        case 6: {  // expression ::= <path> -> NSString
            return children[0];
        }

        case 7: {  // expression ::= <path> '?' -> NSString
            return [children[0] stringByAppendingString:@"?"];
        }

        case 8: {  // expression ::= 'Number' -> @{"literal": id}
            return @{ @"literal": [(CPNumberToken *)children[0] number] };
        }

        case 9: {  // expression ::= 'String' -> @{"literal": id}
            return @{ @"literal": [(CPQuotedToken *)children[0] content] };
        }

        case 10: {  // expression ::= <call> -> iTermScriptFunctionCall*
            return children[0];
        }

        case 11: {  // path ::= 'Identifier' -> NSString
            return [(CPIdentifierToken *)children[0] identifier];
        }

        case 12: {  // path ::= 'Identifier' '.' <path> -> NSString
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
    NSMutableDictionary<NSString *, iTermScriptFunctionCall *> *_dependencies;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _parameters = [NSMutableDictionary dictionary];
        _dependencies = [NSMutableDictionary dictionary];
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
    iTermScriptFunctionCall *call = [iTermScriptFunctionCall castFrom:value];
    if (call) {
        _dependencies[name] = call;
    }
}

- (void)callWithCompletion:(void (^)(id, NSError *))completion {
    if (self.error) {
        completion(nil, self.error);
    } else {
        dispatch_group_t group = dispatch_group_create();
        [self resolveDependenciesWithGroup:group];
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            [[iTermAPIHelper sharedInstance] dispatchRPCWithName:self.name
                                                       arguments:self->_parameters
                                                      completion:completion];
        });
    }
}

- (void)resolveDependenciesWithGroup:(dispatch_group_t)group {
    [_dependencies enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, iTermScriptFunctionCall * _Nonnull call, BOOL * _Nonnull stop) {
        if (self.error) {
            *stop = YES;
        }
        dispatch_group_enter(group);
        [call callWithCompletion:^(id result, NSError *error) {
            if (error) {
                NSString *reason = [NSString stringWithFormat:@"In call to %@: %@", call.name, error.localizedDescription];
                NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: reason };

                NSString *traceback = error.localizedFailureReason;
                if (traceback) {
                    userInfo = [userInfo dictionaryBySettingObject:traceback forKey:NSLocalizedFailureReasonErrorKey];
                }

                self.error = [NSError errorWithDomain:@"com.iterm2.call"
                                                 code:1
                                             userInfo:userInfo];
            } else {
                self->_parameters[key] = result;
            }
            dispatch_group_leave(group);
        }];
    }];
}

@end
