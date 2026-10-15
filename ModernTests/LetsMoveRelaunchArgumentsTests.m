//
//  LetsMoveRelaunchArgumentsTests.m
//  ModernTests
//
//  F-392: LetsMove's relaunch ran `open <app>` with no arguments, so a copy
//  started with -suite NAME came back on the default settings.
//

#import <XCTest/XCTest.h>

extern NSString *PFMoveRelaunchOpenArgumentsSuffix(NSArray<NSString *> *processArguments);

@interface LetsMoveRelaunchArgumentsTests : XCTestCase
@end

@implementation LetsMoveRelaunchArgumentsTests

- (void)testSuiteIsForwarded {
    XCTAssertEqualObjects(PFMoveRelaunchOpenArgumentsSuffix(@[ @"/A/iTerm2", @"-suite", @"qa" ]),
                          @" --args -suite 'qa'");
}

- (void)testSuiteNameIsShellQuoted {
    XCTAssertEqualObjects(PFMoveRelaunchOpenArgumentsSuffix(@[ @"/A/iTerm2", @"-suite", @"it's; rm" ]),
                          @" --args -suite 'it'\\''s; rm'");
}

- (void)testNoSuiteMeansNoArguments {
    XCTAssertEqualObjects(PFMoveRelaunchOpenArgumentsSuffix(@[ @"/A/iTerm2" ]), @"");
    XCTAssertEqualObjects(PFMoveRelaunchOpenArgumentsSuffix(@[ @"/A/iTerm2", @"-suite" ]), @"");
}

@end
