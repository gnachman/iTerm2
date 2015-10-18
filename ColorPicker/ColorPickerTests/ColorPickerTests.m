#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>
#import "CPKKDTree.h"
#import <math.h>

const NSInteger kMaxValue = 10;

@interface ColorPickerTests : XCTestCase

@end

@implementation ColorPickerTests

- (void)testKDTreeStanfordData {
    NSArray *points =
        @[
            @[ @2, @1, @3 ],
            @[ @2, @3, @7 ],
            @[ @1, @4, @4 ],
            @[ @2, @4, @5 ],
            @[ @3, @1, @4 ],
            @[ @0, @5, @7 ],
            @[ @6, @1, @4 ],
            @[ @4, @0, @6 ],
            @[ @4, @3, @4 ],
            @[ @5, @2, @5 ],
            @[ @7, @1, @6 ]
        ];
    [self doTestOnTreeWithPoints:points];
}

- (void)testKDTreeRandomData {
    for (NSInteger i = 0; i < 100; i++) {
        [self doTestOnTreeWithPoints:[self randomPointsWithSeed:i]];
    }
}

- (NSArray *)randomPointsWithSeed:(NSInteger)seed {
    srand((unsigned int)seed);
    const NSInteger kMaxPoints = 50;
    NSInteger numPoints = 1 + abs(rand()) % kMaxPoints;
    NSMutableArray *points = [NSMutableArray array];
    for (NSInteger i = 0; i < numPoints; i++) {
        NSArray *point = @[ @(abs(rand()) % kMaxValue),
                            @(abs(rand()) % kMaxValue),
                            @(abs(rand()) % kMaxValue) ];
        [points addObject:point];
    }
    return points;
}

- (void)doTestOnTreeWithPoints:(NSArray *)points {
    CPKKDTree *tree = [[CPKKDTree alloc] initWithDimensions:3];
    for (NSInteger i = 0; i < points.count; i++) {
        [tree addObject:@(i) forKey:points[i]];
    }
    [tree build];

    for (NSInteger x = -1; x < kMaxValue + 1; x++) {
        for (NSInteger y = -1; y < kMaxValue + 1; y++) {
            for (NSInteger z = -1; z < kMaxValue + 1; z++) {
                NSArray *xyz = @[ @(x), @(y), @(z) ];
                NSNumber *n = [tree nearestNeighborTo:xyz];

                double bestDistance = DBL_MAX;
                NSNumber *actualNearestNeighbor = nil;
                for (NSInteger i = 0; i < points.count; i++) {
                    NSArray *p = points[i];
                    double a1 = [p[0] doubleValue] - x;
                    double a2 = [p[1] doubleValue] - y;
                    double a3 = [p[2] doubleValue] - z;
                    double distance = sqrt(a1*a1 + a2*a2 + a3*a3);
                    if (distance < bestDistance) {
                        bestDistance = distance;
                        actualNearestNeighbor = @(i);
                    }
                }

                double distanceToNearestNeighbor = [self distanceFrom:xyz
                                                                   to:points[n.integerValue]];
                if (distanceToNearestNeighbor > bestDistance) {
                    NSLog(@"Oops");
                }
                XCTAssertEqualWithAccuracy(distanceToNearestNeighbor, bestDistance, 0.0001,
                                           @"Found wrong result");
            }
        }
    }
}

- (double)distanceFrom:(NSArray *)key1 to:(NSArray *)key2 {
    double sumOfSquares = 0;
    for (int i = 0; i < 3; i++) {
        double diff = [key1[i] doubleValue] - [key2[i] doubleValue];
        sumOfSquares += diff * diff;
    }
    return sqrt(sumOfSquares);
}

@end
