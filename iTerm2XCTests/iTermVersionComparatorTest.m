//
//  iTermVersionComparatorTest.m
//  iTerm2
//
//  Created by George Nachman on 2/20/17.
//
//

#import <XCTest/XCTest.h>
#import "iTermVersionComparator.h"

@interface iTermVersionComparatorTest : XCTestCase

@end

@implementation iTermVersionComparatorTest

- (void)testNonBetas {
    iTermVersionComparator *c = [[[iTermVersionComparator alloc] init] autorelease];
    NSComparisonResult actual = [c compareVersion:@"1.2.3" toVersion:@"1.2.4"];
    XCTAssertEqual(NSOrderedAscending, actual);
}

- (void)testNonBetasDifferentNumberOfParts {
    iTermVersionComparator *c = [[[iTermVersionComparator alloc] init] autorelease];
    NSComparisonResult actual = [c compareVersion:@"1.2.3.99" toVersion:@"1.2.4"];
    XCTAssertEqual(NSOrderedAscending, actual);
}

- (void)testNonBetasDifferentMajor {
    iTermVersionComparator *c = [[[iTermVersionComparator alloc] init] autorelease];
    NSComparisonResult actual = [c compareVersion:@"2.2.3.99" toVersion:@"1.2.4"];
    XCTAssertEqual(NSOrderedDescending, actual);
}

- (void)testNonBetasChangeOnlyInExtraPart {
    iTermVersionComparator *c = [[[iTermVersionComparator alloc] init] autorelease];
    NSComparisonResult actual = [c compareVersion:@"3.0.0" toVersion:@"3.0.0.1"];
    XCTAssertEqual(NSOrderedAscending, actual);
}

- (void)testUpgradeFromBetaToRelease {
    iTermVersionComparator *c = [[[iTermVersionComparator alloc] init] autorelease];
    NSComparisonResult actual = [c compareVersion:@"1.2.3.beta" toVersion:@"1.2.0"];
    XCTAssertEqual(NSOrderedAscending, actual);
}

- (void)testUpgradeFromBetaToReleaseReversedOrder {
    iTermVersionComparator *c = [[[iTermVersionComparator alloc] init] autorelease];
    NSComparisonResult actual = [c compareVersion:@"1.2.0" toVersion:@"1.2.3.beta"];
    XCTAssertEqual(NSOrderedDescending, actual);
}

- (void)testUpgradeFromBetaToReleaseSameExceptForBetaSuffix {
    iTermVersionComparator *c = [[[iTermVersionComparator alloc] init] autorelease];
    NSComparisonResult actual = [c compareVersion:@"1.2.0.beta" toVersion:@"1.2.0"];
    XCTAssertEqual(NSOrderedAscending, actual);
}


- (void)testUpgradeFromBetaToBeta {
    iTermVersionComparator *c = [[[iTermVersionComparator alloc] init] autorelease];
    NSComparisonResult actual = [c compareVersion:@"1.2.3.beta" toVersion:@"1.2.4.beta"];
    XCTAssertEqual(NSOrderedAscending, actual);
}

- (void)testUpgradeFromBetaToBetaReversedOrder {
    // Reverse the order and make sure it becomes descending
    iTermVersionComparator *c = [[[iTermVersionComparator alloc] init] autorelease];
    NSComparisonResult actual = [c compareVersion:@"1.2.4.beta" toVersion:@"1.2.3.beta"];
    XCTAssertEqual(NSOrderedDescending, actual);
}

@end
