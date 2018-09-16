//
//  iTermVariablesTest.m
//  iTerm2XCTests
//
//  Created by George Nachman on 9/12/18.
//

#import <XCTest/XCTest.h>
#import "iTermVariableReference.h"
#import "iTermVariables.h"

@interface iTermVariablesTest : XCTestCase

@end

@implementation iTermVariablesTest

- (void)testWriteThenRead {
    iTermVariables *vars = [[[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextSession owner:self] autorelease];
    iTermVariableScope *scope = [[[iTermVariableScope alloc] init] autorelease];
    [scope addVariables:vars toScopeNamed:nil];
    [scope setValue:@123 forVariableNamed:@"v"];
    XCTAssertEqualObjects(@123, [scope valueForVariableName:@"v"]);
}

- (void)testReferenceProducesValue {
    iTermVariables *vars = [[[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextSession owner:self] autorelease];
    iTermVariableScope *scope = [[[iTermVariableScope alloc] init] autorelease];
    [scope addVariables:vars toScopeNamed:nil];
    [scope setValue:@123 forVariableNamed:@"v"];

    __block id actual = nil;
    iTermVariableReference *ref = [[[iTermVariableReference alloc] initWithPath:@"v"
                                                                          scope:scope] autorelease];
    ref.onChangeBlock = ^{
        actual = ref.value;
    };

    [scope setValue:@987 forVariableNamed:@"v"];
    XCTAssertEqualObjects(@987, actual);
}

- (void)testReferenceCanSetValue {
    iTermVariables *vars = [[[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextSession owner:self] autorelease];
    iTermVariableScope *scope = [[[iTermVariableScope alloc] init] autorelease];
    [scope addVariables:vars toScopeNamed:nil];
    [scope setValue:@123 forVariableNamed:@"v"];

    iTermVariableReference *ref = [[[iTermVariableReference alloc] initWithPath:@"v"
                                                                          scope:scope] autorelease];
    ref.value = @987;
    id actual = [scope valueForVariableName:@"v"];
    XCTAssertEqualObjects(@987, actual);
}

- (void)testLateResolution {
    iTermVariables *vars = [[[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextSession owner:self] autorelease];
    iTermVariableScope *scope = [[[iTermVariableScope alloc] init] autorelease];
    [scope addVariables:vars toScopeNamed:nil];

    iTermVariableReference *ref = [[[iTermVariableReference alloc] initWithPath:@"v"
                                                                          scope:scope] autorelease];
    __block id actual = nil;
    ref.onChangeBlock = ^{
        actual = ref.value;
    };

    [scope setValue:@987 forVariableNamed:@"v"];
    XCTAssertEqualObjects(@987, actual);
}

- (void)testChangeOfIntermediate {
    iTermVariables *tab = [[[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextTab owner:self] autorelease];
    iTermVariableScope *tabScope = [[[iTermVariableScope alloc] init] autorelease];
    [tabScope addVariables:tab toScopeNamed:nil];

    iTermVariables *session1 = [[[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextSession owner:self] autorelease];
    iTermVariableScope *session1Scope = [[[iTermVariableScope alloc] init] autorelease];
    [session1Scope addVariables:session1 toScopeNamed:nil];

    iTermVariables *session2 = [[[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextSession owner:self] autorelease];
    iTermVariableScope *session2Scope = [[[iTermVariableScope alloc] init] autorelease];
    [session2Scope addVariables:session2 toScopeNamed:nil];

    [tabScope setValue:session1 forVariableNamed:@"currentSession"];
    [session1Scope setValue:@1 forVariableNamed:@"n"];
    [session2Scope setValue:@2 forVariableNamed:@"n"];

    iTermVariableReference *ref = [[[iTermVariableReference alloc] initWithPath:@"currentSession.n"
                                                                          scope:tabScope] autorelease];
    __block id actual = nil;
    ref.onChangeBlock = ^{
        [actual autorelease];
        actual = [ref.value retain];
    };
    XCTAssertEqualObjects(ref.value, @1);

    [tabScope setValue:session2 forVariableNamed:@"currentSession"];
    XCTAssertEqualObjects(ref.value, @2);
    XCTAssertEqualObjects(actual, @2);
}

- (void)testLateIntermediateResolution {
    iTermVariables *tab = [[[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextTab owner:self] autorelease];
    iTermVariableScope *tabScope = [[[iTermVariableScope alloc] init] autorelease];
    [tabScope addVariables:tab toScopeNamed:nil];

    iTermVariables *session1 = [[[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextSession owner:self] autorelease];
    iTermVariableScope *session1Scope = [[[iTermVariableScope alloc] init] autorelease];
    [session1Scope addVariables:session1 toScopeNamed:nil];
    [session1Scope setValue:@123 forVariableNamed:@"n"];

    iTermVariableReference *ref = [[[iTermVariableReference alloc] initWithPath:@"currentSession.n"
                                                                          scope:tabScope] autorelease];
    __block id actual = nil;
    ref.onChangeBlock = ^{
        [actual autorelease];
        actual = [ref.value retain];
    };
    [tabScope setValue:session1 forVariableNamed:@"currentSession"];
    XCTAssertEqualObjects(actual, @123);
}

- (void)testShadow {
    iTermVariables *vars = [[[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextSession owner:self] autorelease];
    iTermVariableScope *scope1 = [[[iTermVariableScope alloc] init] autorelease];
    [scope1 addVariables:vars toScopeNamed:nil];
    [scope1 setValue:@123 forVariableNamed:@"v"];

    iTermVariableScope *scope2 = [[scope1 copy] autorelease];
    iTermVariables *vars2 = [[[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextSession owner:self] autorelease];
    [scope2 addVariables:vars2 toScopeNamed:nil];
    [scope2 setValue:@234 forVariableNamed:@"v"];

    XCTAssertEqualObjects(@123, [scope1 valueForVariableName:@"v"]);
    XCTAssertEqualObjects(@123, [vars discouragedValueForVariableName:@"v"]);
    
    XCTAssertEqualObjects(@234, [scope2 valueForVariableName:@"v"]);
    XCTAssertEqualObjects(@234, [vars2 discouragedValueForVariableName:@"v"]);
}

@end

