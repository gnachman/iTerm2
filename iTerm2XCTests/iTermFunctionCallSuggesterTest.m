//
//  iTermFunctionCallSuggesterTest.m
//  iTerm2XCTests
//
//  Created by George Nachman on 6/12/18.
//

#import <XCTest/XCTest.h>
#import "iTermFunctionCallSuggester.h"
#import "iTermFunctionCallParser.h"
#import "iTermParsedExpression+Tests.h"
#import "iTermScriptFunctionCall+Private.h"
#import "iTermVariableScope.h"

@interface iTermFunctionCallParser(Testing)
- (instancetype)initPrivate;
@end

@interface iTermFunctionCallSuggesterTest : XCTestCase

@end

@implementation iTermFunctionCallSuggesterTest {
    iTermFunctionCallParser *_parser;
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

    _parser = [[iTermFunctionCallParser alloc] initWithStart:@"expression"];
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
    [functionCall addParameterWithName:@"x" value:@"foo"];
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
    [functionCall addParameterWithName:@"x" value:@"foovaluebar"];
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
    [functionCall addParameterWithName:@"s" value:@"Hello WORLD, how are you?"];
    iTermParsedExpression *innerCall = [[iTermParsedExpression alloc] initWithFunctionCall:functionCall];

    iTermParsedExpression *xValue = [[iTermParsedExpression alloc] initWithInterpolatedStringParts:@[ @"foo", innerCall, @"bar" ]];

    functionCall = [[iTermScriptFunctionCall alloc] init];
    functionCall.name = @"func";
    [functionCall addParameterWithName:@"x" value:xValue];
    iTermParsedExpression *expected = [[iTermParsedExpression alloc] initWithFunctionCall:functionCall];

    XCTAssertEqualObjects(actual, expected);
}

@end
