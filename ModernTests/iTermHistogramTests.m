//
//  iTermHistogramTests.m
//  ModernTests
//

#import <XCTest/XCTest.h>

#import "iTermHistogram.h"

@interface iTermHistogramTests : XCTestCase
@end

@implementation iTermHistogramTests

// A histogram whose reservoir is full and whose sampler has seen `weight` values.
- (iTermHistogram *)histogramWithWeight:(int64_t)weight {
    NSMutableArray<NSNumber *> *values = [NSMutableArray array];
    for (int i = 0; i < 100; i++) {
        [values addObject:@(i)];
    }
    NSDictionary *dict = @{ @"reservoirSize": @100,
                            @"sampler": @{ @"capacity": @100,
                                           @"weight": @(weight),
                                           @"values": values },
                            @"sum": @(4950),
                            @"min": @0,
                            @"max": @99,
                            @"count": @(weight),
                            @"discrete": @NO };
    return [[iTermHistogram alloc] initWithDictionary:dict];
}

- (int64_t)samplerWeightOf:(iTermHistogram *)histogram {
    return [histogram.dictionaryValue[@"sampler"][@"weight"] longLongValue];
}

- (NSUInteger)samplerValueCountOf:(iTermHistogram *)histogram {
    return [histogram.dictionaryValue[@"sampler"][@"values"] count];
}

// The global Metal histograms live for the whole process and merge every frame,
// so after weeks of uptime the sampler's weight passes INT32_MAX. Issue 13103.
- (void)testMergeBeyondInt32WeightDoesNotOverflow {
    const int64_t weight = INT32_MAX - 1;
    iTermHistogram *histogram = [self histogramWithWeight:weight];
    for (int i = 1; i <= 4; i++) {
        [histogram mergeFrom:[self histogramWithWeight:weight]];
        XCTAssertEqual([self samplerWeightOf:histogram], weight * (i + 1));
        XCTAssertGreaterThan([self samplerValueCountOf:histogram], 0u);
        XCTAssertLessThanOrEqual([self samplerValueCountOf:histogram], 100u);
    }
}

// After the weight passes INT32_MAX, adding values must still work.
- (void)testAddAfterInt32WeightKeepsCounting {
    const int64_t weight = (int64_t)INT32_MAX + 10;
    iTermHistogram *histogram = [self histogramWithWeight:weight];
    for (int i = 0; i < 1000; i++) {
        [histogram addValue:i];
    }
    XCTAssertEqual([self samplerWeightOf:histogram], weight + 1000);
    XCTAssertEqual([self samplerValueCountOf:histogram], 100u);
}

@end
