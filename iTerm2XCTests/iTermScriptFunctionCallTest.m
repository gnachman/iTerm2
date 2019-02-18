//
//  iTermScriptFunctionCallTest.m
//  iTerm2XCTests
//
//  Created by George Nachman on 2/17/19.
//

#import <XCTest/XCTest.h>
#import "iTermBuiltInFunctions.h"
#import "iTermFunctionCallParser.h"
#import "iTermScriptFunctionCall.h"
#import "iTermVariableScope.h"

@interface iTermScriptFunctionCallTest : XCTestCase

@end

@implementation iTermScriptFunctionCallTest {
    id _savedBIFs;
    iTermVariableScope *_scope;
}

- (void)setUp {
    _savedBIFs = [[iTermBuiltInFunctions sharedInstance] savedState];
    iTermBuiltInFunction *add = [[iTermBuiltInFunction alloc] initWithName:@"add"
                                                                 arguments:@{ @"x": [NSNumber class], @"y": [NSNumber class] }
                                                             defaultValues:@{}
                                                                   context:iTermVariablesSuggestionContextNone
                                                                     block:^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock  _Nonnull completion) {
                                                                         id result = @([parameters[@"x"] integerValue] + [parameters[@"y"] integerValue]);
                                                                         completion(result, nil);
                                                                     }];
    [[iTermBuiltInFunctions sharedInstance] registerFunction:add namespace:nil];

    iTermBuiltInFunction *mult = [[iTermBuiltInFunction alloc] initWithName:@"mult"
                                                                  arguments:@{ @"x": [NSNumber class], @"y": [NSNumber class] }
                                                              defaultValues:@{}
                                                                    context:iTermVariablesSuggestionContextNone
                                                                      block:^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock  _Nonnull completion) {
                                                                          id result = @([parameters[@"x"] integerValue] * [parameters[@"y"] integerValue]);
                                                                          completion(result, nil);
                                                                      }];
    [[iTermBuiltInFunctions sharedInstance] registerFunction:mult namespace:nil];

    iTermBuiltInFunction *cat = [[iTermBuiltInFunction alloc] initWithName:@"cat"
                                                                  arguments:@{ @"x": [NSString class], @"y": [NSString class] }
                                                              defaultValues:@{}
                                                                    context:iTermVariablesSuggestionContextNone
                                                                      block:^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock  _Nonnull completion) {
                                                                          id result = [parameters[@"x"] stringByAppendingString:parameters[@"y"]];
                                                                          completion(result, nil);
                                                                      }];
    [[iTermBuiltInFunctions sharedInstance] registerFunction:cat namespace:nil];

    iTermBuiltInFunction *s = [[iTermBuiltInFunction alloc] initWithName:@"s"
                                                               arguments:@{}
                                                             defaultValues:@{}
                                                                   context:iTermVariablesSuggestionContextNone
                                                                     block:^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock  _Nonnull completion) {
                                                                         completion(@"string", nil);
                                                                     }];
    [[iTermBuiltInFunctions sharedInstance] registerFunction:s namespace:nil];

    iTermBuiltInFunction *a = [[iTermBuiltInFunction alloc] initWithName:@"a"
                                                               arguments:@{}
                                                           defaultValues:@{}
                                                                 context:iTermVariablesSuggestionContextNone
                                                                   block:^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock  _Nonnull completion) {
                                                                       completion(@[ @1, @"foo" ], nil);
                                                                   }];
    [[iTermBuiltInFunctions sharedInstance] registerFunction:a namespace:nil];

    _scope = [[iTermVariableScope alloc] init];
    iTermVariables *variables = [[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextNone owner:self];
    [_scope addVariables:variables toScopeNamed:nil];
}

- (void)tearDown {
    [[iTermBuiltInFunctions sharedInstance] restoreState:_savedBIFs];
}

- (void)testSignature {
    iTermFunctionCallParser *parser = [iTermFunctionCallParser callParser];
    iTermVariableScope *scope = [[iTermVariableScope alloc] init];
    iTermParsedExpression *expression = [parser parse:@"add(x:1, y:2)" scope:scope];
    XCTAssertEqual(expression.expressionType, iTermParsedExpressionTypeFunctionCall);
    XCTAssertEqualObjects(expression.functionCall.signature, @"add(x,y)");
}

