//
//  iTermSixelSizeTests.m
//  ModernTests
//

#import <XCTest/XCTest.h>
#import "iTermSixelSize.h"

@interface iTermSixelSizeTests : XCTestCase
@end

@implementation iTermSixelSizeTests

- (void)testOrdinaryImage {
    size_t pixels = 0;
    size_t bytes = 0;
    XCTAssertTrue(iTermSixelRGBASize(640, 480, &pixels, &bytes));
    XCTAssertEqual(pixels, (size_t)640 * 480);
    XCTAssertEqual(bytes, (size_t)640 * 480 * 4);
}

// width * height * 4 overflows a 32-bit int here, which once produced a tiny buffer that the
// conversion loop then wrote gigabytes past.
- (void)testDimensionsWhoseByteCountOverflowsIntAreRejected {
    size_t pixels = 0;
    size_t bytes = 0;
    XCTAssertFalse(iTermSixelRGBASize(32768, 32770, &pixels, &bytes));
}

- (void)testImagesOverThePixelLimitAreRejected {
    size_t pixels = 0;
    size_t bytes = 0;
    XCTAssertTrue(iTermSixelRGBASize(iTermSixelMaxPixels, 1, &pixels, &bytes));
    XCTAssertFalse(iTermSixelRGBASize(iTermSixelMaxPixels + 1, 1, &pixels, &bytes));
}

- (void)testNonPositiveDimensionsAreRejected {
    size_t pixels = 0;
    size_t bytes = 0;
    XCTAssertFalse(iTermSixelRGBASize(0, 10, &pixels, &bytes));
    XCTAssertFalse(iTermSixelRGBASize(10, -1, &pixels, &bytes));
}

@end
