//
//  MetalGlueStatsLifetimeTests.m
//  ModernTests
//
//  iTermMetalGlue gives each frame's iTermAttributedStringBuilder raw pointers into the glue's own
//  timing statistics. The frame (and its builder) can outlive the glue: a session that closes
//  frees its glue while frames are still in flight on the Metal queue, and completing a frame
//  writes the builder's statistics. That wrote into freed memory, corrupting the heap. A builder's
//  statistics must stay valid for as long as the builder exists. (ModernTests runs under
//  AddressSanitizer, so touching freed memory aborts.)
//

#import <XCTest/XCTest.h>
#import <objc/runtime.h>

#import "iTermAttributedStringBuilder.h"

// iTermMetalGlue.h can't be imported here (it needs the generated Swift header), so declare what
// the test uses.
@interface iTermMetalGlue : NSObject
- (iTermAttributedStringBuilder *)newAttributedStringBuilder;
@end

@interface MetalGlueStatsLifetimeTests : XCTestCase
@end

@implementation MetalGlueStatsLifetimeTests

// The builder's statistics must not live inside the glue, which can be freed while the builder
// is still in use.
- (void)testBuilderStatisticsAreNotInsideGlue {
    iTermMetalGlue *glue = [[iTermMetalGlue alloc] init];
    iTermAttributedStringBuilder *builder = [glue newAttributedStringBuilder];
    const uintptr_t glueStart = (uintptr_t)(__bridge void *)glue;
    const uintptr_t glueEnd = glueStart + class_getInstanceSize([glue class]);
    const iTermPreciseTimerStats *pointers[] = {
        builder.stats.attrsForChar,
        builder.stats.shouldSegment,
        builder.stats.buildMutableAttributedString,
        builder.stats.combineAttributes,
        builder.stats.updateBuilder,
        builder.stats.advances,
    };
    for (size_t i = 0; i < sizeof(pointers) / sizeof(*pointers); i++) {
        const uintptr_t p = (uintptr_t)pointers[i];
        XCTAssertFalse(p >= glueStart && p < glueEnd, @"Statistic %zu is inside the glue", i);
    }
}

// Freeing the glue doesn't invalidate statistics a builder still uses.
- (void)testBuilderStatisticsOutliveGlue {
    iTermAttributedStringBuilder *builder = nil;
    __weak iTermMetalGlue *weakGlue = nil;
    @autoreleasepool {
        iTermMetalGlue *glue = [[iTermMetalGlue alloc] init];
        weakGlue = glue;
        builder = [glue newAttributedStringBuilder];
    }
    XCTAssertNil(weakGlue, @"Precondition: the glue was freed");
    // statisticsString reads and resets the statistics, as -[iTermMetalDriver complete:] does
    // after a frame.
    XCTAssertNotNil(builder.statisticsString);
    XCTAssertNotNil(builder.statisticsString);
}

@end