- (void)withAddFunction:(void (^)(void))block {

}

#pragma mark - Test evaluateExpression:timeout:scope:completion:

- (void)testEvaluateExpressionFunction {
    __block id output;

    [iTermScriptFunctionCall evaluateExpression:@"add(x: 1, y: 2)"
                                        timeout:0
                                          scope:_scope
                                     completion:^(id result, NSError *error, NSSet<NSString *> *missingFunctionSignatures) {
                                         output = result;
                                         XCTAssertNil(error);
                                         XCTAssertEqual(0, missingFunctionSignatures.count);
                                     }];
    XCTAssertEqualObjects(output, @3);
}

- (void)testEvaluateExpressionFunctionComposition {
    __block id output;

    [iTermScriptFunctionCall evaluateExpression:@"add(x: 1, y: mult(x: 2, y: 3))"
                                        timeout:0
                                          scope:_scope
                                     completion:^(id result, NSError *error, NSSet<NSString *> *missingFunctionSignatures) {
                                         output = result;
                                         XCTAssertNil(error);
                                         XCTAssertEqual(0, missingFunctionSignatures.count);
                                     }];
    XCTAssertEqualObjects(output, @7);
}

- (void)testEvaluateExpressionUndefinedFunction {
    XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"evaluate function call"];
    [iTermScriptFunctionCall evaluateExpression:@"add(x: 1, y: bogus(x: 2, y: 3))"
                                        timeout:INFINITY
                                          scope:_scope
                                     completion:^(id result, NSError *error, NSSet<NSString *> *missingFunctionSignatures) {
                                         XCTAssertNil(result);
                                         XCTAssertNotNil(error);
                                         XCTAssertEqualObjects(missingFunctionSignatures.allObjects, @[ @"bogus(x,y)" ]);
                                         [expectation fulfill];
                                     }];
    [self waitForExpectations:@[expectation] timeout:3600];
}

- (void)testEvaluateExpressionStringVariable {
    [_scope setValue:@"xyz" forVariableNamed:@"foo"];

    __block id output;
    [iTermScriptFunctionCall evaluateExpression:@"foo"
                                        timeout:0
                                          scope:_scope
                                     completion:^(id result, NSError *error, NSSet<NSString *> *missingFunctionSignatures) {
                                         output = result;
                                         XCTAssertNil(error);
                                         XCTAssertEqual(0, missingFunctionSignatures.count);
                                     }];
    XCTAssertEqualObjects(output, @"xyz");
}

- (void)testEvaluateExpressionStringLiteral {
    __block id output;
    [iTermScriptFunctionCall evaluateExpression:@"\"foo\""
                                        timeout:0
                                          scope:_scope
                                     completion:^(id result, NSError *error, NSSet<NSString *> *missingFunctionSignatures) {
                                         output = result;
                                         XCTAssertNil(error);
                                         XCTAssertEqual(0, missingFunctionSignatures.count);
                                     }];
    XCTAssertEqualObjects(output, @"foo");
}

- (void)testEvaluateExpressionNumberLiteral {
    __block id output;
    [iTermScriptFunctionCall evaluateExpression:@"42"
                                        timeout:0
                                          scope:_scope
                                     completion:^(id result, NSError *error, NSSet<NSString *> *missingFunctionSignatures) {
                                         output = result;
                                         XCTAssertNil(error);
                                         XCTAssertEqual(0, missingFunctionSignatures.count);
                                     }];
    XCTAssertEqualObjects(output, @42);
}

- (void)testEvaluateExpressionInterpolatedString {
    [_scope setValue:@"the sum is" forVariableNamed:@"label"];
    [_scope setValue:@1 forVariableNamed:@"one"];
    [_scope setValue:@[@0, @1, @2, @3] forVariableNamed:@"array"];

    __block id output;
    [iTermScriptFunctionCall evaluateExpression:@"\"I found that \\(label) equal to \\(add(x: one, y: array[2]))\""
                                        timeout:0
                                          scope:_scope
                                     completion:^(id result, NSError *error, NSSet<NSString *> *missingFunctionSignatures) {
                                         output = result;
                                         XCTAssertNil(error);
                                         XCTAssertEqual(0, missingFunctionSignatures.count);
                                     }];
    XCTAssertEqualObjects(output, @"I found that the sum is equal to 3");
}

