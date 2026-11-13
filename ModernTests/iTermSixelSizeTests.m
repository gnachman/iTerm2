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

// libsixel allocates one byte per pixel at whatever size the image's raster attributes ask for,
// up to 1,000,000 on a side, before iTerm2 ever sees the dimensions. Its allocator must refuse
// anything bigger than the largest image we accept.
- (void)testAllocatorRefusesBuffersLargerThanTheBiggestAcceptedImage {
    void *p = iTermSixelMalloc(iTermSixelMaxPixels + 1);
    XCTAssertTrue(p == NULL);
    p = iTermSixelCalloc(iTermSixelMaxPixels / 2 + 1, 2);
    XCTAssertTrue(p == NULL);
    p = iTermSixelCalloc(SIZE_MAX / 2, 4);
    XCTAssertTrue(p == NULL);
    void *small = iTermSixelMalloc(16);
    XCTAssertTrue(small != NULL);
    XCTAssertTrue(iTermSixelRealloc(small, iTermSixelMaxPixels + 1) == NULL);
    free(small);
}

- (void)testAllocatorAllowsTheBiggestAcceptedImage {
    void *p = iTermSixelMalloc(iTermSixelMaxPixels);
    XCTAssertTrue(p != NULL);
    p = iTermSixelRealloc(p, 32);
    XCTAssertTrue(p != NULL);
    free(p);
    p = iTermSixelCalloc(iTermSixelMaxPixels / 4, 4);
    XCTAssertTrue(p != NULL);
    free(p);
}

- (void)testNonPositiveDimensionsAreRejected {
    size_t pixels = 0;
    size_t bytes = 0;
    XCTAssertFalse(iTermSixelRGBASize(0, 10, &pixels, &bytes));
    XCTAssertFalse(iTermSixelRGBASize(10, -1, &pixels, &bytes));
}

@end
