//
//  PreferIntegratedGPUEnabledTests.m
//  ModernTests
//
//  “Prefer integrated to discrete GPU” only means something on a Mac with both kinds of GPU.
//  The Advanced GPU Settings sheet disabled it elsewhere, but the generic preference binding
//  re-enabled it, so it could be toggled on a single-GPU Mac (QA finding F-254). The binding now
//  asks the same question the sheet does.
//

#import <XCTest/XCTest.h>

#import "iTermAdvancedGPUSettingsViewController.h"

@interface PreferIntegratedGPUEnabledTests : XCTestCase
@end

@implementation PreferIntegratedGPUEnabledTests

- (void)testSingleDiscreteGPUCannotPreferIntegrated {
    XCTAssertFalse([iTermAdvancedGPUSettingsViewController canPreferIntegratedGPUWithLowPowerFlags:@[ @NO ]]);
}

- (void)testSingleIntegratedGPUCannotPreferIntegrated {
    XCTAssertFalse([iTermAdvancedGPUSettingsViewController canPreferIntegratedGPUWithLowPowerFlags:@[ @YES ]]);
}

- (void)testNoGPUCannotPreferIntegrated {
    XCTAssertFalse([iTermAdvancedGPUSettingsViewController canPreferIntegratedGPUWithLowPowerFlags:[NSArray array]]);
}

- (void)testIntegratedAndDiscreteCanPreferIntegrated {
    NSArray<NSNumber *> *flags = @[ @NO, @YES ];
    XCTAssertTrue([iTermAdvancedGPUSettingsViewController canPreferIntegratedGPUWithLowPowerFlags:flags]);
}

@end