- (void)testEvaluateExpressionNestedInterpolatedString {
    [_scope setValue:@"the sum is" forVariableNamed:@"label"];
    [_scope setValue:@1 forVariableNamed:@"one"];
    [_scope setValue:@[@0, @1, @2, @3] forVariableNamed:@"array"];

    __block id output;
    NSString *const expression =
    @"\"start-top \\("
    @"    cat(x: \"outer-cat-x\","
    @"        y: \"begin-outer-cat-y \\("
    @"                cat(x: \"inner-cat-x\", "
    @"                    y: \"inner-cat-y\")"
    @"            ) end-outer-cat-y\")"
    @"    ) end-outer\"";
    [iTermScriptFunctionCall evaluateExpression:expression
                                        timeout:0
                                          scope:_scope
                                     completion:^(id result, NSError *error, NSSet<NSString *> *missingFunctionSignatures) {
                                         output = result;
                                         XCTAssertNil(error);
                                         XCTAssertEqual(0, missingFunctionSignatures.count);
                                     }];
    XCTAssertEqualObjects(output, @"start-top outer-cat-xbegin-outer-cat-y inner-cat-xinner-cat-y end-outer-cat-y end-outer");
}

- (void)testEvaluateExpressionNestedInterpolatedStringWithUndefinedFunctionCall {
    [_scope setValue:@"the sum is" forVariableNamed:@"label"];
    [_scope setValue:@1 forVariableNamed:@"one"];
    [_scope setValue:@[@0, @1, @2, @3] forVariableNamed:@"array"];

    XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"evaluate function call"];
    NSString *const expression =
    @"\"start-top \\("
    @"    cat(x: \"outer-cat-x\","
    @"        y: \"begin-outer-cat-y \\("
    @"                XXX(x: \"inner-cat-x\", "
    @"                    y: \"inner-cat-y\")"
    @"            ) end-outer-cat-y\")"
    @"    ) end-outer\"";
    [iTermScriptFunctionCall evaluateExpression:expression
                                        timeout:INFINITY
                                          scope:_scope
                                     completion:^(id result, NSError *error, NSSet<NSString *> *missingFunctionSignatures) {
                                         XCTAssertNil(result);
                                         XCTAssertNotNil(error);
                                         NSArray *expected = @[ @"XXX(x,y)" ];
                                         XCTAssertEqualObjects(missingFunctionSignatures.allObjects, expected);

                                         [expectation fulfill];
                                     }];
    [self waitForExpectations:@[expectation] timeout:3600];
}

- (void)testEvaluateExpressionNestedInterpolatedStringWithUndefinedVariableCall {
    [_scope setValue:@"the sum is" forVariableNamed:@"label"];
    [_scope setValue:@1 forVariableNamed:@"one"];
    [_scope setValue:@[@0, @1, @2, @3] forVariableNamed:@"array"];

    XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"evaluate function call"];
    NSString *const expression =
    @"\"start-top \\("
    @"    cat(x: \"outer-cat-x\","
    @"        y: \"begin-outer-cat-y \\("
    @"                cat(x: \"inner-cat-x\", "
    @"                    y: bogus)"
    @"            ) end-outer-cat-y\")"
    @"    ) end-outer\"";
    [iTermScriptFunctionCall evaluateExpression:expression
                                        timeout:INFINITY
                                          scope:_scope
                                     completion:^(id result, NSError *error, NSSet<NSString *> *missingFunctionSignatures) {
                                         XCTAssertNil(result);
                                         XCTAssertNotNil(error);
                                         XCTAssertEqual(0, missingFunctionSignatures.count);

                                         [expectation fulfill];
                                     }];
    [self waitForExpectations:@[expectation] timeout:3600];
}

