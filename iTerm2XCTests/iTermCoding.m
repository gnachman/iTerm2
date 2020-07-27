//
//  iTermCoding.m
//  iTerm2XCTests
//
//  Created by George Nachman on 7/26/20.
//

#import <XCTest/XCTest.h>
#import "iTermGraphEncoder.h"

@interface iTermCoding : XCTestCase

@end

@implementation iTermCoding

- (void)testPODRecord {
    iTermEncoderPODRecord *record;

    record = [iTermEncoderPODRecord withString:@"xyz" key:@"k"];
    XCTAssertEqual(record.type, iTermEncoderRecordTypeString);
    XCTAssertEqualObjects(record.key, @"k");
    XCTAssertEqualObjects(record.value, @"xyz");

    record = [iTermEncoderPODRecord withNumber:@123 key:@"k"];
    XCTAssertEqual(record.type, iTermEncoderRecordTypeNumber);
    XCTAssertEqualObjects(record.key, @"k");
    XCTAssertEqualObjects(record.value, @123);

    NSData *data = [NSData dataWithBytes:"xyz" length:3];
    record = [iTermEncoderPODRecord withData:data key:@"k"];
    XCTAssertEqual(record.type, iTermEncoderRecordTypeData);
    XCTAssertEqualObjects(record.key, @"k");
    XCTAssertEqualObjects(record.value, data);

    NSDate *date = [NSDate date];
    record = [iTermEncoderPODRecord withDate:date key:@"k"];
    XCTAssertEqual(record.type, iTermEncoderRecordTypeDate);
    XCTAssertEqualObjects(record.key, @"k");
    XCTAssertEqualObjects(record.value, date);
}

- (void)testGraphRecord_OnlyPOD {
    NSArray<iTermEncoderPODRecord *> *pods =
    @[ [iTermEncoderPODRecord withNumber:@1 key:@"one"],
       [iTermEncoderPODRecord withString:@"x" key:@"letter"] ];

    NSArray<iTermEncoderGraphRecord *> *graphs = nil;
    iTermEncoderGraphRecord *record;
    record = [iTermEncoderGraphRecord withPODs:pods
                                        graphs:graphs
                                    generation:3
                                           key:@"root"
                                    identifier:nil];

    NSDictionary<NSString *, iTermEncoderPODRecord *> *expectedRecords =
    @{ @"one": pods[0],
       @"letter": pods[1] };
    XCTAssertEqualObjects(expectedRecords, record.podRecords);
    XCTAssertEqualObjects(@[], record.graphRecords);
    XCTAssertEqual(3, record.generation);
    XCTAssertEqualObjects(@"root", record.key);
    XCTAssertNil(record.identifier);
}

- (void)testGraphRecord {
    NSArray<iTermEncoderPODRecord *> *pods1 =
    @[ [iTermEncoderPODRecord withNumber:@1 key:@"one"],
       [iTermEncoderPODRecord withString:@"x" key:@"letter"] ];
    NSArray<iTermEncoderPODRecord *> *pods2 =
    @[ [iTermEncoderPODRecord withNumber:@2 key:@"one"],
       [iTermEncoderPODRecord withString:@"y" key:@"letter"] ];
    NSData *data = [NSData dataWithBytes:"xyz" length:3];
    NSArray<iTermEncoderPODRecord *> *pods3 =
    @[ [iTermEncoderPODRecord withDate:[NSDate date] key:@"now"],
       [iTermEncoderPODRecord withData:data key:@"data"] ];

    NSArray<iTermEncoderGraphRecord *> *graphs =
    @[
        [iTermEncoderGraphRecord withPODs:pods1 graphs:@[] generation:3 key:@"k" identifier:@"id1"],
        [iTermEncoderGraphRecord withPODs:pods2 graphs:@[] generation:5 key:@"k" identifier:@"id2"],
    ];
    iTermEncoderGraphRecord *record;
    record = [iTermEncoderGraphRecord withPODs:pods3
                                        graphs:graphs
                                    generation:7
                                           key:@"root"
                                    identifier:nil];

    NSDictionary<NSString *, iTermEncoderPODRecord *> *expectedPODRecords =
    @{ @"now": pods3[0],
       @"data": pods3[1] };
    XCTAssertEqualObjects(expectedPODRecords, record.podRecords);
    XCTAssertEqualObjects(graphs, record.graphRecords);
    XCTAssertEqual(7, record.generation);
    XCTAssertEqualObjects(record.key, @"root");
    XCTAssertNil(record.identifier);
}

