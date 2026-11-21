//
//  BackgroundColorRendererSuppressedRegionTests.m
//  ModernTests
//
//  -[iTermBackgroundColorRenderer drawWithFrameData:transientState:] fills
//  the suppressed region at the bottom with the default background color, in
//  a quad suppressedBottomHeight * scale - margins.top pixels tall. It used to
//  convert that to NSUInteger on every frame, before checking that anything
//  was suppressed, so with nothing suppressed it converted -margins.top: a
//  negative value, which is undefined (0 on arm64, near 2^64 on x86_64). It
//  is computed only when something is suppressed now, and is 0 when the
//  margin is the larger. See docs/swift-migration/integer-findings.md
//  section 4.3.
//

#import <XCTest/XCTest.h>

#import "iTermBackgroundColorRenderer.h"

@interface BackgroundColorRendererSuppressedRegionTests : XCTestCase
@end

@implementation BackgroundColorRendererSuppressedRegionTests

- (void)testScaledHeightLessTheMargin {
    XCTAssertEqual(iTermBackgroundColorRendererSuppressedBottomPixels(30, 2, 12), 48u);
    XCTAssertEqual(iTermBackgroundColorRendererSuppressedBottomPixels(30, 1, 0), 30u);
}

- (void)testFractionalPixelsTruncate {
    XCTAssertEqual(iTermBackgroundColorRendererSuppressedBottomPixels(10.75, 2, 1), 20u);
    XCTAssertEqual(iTermBackgroundColorRendererSuppressedBottomPixels(6.9, 1, 6), 0u);
}

- (void)testMarginLargerThanTheSuppressedHeightGivesZero {
    // 4 * 2 - 12 = -4 pixels.
    XCTAssertEqual(iTermBackgroundColorRendererSuppressedBottomPixels(4, 2, 12), 0u);
}

- (void)testNothingSuppressedGivesZero {
    // The values every observed frame had: -12 and -36 pixels.
    XCTAssertEqual(iTermBackgroundColorRendererSuppressedBottomPixels(0, 2, 12), 0u);
    XCTAssertEqual(iTermBackgroundColorRendererSuppressedBottomPixels(0, 2, 36), 0u);
}

- (void)testMarginEqualToTheSuppressedHeightGivesZero {
    XCTAssertEqual(iTermBackgroundColorRendererSuppressedBottomPixels(6, 2, 12), 0u);
}

@end
