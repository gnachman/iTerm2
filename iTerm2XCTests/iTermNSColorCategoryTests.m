//
//  iTermNSColorCategoryTests.m
//  iTerm2XCTests
//
//  Created by George Nachman on 10/31/20.
//

#import <XCTest/XCTest.h>
#import "NSColor+iTerm.h"

@interface iTermNSColorCategoryTests : XCTestCase

@end

@implementation iTermNSColorCategoryTests

// The tolerances on these tests are much larger than I'd like. I have not found two reference
// implementations that agree with each other any more closely, unfortunately.
- (void)testLABFromSRGB {
    {
        iTermLABColor lab = iTermLABFromSRGB((iTermSRGBColor) {
            .r = 1,
            .g = 0,
            .b = 0
        });
        XCTAssertEqualWithAccuracy(lab.l, 54, 1);
        XCTAssertEqualWithAccuracy(lab.a, 80, 1);
        XCTAssertEqualWithAccuracy(lab.b, 67, 1);
    }
    {
        iTermLABColor lab = iTermLABFromSRGB((iTermSRGBColor) {
            .r = 0.8,
            .g = 0.2,
            .b = 0.5
        });

        XCTAssertEqualWithAccuracy(lab.l, 48, 1);
        XCTAssertEqualWithAccuracy(lab.a, 65, 1);
        XCTAssertEqualWithAccuracy(lab.b, -7, 1);
    }
    {
        iTermLABColor lab = iTermLABFromSRGB((iTermSRGBColor) {
            .r = 0.9,
            .g = 0.8,
            .b = 0.9
        });

        XCTAssertEqualWithAccuracy(lab.l, 85, 1);
        XCTAssertEqualWithAccuracy(lab.a, 13, 1);
        XCTAssertEqualWithAccuracy(lab.b, -9, 1);
    }
    {
        iTermLABColor lab = iTermLABFromSRGB((iTermSRGBColor) {
            .r = 0.1,
            .g = 0.2,
            .b = 0.1
        });

        XCTAssertEqualWithAccuracy(lab.l, 18, 1);
        XCTAssertEqualWithAccuracy(lab.a, -16, 1);
        XCTAssertEqualWithAccuracy(lab.b, 13, 1);
    }
}

// This is really a test that iTermSRGBFromLAB is an inverse of iTermLABFromSRGB. These are not
// ground-truth values because as noted above I can't find any.
- (void)testSRGBFromLAB {
    {
        iTermSRGBColor srgb = iTermSRGBFromLAB((iTermLABColor) {
            .l = 53.23,
            .a = 80.10,
            .b = 67.22
        });
        XCTAssertEqualWithAccuracy(srgb.r, 1, 0.01);
        XCTAssertEqualWithAccuracy(srgb.g, 0, 0.01);
        XCTAssertEqualWithAccuracy(srgb.b, 0, 0.01);
    }
    {
        iTermSRGBColor srgb = iTermSRGBFromLAB((iTermLABColor) {
            .l = 47.94,
            .a = 64.62,
            .b = -6.94
        });

        XCTAssertEqualWithAccuracy(srgb.r, 0.8, 0.01);
        XCTAssertEqualWithAccuracy(srgb.g, 0.2, 0.01);
        XCTAssertEqualWithAccuracy(srgb.b, 0.5, 0.01);
    }
    {
        iTermSRGBColor srgb = iTermSRGBFromLAB((iTermLABColor) {
            .l = 84.80,
            .a = 13.32,
            .b = -9.32
        });

        XCTAssertEqualWithAccuracy(srgb.r, 0.9, 0.01);
        XCTAssertEqualWithAccuracy(srgb.g, 0.8, 0.01);
        XCTAssertEqualWithAccuracy(srgb.b, 0.9, 0.01);
    }
    {
        iTermSRGBColor srgb = iTermSRGBFromLAB((iTermLABColor) {
            .l =  18.60,
            .a = -16.39,
            .b =  13.17
        });

        XCTAssertEqualWithAccuracy(srgb.r, 0.1, 0.01);
        XCTAssertEqualWithAccuracy(srgb.g, 0.2, 0.01);
        XCTAssertEqualWithAccuracy(srgb.b, 0.1, 0.01);
    }
}

@end
