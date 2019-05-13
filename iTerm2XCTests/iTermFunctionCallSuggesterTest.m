//
//  iTermFunctionCallSuggesterTest.m
//  iTerm2XCTests
//
//  Created by George Nachman on 6/12/18.
//

#import <XCTest/XCTest.h>
#import "iTermFunctionCallSuggester.h"
#import "iTermExpressionParser.h"
#import "iTermExpressionParser+Private.h"
#import "iTermParsedExpression+Tests.h"
#import "iTermScriptFunctionCall+Private.h"
#import "iTermVariableScope.h"

@interface iTermExpressionParser(Testing)
- (instancetype)initPrivate;
@end

@interface iTermFunctionCallSuggester(Testing)
- (CPLALR1Parser *)parser;
@end

@interface iTermFunctionCallSuggesterTest : XCTestCase

@end

@implementation iTermFunctionCallSuggesterTest {
    iTermExpressionParser *_parser;
    iTermFunctionCallSuggester *_suggester;
}

- (void)setUp {
    [super setUp];

    NSDictionary *signatures = @{ @"func1": @[ @"arg1", @"arg2" ],
                                  @"func2": @[ ] };
    NSArray *paths = @[ @"path.first", @"path.second", @"third" ];
    _suggester =
        [[iTermFunctionCallSuggester alloc] initWithFunctionSignatures:signatures
                                                            pathSource:^NSSet<NSString *> *(NSString *prefix) {
                                                                return [NSSet setWithArray:paths];
                                                            }];

    _parser = [iTermExpressionParser expressionParser];
}

- (void)tearDown {
    [_suggester release];
}

- (void)testSuggestFunctionName {
    NSArray<NSString *> *actual = [_suggester suggestionsForString:@"f"];
    NSArray<NSString *> *expected = @[ @"func1(arg1:", @"func2()" ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testParseFunctionCallWithStringLiteral {
    NSString *code = @"func(x: \"foo\")";
    iTermVariableScope *scope = [[[iTermVariableScope alloc] init] autorelease];
    [scope addVariables:[[[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextNone owner:self] autorelease]
           toScopeNamed:nil];
    iTermParsedExpression *actual = [_parser parse:code
                                             scope:scope];
    iTermScriptFunctionCall *functionCall = [[iTermScriptFunctionCall alloc] init];
    functionCall.name = @"func";
    [functionCall addParameterWithName:@"x" parsedExpression:[[iTermParsedExpression alloc] initWithInterpolatedStringParts:@[ [[iTermParsedExpression alloc] initWithString:@"foo"] ]]];
    iTermParsedExpression *expected = [[iTermParsedExpression alloc] initWithFunctionCall:functionCall];

    XCTAssertEqualObjects(actual, expected);
}

- (void)testParseFunctionCallWithSwiftyString {
    iTermVariableScope *scope = [[[iTermVariableScope alloc] init] autorelease];
    [scope addVariables:[[[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextNone owner:self] autorelease]
           toScopeNamed:nil];
    [scope setValue:@"value" forVariableNamed:@"path"];
    NSString *code = @"func(x: \"foo\\(path)bar\")";
    iTermParsedExpression *actual = [_parser parse:code
                                             scope:scope];
    iTermScriptFunctionCall *functionCall = [[iTermScriptFunctionCall alloc] init];
    functionCall.name = @"func";
    [functionCall addParameterWithName:@"x" parsedExpression:[[iTermParsedExpression alloc] initWithInterpolatedStringParts:@[ [[iTermParsedExpression alloc] initWithString:@"foovaluebar"] ]]];
    iTermParsedExpression *expected = [[iTermParsedExpression alloc] initWithFunctionCall:functionCall];

    XCTAssertEqualObjects(actual, expected);
}

- (void)testParseFunctionCallWithNestedSwiftyString {
    // func(                                                      )
    //      x: "foo\(                                        )bar"
    //               inner(                                 )
    //                     s: "Hello \(     ), how are you?"
    //                                 world

    iTermVariableScope *scope = [[[iTermVariableScope alloc] init] autorelease];
    [scope addVariables:[[[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextNone owner:self] autorelease]
           toScopeNamed:nil];
    [scope setValue:@"WORLD" forVariableNamed:@"world"];

    NSString *code = @"func(x: \"foo\\(inner(s: \"Hello \\(world), how are you?\"))bar\")";
    iTermParsedExpression *actual = [_parser parse:code
                                             scope:scope];
    iTermScriptFunctionCall *functionCall = [[iTermScriptFunctionCall alloc] init];
    functionCall.name = @"inner";
    iTermParsedExpression *sParsedExpression = [[iTermParsedExpression alloc] initWithInterpolatedStringParts:@[ [[iTermParsedExpression alloc] initWithString:@"Hello WORLD, how are you?"] ]];
    [functionCall addParameterWithName:@"s" parsedExpression:sParsedExpression];
    iTermParsedExpression *innerCall = [[iTermParsedExpression alloc] initWithFunctionCall:functionCall];

    iTermParsedExpression *xValue = [[iTermParsedExpression alloc] initWithInterpolatedStringParts:@[ [[iTermParsedExpression alloc] initWithString:@"foo"],
                                                                                                      innerCall,
                                                                                                      [[iTermParsedExpression alloc] initWithString:@"bar"] ]];

    functionCall = [[iTermScriptFunctionCall alloc] init];
    functionCall.name = @"func";
    [functionCall addParameterWithName:@"x" parsedExpression:xValue];
    iTermParsedExpression *expected = [[iTermParsedExpression alloc] initWithFunctionCall:functionCall];

    XCTAssertEqualObjects(actual, expected);
}

- (void)testParserReuse {
    NSDictionary *signatures = @{ @"func1": @[ @"arg1", @"arg2" ],
                                  @"func2": @[ ] };
    NSArray *paths = @[ @"path.first", @"path.second", @"third" ];

    CPLALR1Parser *firstInnerParser;
    @autoreleasepool {
        iTermFunctionCallSuggester *suggester =
        [[iTermFunctionCallSuggester alloc] initWithFunctionSignatures:signatures
                                                            pathSource:^NSSet<NSString *> *(NSString *prefix) {
                                                                return [NSSet setWithArray:paths];
                                                            }];
        firstInnerParser = suggester.parser;
        [suggester release];
    }

    CPLALR1Parser *secondInnerParser;
    @autoreleasepool {
        iTermFunctionCallSuggester *suggester =
        [[iTermFunctionCallSuggester alloc] initWithFunctionSignatures:signatures
                                                            pathSource:^NSSet<NSString *> *(NSString *prefix) {
                                                                return [NSSet setWithArray:paths];
                                                            }];
        secondInnerParser = suggester.parser;
        [suggester release];
    }

    XCTAssertEqual(firstInnerParser, secondInnerParser);
}
@end
