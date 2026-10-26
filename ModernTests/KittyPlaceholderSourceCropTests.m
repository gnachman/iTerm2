//
//  KittyPlaceholderSourceCropTests.m
//  ModernTests
//
//  A Kitty Unicode-placeholder placement with a source crop (x, y, w, h) must
//  draw only the cropped part of the image. Two bugs broke this:
//  - The crop's origin was subtracted instead of added when converting a cell's
//    source rect to the bottom-up coordinates the source frame uses, so a crop
//    of the top-left quadrant sampled below the image and drew nothing.
//  - A cell in the letterbox padding around the image sampled outside the crop,
//    so the neighboring part of the image bled into it.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "iTermTextDrawingHelper.h"

@interface KittyPlaceholderSourceCropTests : XCTestCase
@end

@implementation KittyPlaceholderSourceCropTests

// A 64x64 image cropped to a 32x32 quadrant shown in a 4x2 cell placement with
// 8x17 cells. The 32x34 placement is taller than the square crop, so the crop
// is scaled to 32x32 with one point of padding above and below.
static const NSSize kCellSize = { 8, 17 };

static iTermKittyPlaceholderDrawInstructions Instructions(NSRect sourceFrame, int x, int y) {
    return iTermKittyPlaceholderDrawInstructionsCreateForSourceFrame(sourceFrame,
                                                                     VT100GridSizeMake(4, 2),
                                                                     kCellSize,
                                                                     VT100GridCoordMake(x, y),
                                                                     NSMakePoint(100, 200),
                                                                     0);
}

- (void)assertRect:(NSRect)actual equals:(NSRect)expected {
    XCTAssertEqualWithAccuracy(actual.origin.x, expected.origin.x, 0.001, @"%@ vs %@", NSStringFromRect(actual), NSStringFromRect(expected));
    XCTAssertEqualWithAccuracy(actual.origin.y, expected.origin.y, 0.001, @"%@ vs %@", NSStringFromRect(actual), NSStringFromRect(expected));
    XCTAssertEqualWithAccuracy(actual.size.width, expected.size.width, 0.001, @"%@ vs %@", NSStringFromRect(actual), NSStringFromRect(expected));
    XCTAssertEqualWithAccuracy(actual.size.height, expected.size.height, 0.001, @"%@ vs %@", NSStringFromRect(actual), NSStringFromRect(expected));
}

// Kitty crop x=0,y=0,w=32,h=32 is the top-left quadrant, which is (0, 32, 32, 32)
// with the origin at the bottom.
- (void)testTopLeftQuadrantCropSamplesInsideTheCrop {
    const NSRect frame = NSMakeRect(0, 32, 32, 32);
    iTermKittyPlaceholderDrawInstructions top = Instructions(frame, 1, 0);
    XCTAssertTrue(top.valid);
    [self assertRect:top.sourceRect equals:NSMakeRect(8, 48, 8, 16)];
    // The point of padding at the top of the cell stays empty.
    [self assertRect:top.destRect equals:NSMakeRect(0, 0, 8, 16)];

    iTermKittyPlaceholderDrawInstructions bottom = Instructions(frame, 1, 1);
    XCTAssertTrue(bottom.valid);
    [self assertRect:bottom.sourceRect equals:NSMakeRect(8, 32, 8, 16)];
    [self assertRect:bottom.destRect equals:NSMakeRect(0, 1, 8, 16)];
}

// Kitty crop x=32,y=32,w=32,h=32 is the bottom-right quadrant, which is
// (32, 0, 32, 32) with the origin at the bottom. The top row must not sample
// above y=32, which is the top-right quadrant.
- (void)testBottomRightQuadrantCropDoesNotBleed {
    const NSRect frame = NSMakeRect(32, 0, 32, 32);
    iTermKittyPlaceholderDrawInstructions top = Instructions(frame, 0, 0);
    XCTAssertTrue(top.valid);
    [self assertRect:top.sourceRect equals:NSMakeRect(32, 16, 8, 16)];
    [self assertRect:top.destRect equals:NSMakeRect(0, 0, 8, 16)];

    iTermKittyPlaceholderDrawInstructions bottom = Instructions(frame, 3, 1);
    XCTAssertTrue(bottom.valid);
    [self assertRect:bottom.sourceRect equals:NSMakeRect(56, 0, 8, 16)];
    [self assertRect:bottom.destRect equals:NSMakeRect(0, 1, 8, 16)];
}

// A wide crop in a tall placement leaves whole rows of padding, which draw
// nothing rather than a neighboring part of the image.
- (void)testCellEntirelyInPaddingIsInvalid {
    const NSRect frame = NSMakeRect(0, 32, 64, 8);
    iTermKittyPlaceholderDrawInstructions instructions =
        iTermKittyPlaceholderDrawInstructionsCreateForSourceFrame(frame,
                                                                  VT100GridSizeMake(4, 4),
                                                                  kCellSize,
                                                                  VT100GridCoordMake(0, 0),
                                                                  NSZeroPoint,
                                                                  0);
    XCTAssertFalse(instructions.valid);
}

@end
