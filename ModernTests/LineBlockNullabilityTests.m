//
//  LineBlockNullabilityTests.m
//  ModernTests
//
//  -[LineBlock(SwiftInterop) subBidiInfo:range:width:] receives nil for a line
//  without bidi info, which is most lines, under a nonnull claim (unit H2 of
//  docs/swift-migration/nullability-triage.md). Its body only messages the bidi
//  info, so the result is nil. LineBlock+SwiftInterop.h is not visible to
//  Swift, so the claim is pinned here in Objective-C.
//

#import <XCTest/XCTest.h>

#import "LineBlock+SwiftInterop.h"

@interface LineBlockNullabilityTests : XCTestCase
@end

@implementation LineBlockNullabilityTests

- (void)testSubBidiInfoOfNoBidiInfoIsNil {
    LineBlock *block = [[LineBlock alloc] initWithRawBufferSize:16 absoluteBlockNumber:0];
    XCTAssertNil([block subBidiInfo:nil range:NSMakeRange(0, 1) width:10]);
}

@end