- (void)testGraphEncoder {
    iTermGraphEncoder *encoder = [[iTermGraphEncoder alloc] initWithKey:@"root"
                                                             identifier:nil
                                                             generation:1];
    [encoder encodeString:@"red" forKey:@"color"];
    [encoder encodeNumber:@1 forKey:@"count"];
    [encoder encodeChildWithKey:@"left" identifier:nil generation:2 block:^(iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeString:@"bob" forKey:@"name"];
    }];
    [encoder encodeChildWithKey:@"right" identifier:nil generation:3 block:^(iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeNumber:@23 forKey:@"age"];
    }];

    iTermEncoderGraphRecord *actual = encoder.record;

    NSArray *expectedPODs = @[ [iTermEncoderPODRecord withString:@"red" key:@"color"],
                               [iTermEncoderPODRecord withNumber:@1 key:@"count"] ];
    iTermEncoderPODRecord *name = [iTermEncoderPODRecord withString:@"bob" key:@"name"];
    iTermEncoderPODRecord *age = [iTermEncoderPODRecord withNumber:@23 key:@"age"];
    NSArray *expectedGraphs =
    @[ [iTermEncoderGraphRecord withPODs:@[ name ] graphs:@[] generation:2 key:@"left" identifier:nil],
       [iTermEncoderGraphRecord withPODs:@[ age ] graphs:@[] generation:3 key:@"right" identifier:nil] ];
    iTermEncoderGraphRecord *expected = [iTermEncoderGraphRecord withPODs:expectedPODs
                                                                   graphs:expectedGraphs
                                                               generation:1
                                                                      key:@"root"
                                                               identifier:nil];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testGraphTableTransformer_HappyPath {
    NSArray *nodes = @[
        // key, identifier, parent, generation
        @[ @"k5", @"",   @"k4,i2,1", @1 ],
        @[ @"k4", @"i2", @"k2,,1",   @1 ],
        @[ @"k4", @"i1", @"k2,,1",   @1 ],
        @[ @"k2", @"",   @"k1,,1",   @1 ],
        @[ @"k1", @"",   @"",        @1 ],  // Root
    ];

    NSData *data = [NSData dataWithBytes:"xyz" length:3];
    NSDate *date = [NSDate date];
    // nodeid, key, value, type
    NSArray *values = @[
        @[ @"k1,,1", @"vk1", @"vv1", @(iTermEncoderRecordTypeString) ],
        @[ @"k1,,1", @"vk2", @123, @(iTermEncoderRecordTypeNumber) ],
        @[ @"k1,,1", @"vk3", date, @(iTermEncoderRecordTypeDate) ],
        @[ @"k1,,1", @"vk4", data, @(iTermEncoderRecordTypeData) ],

        @[ @"k5,,1", @"vk5", @"vv2", @(iTermEncoderRecordTypeString) ]
    ];

    iTermGraphTableTransformer *transformer =
    [[iTermGraphTableTransformer alloc] initWithNodeRows:nodes
                                               valueRows:values];

    iTermEncoderGraphRecord *record = transformer.root;
    XCTAssertNotNil(record);

    NSArray<iTermEncoderPODRecord *> *expectedRootPODs = @[
        [iTermEncoderPODRecord withString:@"vv1" key:@"vk1"],
        [iTermEncoderPODRecord withNumber:@123 key:@"vk2"],
        [iTermEncoderPODRecord withDate:date key:@"vk3"],
        [iTermEncoderPODRecord withData:data key:@"vk4"],
    ];
    NSArray<iTermEncoderPODRecord *> *expectedK5PODs = @[
        [iTermEncoderPODRecord withString:@"vv2" key:@"vk5"],
    ];

    NSArray<iTermEncoderGraphRecord *> *expectedK4Children = @[
        [iTermEncoderGraphRecord withPODs:expectedK5PODs
                                   graphs:@[]
                               generation:1
                                      key:@"k5"
                               identifier:nil],
    ];
    NSArray<iTermEncoderGraphRecord *> *expectedK2Children = @[
        [iTermEncoderGraphRecord withPODs:@[]
                                   graphs:expectedK4Children
                               generation:1
                                      key:@"k4"
                               identifier:@"i2"],
        [iTermEncoderGraphRecord withPODs:@[]
                                   graphs:@[]
                               generation:1
                                      key:@"k4"
                               identifier:@"i1"],
    ];
    NSArray<iTermEncoderGraphRecord *> *expectedRootGraphs = @[
        [iTermEncoderGraphRecord withPODs:@[]
                                   graphs:expectedK2Children
                               generation:1
                                      key:@"k2"
                               identifier:nil],

    ];
    iTermEncoderGraphRecord *expected =
    [iTermEncoderGraphRecord withPODs:expectedRootPODs
                               graphs:expectedRootGraphs
                           generation:1
                                  key:@"k1"
                           identifier:nil];

    iTermEncoderGraphRecord *actual = transformer.root;
    XCTAssertEqualObjects(expected, actual);
}

