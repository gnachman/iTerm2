//
//  LatchedWindowMinSizeTests.m
//  ModernTests
//
//  A window manager can move a window partly off screen and AppKit then stores
//  that frame as minSize or contentMinSize. Later shrinks are clamped to it
//  before -windowWillResize:toSize:. -it_clearLatchedMinSize drops that floor.
//  Assigning {0, 0} is how the floor is cleared. AppKit may still report a
//  small minimum for the window chrome, which is not the latched frame.
//

#import <XCTest/XCTest.h>

#import "PTYWindow.h"

@interface LatchedWindowMinSizeTests : XCTestCase
@end

@implementation LatchedWindowMinSizeTests

- (iTermWindow *)newWindow {
    return [[iTermWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
                                          styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskClosable)
                                            backing:NSBackingStoreBuffered
                                              defer:YES];
}

- (void)testClearLatchedMinSizeDropsAFloor {
    iTermWindow *untouched = [self newWindow];
    const NSSize naturalMinSize = untouched.minSize;
    const NSSize naturalContentMinSize = untouched.contentMinSize;

    iTermWindow *window = [self newWindow];
    window.minSize = NSMakeSize(1200, 800);
    window.contentMinSize = NSMakeSize(1100, 700);
    XCTAssertGreaterThan(window.minSize.width, 1000);
    XCTAssertGreaterThan(window.contentMinSize.width, 1000);

    [window it_clearLatchedMinSize];

    XCTAssertEqualWithAccuracy(window.minSize.width, naturalMinSize.width, 1,
                               @"minSize %@ natural %@",
                               NSStringFromSize(window.minSize),
                               NSStringFromSize(naturalMinSize));
    XCTAssertEqualWithAccuracy(window.minSize.height, naturalMinSize.height, 1,
                               @"minSize %@ natural %@",
                               NSStringFromSize(window.minSize),
                               NSStringFromSize(naturalMinSize));
    XCTAssertTrue(NSEqualSizes(window.contentMinSize, naturalContentMinSize),
                  @"contentMinSize %@ natural %@",
                  NSStringFromSize(window.contentMinSize),
                  NSStringFromSize(naturalContentMinSize));
}

- (void)testClearLatchedMinSizeLeavesAnUntouchedWindowAlone {
    iTermWindow *window = [self newWindow];
    const NSSize minSize = window.minSize;
    const NSSize contentMinSize = window.contentMinSize;

    [window it_clearLatchedMinSize];

    XCTAssertTrue(NSEqualSizes(window.minSize, minSize),
                  @"minSize %@ before %@",
                  NSStringFromSize(window.minSize),
                  NSStringFromSize(minSize));
    XCTAssertTrue(NSEqualSizes(window.contentMinSize, contentMinSize),
                  @"contentMinSize %@ before %@",
                  NSStringFromSize(window.contentMinSize),
                  NSStringFromSize(contentMinSize));
}

@end
