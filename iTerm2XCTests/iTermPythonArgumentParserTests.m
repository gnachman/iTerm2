//
//  iTermPythonArgumentParserTests.m
//  iTerm2XCTests
//
//  Created by George Nachman on 11/14/19.
//

#import <XCTest/XCTest.h>

#import "iTermPythonArgumentParser.h"

@interface iTermPythonArgumentParserTests : XCTestCase

@end

@implementation iTermPythonArgumentParserTests

- (void)testStatement {
    iTermPythonArgumentParser *parser = [[iTermPythonArgumentParser alloc] initWithArgs:@[ @"python", @"-c", @"statement", @"script" ]];
    XCTAssertEqualObjects(parser.statement, @"statement");
    XCTAssertNil(parser.script);
}

- (void)testCompoundStatement {
    iTermPythonArgumentParser *parser = [[iTermPythonArgumentParser alloc] initWithArgs:@[ @"python", @"-cstatement", @"script" ]];
    XCTAssertEqualObjects(parser.statement, @"statement");
    XCTAssertNil(parser.script);
}

- (void)testModule {
    iTermPythonArgumentParser *parser = [[iTermPythonArgumentParser alloc] initWithArgs:@[ @"python", @"-m", @"module", @"arg" ]];
    XCTAssertEqualObjects(parser.module, @"module arg");
    XCTAssertNil(parser.script);
}

- (void)testCompoundModule {
    iTermPythonArgumentParser *parser = [[iTermPythonArgumentParser alloc] initWithArgs:@[ @"python", @"-mmodule", @"arg" ]];
    XCTAssertEqualObjects(parser.module, @"module arg");
    XCTAssertNil(parser.script);
}

- (void)testScript {
    iTermPythonArgumentParser *parser = [[iTermPythonArgumentParser alloc] initWithArgs:@[ @"python", @"script" ]];
    XCTAssertEqualObjects(parser.script, @"script");
}

- (void)testIgnoresDivisionControl {
    iTermPythonArgumentParser *parser = [[iTermPythonArgumentParser alloc] initWithArgs:@[ @"python", @"-Q", @"old", @"script" ]];
    XCTAssertEqualObjects(parser.script, @"script");
}

- (void)testIgnoresCompoundDivisionControl {
    iTermPythonArgumentParser *parser = [[iTermPythonArgumentParser alloc] initWithArgs:@[ @"python", @"-Qold", @"script" ]];
    XCTAssertEqualObjects(parser.script, @"script");
}

- (void)testIgnoresWarningControl {
    iTermPythonArgumentParser *parser = [[iTermPythonArgumentParser alloc] initWithArgs:@[ @"python", @"-W", @"old", @"script" ]];
    XCTAssertEqualObjects(parser.script, @"script");
}

- (void)testIgnoresCompoundWarningControl {
    iTermPythonArgumentParser *parser = [[iTermPythonArgumentParser alloc] initWithArgs:@[ @"python", @"-Wold", @"script" ]];
    XCTAssertEqualObjects(parser.script, @"script");
}

- (void)testIgnoresArgv {
    iTermPythonArgumentParser *parser = [[iTermPythonArgumentParser alloc] initWithArgs:@[ @"python", @"-", @"argv" ]];
    XCTAssertNil(parser.script);
}

- (void)testIgnoresUnrecognized {
    iTermPythonArgumentParser *parser = [[iTermPythonArgumentParser alloc] initWithArgs:@[ @"python", @"-B", @"script" ]];
    XCTAssertEqualObjects(parser.script, @"script");
}

@end