- (void)testEvaluateExpressionNumberVariable {
    [_scope setValue:@5 forVariableNamed:@"foo"];

    __block id output;
    [iTermScriptFunctionCall evaluateExpression:@"foo"
                                        timeout:0
                                          scope:_scope
                                     completion:^(id result, NSError *error, NSSet<NSString *> *missingFunctionSignatures) {
                                         output = result;
                                         XCTAssertNil(error);
                                         XCTAssertEqual(0, missingFunctionSignatures.count);
                                     }];
    XCTAssertEqualObjects(output, @5);
}

- (void)testEvaluateExpressionArrayVariable {
    NSArray *value = @[@2, @3];
    [_scope setValue:value forVariableNamed:@"foo"];

    __block id output;
    [iTermScriptFunctionCall evaluateExpression:@"foo"
                                        timeout:0
                                          scope:_scope
                                     completion:^(id result, NSError *error, NSSet<NSString *> *missingFunctionSignatures) {
                                         output = result;
                                         XCTAssertNil(error);
                                         XCTAssertEqual(0, missingFunctionSignatures.count);
                                     }];
    XCTAssertEqualObjects(output, value);
}

- (void)testEvaluateExpressionDereferencedArrayVariable {
    NSArray *value = @[@2, @3, @4];
    [_scope setValue:value forVariableNamed:@"foo"];

    __block id output;
    [iTermScriptFunctionCall evaluateExpression:@"foo[1]"
                                        timeout:0
                                          scope:_scope
                                     completion:^(id result, NSError *error, NSSet<NSString *> *missingFunctionSignatures) {
                                         output = result;
                                         XCTAssertNil(error);
                                         XCTAssertEqual(0, missingFunctionSignatures.count);
                                     }];
    XCTAssertEqualObjects(output, @3);
}

- (void)testEvaluateExpressionOutOfBoundsArrayReference {
    NSArray *value = @[@2, @3, @4];
    [_scope setValue:value forVariableNamed:@"foo"];

    [iTermScriptFunctionCall evaluateExpression:@"foo[3]"
                                        timeout:0
                                          scope:_scope
                                     completion:^(id result, NSError *error, NSSet<NSString *> *missingFunctionSignatures) {
                                         XCTAssertNil(result);
                                         XCTAssertNotNil(error);
                                         XCTAssertEqual(error.code, 3);
                                         XCTAssertEqual(0, missingFunctionSignatures.count);
                                     }];
}

- (void)testEvaluateExpressionOptionalVariable {
    [_scope setValue:@5 forVariableNamed:@"foo"];

    __block id output;
    [iTermScriptFunctionCall evaluateExpression:@"foo?"
                                        timeout:0
                                          scope:_scope
                                     completion:^(id result, NSError *error, NSSet<NSString *> *missingFunctionSignatures) {
                                         output = result;
                                         XCTAssertNil(error);
                                         XCTAssertEqual(0, missingFunctionSignatures.count);
                                     }];
    XCTAssertEqualObjects(output, @5);

    output = nil;
    [iTermScriptFunctionCall evaluateExpression:@"bar?"
                                        timeout:0
                                          scope:_scope
                                     completion:^(id result, NSError *error, NSSet<NSString *> *missingFunctionSignatures) {
                                         output = result;
                                         XCTAssertNil(error);
                                         XCTAssertEqual(0, missingFunctionSignatures.count);
                                     }];
    XCTAssertEqualObjects(output, nil);
}

- (void)testEvaluateExpressionUndefinedVariable {
    [iTermScriptFunctionCall evaluateExpression:@"foo"
                                        timeout:0
                                          scope:_scope
                                     completion:^(id result, NSError *error, NSSet<NSString *> *missingFunctionSignatures) {
                                         XCTAssertNil(result);
                                         XCTAssertNotNil(error);
                                         XCTAssertEqual(error.code, 7);
                                         XCTAssertEqual(0, missingFunctionSignatures.count);
                                     }];
}

#pragma mark - Test callFunction:timeout:scope:completion:

