//
//  TriggerTimeoutDescriptionTests.m
//  ModernTests
//
//  Regression test for the fractional-seconds truncation in trigger timing
//  descriptions. The idle/long-running timeout is stored as a Double, but the
//  localized description formatted it with (long)integerValue, so a 0.5 s timeout
//  was described as "after 0 seconds" and 2.5 s as "after 2 seconds".
//

#import <XCTest/XCTest.h>

#import "Trigger.h"

@interface TriggerTimeoutDescriptionTests : XCTestCase
@end

@implementation TriggerTimeoutDescriptionTests

// A fractional timeout must keep its fractional part rather than truncate to 0.
- (void)testFractionalSecondsAreNotTruncated {
    NSString *half = [Trigger eventTimingDescriptionForSeconds:@0.5];
    XCTAssertTrue([half containsString:@"0.5"],
                  @"0.5 s should render its fractional value, got: %@", half);
    XCTAssertFalse([half containsString:@"0 second"],
                   @"0.5 s must not truncate to 0 seconds, got: %@", half);

    NSString *twoAndHalf = [Trigger eventTimingDescriptionForSeconds:@2.5];
    XCTAssertTrue([twoAndHalf containsString:@"2.5"],
                  @"2.5 s should render its fractional value, got: %@", twoAndHalf);
    XCTAssertFalse([twoAndHalf containsString:@"2 second"],
                   @"2.5 s must not truncate to 2 seconds, got: %@", twoAndHalf);
}

// Whole-number timeouts keep the correct English singular/plural inflection.
- (void)testWholeSecondsUsePluralForms {
    NSString *one = [Trigger eventTimingDescriptionForSeconds:@1];
    XCTAssertTrue([one containsString:@"1 second"],
                  @"1 s should be singular, got: %@", one);
    XCTAssertFalse([one containsString:@"seconds"],
                   @"1 s must be singular (no trailing s), got: %@", one);

    NSString *two = [Trigger eventTimingDescriptionForSeconds:@2];
    XCTAssertTrue([two containsString:@"2 seconds"],
                  @"2 s should be plural, got: %@", two);
}

@end
