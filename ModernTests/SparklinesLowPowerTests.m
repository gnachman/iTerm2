//
//  SparklinesLowPowerTests.m
//  ModernTests
//
//  F-391: in Low Power Mode the sparkline kept animating smoothly because its
//  1 fps frame-rate hint was ignored. It now doesn't animate at all then.
//

#import <XCTest/XCTest.h>

#import "iTermStatusBarSparklinesComponent.h"

@interface SparklinesLowPowerTests : XCTestCase
@end

@implementation SparklinesLowPowerTests

- (void)testNoAnimationInLowPowerMode {
    XCTAssertTrue([iTermStatusBarSparklinesComponent shouldAnimateWithSetting:YES lowPowerMode:NO]);
    XCTAssertFalse([iTermStatusBarSparklinesComponent shouldAnimateWithSetting:YES lowPowerMode:YES]);
    XCTAssertFalse([iTermStatusBarSparklinesComponent shouldAnimateWithSetting:NO lowPowerMode:NO]);
}

@end