- (void)testCallFunction {
    __block id result;
    [iTermScriptFunctionCall callFunction:@"add(x:1, y:2)"
                                  timeout:0
                                    scope:_scope
                               completion:^(id object, NSError *error, NSSet<NSString *> *missing) {
                                   result = object;
                                   XCTAssertNil(error);
                                   XCTAssertEqual(0, missing.count);
                               }];
    XCTAssertEqualObjects(result, @3);
}

- (void)testCallFunctionMistypedArgument {
    [iTermScriptFunctionCall callFunction:@"add(x:1, y:\"foo\")"
                                  timeout:0
                                    scope:_scope
                               completion:^(id object, NSError *error, NSSet<NSString *> *missing) {
                                   XCTAssertNil(object);
                                   XCTAssertNotNil(error);
                                   XCTAssertEqual(0, missing.count);
                               }];
}

- (void)testCallFunctionWrongArguments {
    XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"evaluate function call"];
    [iTermScriptFunctionCall callFunction:@"add(x:1)"
                                  timeout:INFINITY
                                    scope:_scope
                               completion:^(id object, NSError *error, NSSet<NSString *> *missing) {
                                   XCTAssertNil(object);
                                   XCTAssertNotNil(error);
                                   NSArray *expected = @[ @"add(x)" ];
                                   XCTAssertEqualObjects(missing.allObjects, expected);
                                   [expectation fulfill];
                               }];
    [self waitForExpectations:@[expectation] timeout:3600];
}

#pragma mark - Test signature

- (void)testSignatureForFunctionCallInvocation {
    NSString *invocation = @"f(x: 1, y: \"foo\")";
    NSString *expected = @"f(x, y)";
    NSError *error = nil;
    NSString *actual = [iTermScriptFunctionCall signatureForFunctionCallInvocation:invocation error:&error];
    XCTAssertEqual(expected, actual);
    XCTAssertNil(error);
}

- (void)testSignatureForErroneousFunctionCallInvocation {
    NSString *invocation = @"f(x: 1, y: \"foo)";
    NSError *error = nil;
    NSString *actual = [iTermScriptFunctionCall signatureForFunctionCallInvocation:invocation error:&error];
    XCTAssertNil(actual);
    XCTAssertNotNil(error);

    invocation = @"f(x: 1, y: 2";
    actual = [iTermScriptFunctionCall signatureForFunctionCallInvocation:invocation error:&error];
    XCTAssertNil(actual);
    XCTAssertNotNil(error);
}

#pragma mark - Evaluate String

- (void)testEvaluateString {
    [_scope setValue:@"BAR" forVariableNamed:@"bar"];
    __block id result;
    [iTermScriptFunctionCall evaluateString:@"foo \\(cat(x: s(), y: bar)) fin"
                                    timeout:0
                                      scope:_scope
                                 completion:^(NSString *object, NSError *error, NSSet<NSString *> *missingFunctionSignatures) {
                                     result = object;
                                     XCTAssertNil(error);
                                     XCTAssertEqual(0, missingFunctionSignatures.count);
                                 }];
    NSString *expected = @"foo stringBAR fin";
    XCTAssertEqualObjects(expected, result);
}

- (void)testEvaluateStringArrayResult {
    __block id result;
    [iTermScriptFunctionCall evaluateString:@"\\(a())"
                                    timeout:0
                                      scope:_scope
                                 completion:^(NSString *object, NSError *error, NSSet<NSString *> *missingFunctionSignatures) {
                                     result = object;
                                     XCTAssertNil(error);
                                     XCTAssertEqual(0, missingFunctionSignatures.count);
                                 }];
    NSString *expected = @"[1, foo]";
    XCTAssertEqualObjects(expected, result);
}

#pragma mark - Built-in Functions

- (void)testArrayCount {
    __block id result;
    [iTermArrayCountBuiltInFunction registerBuiltInFunction];
    [iTermScriptFunctionCall callFunction:@"iterm2.count(array: a())"
                                  timeout:0
                                    scope:_scope
                               completion:^(id object, NSError *error, NSSet<NSString *> *missing) {
                                   result = object;
                               }];
    XCTAssertEqualObjects(result, @2);
}

@end