- (void)testDeltaEncoder {
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:nil];
    [encoder encodeString:@"k1_v1" forKey:@"k1"];
    [encoder encodeChildWithKey:@"k2" identifier:nil generation:1 block:^(iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeString:@"k3_v1" forKey:@"k3"];

        [subencoder encodeChildWithKey:@"k4" identifier:nil generation:1 block:^(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"k5_v1" forKey:@"k5"];
        }];
        [subencoder encodeChildWithKey:@"k6" identifier:@"i1" generation:1 block:^(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"k7_v1" forKey:@"k7"];
        }];
        [subencoder encodeChildWithKey:@"k6" identifier:@"i2" generation:1 block:^(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"k9_v1" forKey:@"k9"];
            [subencoder encodeString:@"k9a_v1" forKey:@"k9a"];
        }];
        [subencoder encodeChildWithKey:@"k6" identifier:@"i3" generation:1 block:^(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"k10_v1" forKey:@"k10"];
        }];
    }];

    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeString:@"k1_v2" forKey:@"k1"];
    [encoder encodeChildWithKey:@"k2" identifier:nil generation:2 block:^(iTermGraphEncoder * _Nonnull subencoder) {
        // Omit k3
        [subencoder encodeChildWithKey:@"k4" identifier:nil generation:1 block:^(iTermGraphEncoder * _Nonnull subencoder) {
            XCTFail(@"Shouldn't reach this because generation is unchanged.");
        }];
        // omit k6.i1
        [subencoder encodeChildWithKey:@"k6" identifier:@"i2" generation:2 block:^(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"k9_v2" forKey:@"k9"];
            [subencoder encodeString:@"k9a_v1" forKey:@"k9a"];
            [subencoder encodeString:@"k9b_v1" forKey:@"k9b"];
        }];
        [subencoder encodeChildWithKey:@"k6" identifier:@"i3" generation:1 block:^(iTermGraphEncoder * _Nonnull subencoder) {
            XCTFail(@"Shouldn't reach this because generation is unchanged.");
        }];
        [subencoder encodeChildWithKey:@"k6" identifier:@"i4" generation:1 block:^(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"k11_v1" forKey:@"k11"];
        }];
    }];

    NSMutableArray<NSString *> *actual = [NSMutableArray array];
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSString *context) {
        if (before && !after) {
            [actual addObject:[NSString stringWithFormat:@"delete node where key=%@.%@, context=%@",
                               before.key, before.identifier ?: @"", context]];
            [before enumerateValuesVersus:nil block:^(iTermEncoderPODRecord * _Nullable mine,
                                                      iTermEncoderPODRecord * _Nullable theirs) {
                [actual addObject:[NSString stringWithFormat:@"delete value where key=%@, node=%@.%@, context=%@",
                                   mine.key, before.key, before.identifier ?: @"", context]];
            }];
        } else if (!before && after) {
            [actual addObject:[NSString stringWithFormat:@"insert node key=%@.%@, parent=%@.%@, context=%@",
                               after.key, after.identifier ?: @"",
                               after.parent.key, after.parent.identifier ?: @"",
                               context]];
            [after enumerateValuesVersus:nil block:^(iTermEncoderPODRecord * _Nullable record,
                                                     iTermEncoderPODRecord * _Nullable na) {
                [actual addObject:[NSString stringWithFormat:@"insert value key=%@, value=%@, node=%@.%@, context=%@",
                                   record.key, record.value, after.key, after.identifier ?: @"", context]];
            }];
        } else if (before && after) {
            [before enumerateValuesVersus:after block:^(iTermEncoderPODRecord * _Nullable mine,
                                                        iTermEncoderPODRecord * _Nullable theirs) {
                if (mine && theirs) {
                    if (![mine isEqual:theirs]) {
                        [actual addObject:[NSString stringWithFormat:@"update value where key=%@, node=%@.%@, context=%@ value=%@",
                                           mine.key, before.key, before.identifier ?: @"", context, theirs.value]];
                    }
                } else if (!mine && theirs) {
                    [actual addObject:[NSString stringWithFormat:@"insert value key=%@, value=%@, node=%@.%@, context=%@",
                                       theirs.key, theirs.value, before.key, before.identifier ?: @"", context]];
                } else if (mine && !theirs) {
                    [actual addObject:[NSString stringWithFormat:@"delete value where key=%@, node=%@, context=%@",
                                       mine.key, before.key, before.identifier ?: @"", context]];
                } else {
                    XCTFail(@"At least one of before/after should be nonnil");
                }
            }];
        } else {
            XCTFail(@"At least one of before/after should be nonnil");
        }
    }];

    NSArray<NSString *> *expected = @[
        @"update value where key=k1, context= value=k1_v2",
        @"delete value where key=k3, context=k2",
        @"delete node where key=k6.i1, context=k2",
        @"delete value where key=k7, context=k2.k6[i1]",
        @"update value where key=k9, context=k2.k6[i2] value=k9_v2",
        @"insert value key=k9b, value=k9b_v1, context=k2.k6[i2]",
        @"insert node key=k6.i4, parent=k2., context=k2",
        @"insert value key=k11, value=k11_v1, context=k2.k6[i4]"
    ];
    XCTAssertEqualObjects(actual, expected);
}
@end
