//
//  iTermCoding.m
//  iTerm2XCTests
//
//  Created by George Nachman on 7/26/20.
//

#import <XCTest/XCTest.h>
#import "iTermGraphEncoder.h"
#import "iTermGraphDatabase.h"
#import "iTermThreadSafety.h"

@interface NSObject(Coding)
+ (instancetype)force:(id)obj;
@end

@implementation NSObject(Coding)
+ (instancetype)force:(id)obj {
    assert(obj != nil);
    const BOOL ok = [obj isKindOfClass:self];
    assert(ok);
    return obj;
}
@end

@interface iTermCoding : XCTestCase
@end

@interface iTermMockDatabaseResultSet: NSObject<iTermDatabaseResultSet>
@property (nonatomic, readonly, copy) NSArray<NSDictionary *> *rows;
@end

@implementation iTermMockDatabaseResultSet {
    NSInteger _next;
}

+ (instancetype)withRows:(NSArray<NSDictionary *> *)rows {
    iTermMockDatabaseResultSet *set = [[iTermMockDatabaseResultSet alloc] init];
    set->_rows = rows;
    return set;
}

- (BOOL)next {
    _next +=1 ;
    return (_next - 1 < _rows.count);
}

- (void)close {
    _next = 0;
}

- (NSString *)stringForColumn:(NSString *)columnName {
    const NSInteger i = _next - 1;
    return [NSString force:_rows[i][columnName]];
}

- (long long)longLongIntForColumn:(NSString *)columnName {
    const NSInteger i = _next - 1;
    return [[NSNumber force:_rows[i][columnName]] longLongValue];
}

- (NSData *)dataForColumn:(NSString *)columnName {
    const NSInteger i = _next - 1;
    return [NSData force:_rows[i][columnName]];
}

- (NSDate *)dateForColumn:(NSString *)columnName {
    const NSInteger i = _next - 1;
    return [NSDate force:_rows[i][columnName]];
}

@end

@interface iTermMockDatabase: NSObject<iTermDatabase>
@property (nonatomic) BOOL shouldOpen;
@property (nonatomic, readonly, getter=isOpen) BOOL open;
@property (nonatomic, readonly) NSArray<NSString *> *commands;
@property (nonatomic, readonly) NSMutableDictionary<NSString *, id<iTermDatabaseResultSet>> *results;
@property (nonatomic, strong) NSError *lastError;
@property (nonatomic, readonly) NSURL *url;

- (instancetype)initWithURL:(NSURL *)url
                    results:(NSMutableDictionary<NSString *, id<iTermDatabaseResultSet>> *)results NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface iTermMockDatabaseFactory: NSObject<iTermDatabaseFactory>
@property (nonatomic, readonly) NSArray<NSString *> *commands;
@property (nonatomic, readonly) NSMutableDictionary<NSString *, id<iTermDatabaseResultSet>> *results;
@property (nonatomic, readonly, nullable) iTermMockDatabase *database;

- (instancetype)initWithResults:(NSMutableDictionary<NSString *, id<iTermDatabaseResultSet>> *)results NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@implementation iTermMockDatabaseFactory

- (instancetype)initWithResults:(NSMutableDictionary<NSString *, id<iTermDatabaseResultSet>> *)results {
    self = [super init];
    if (self) {
        _results = results;
    }
    return self;
}

- (id<iTermDatabase>)withURL:(NSURL *)url {
    if (!_database) {
        _database = [[iTermMockDatabase alloc] initWithURL:url
                                                   results:_results];
    }
    return _database;
}

@end

@implementation iTermMockDatabase {
    NSMutableArray<NSString *> *_commands;
    BOOL _open;
}

- (instancetype)initWithURL:(NSURL *)url
                    results:(NSMutableDictionary<NSString *, id<iTermDatabaseResultSet>> *)results {
    self = [super init];
    if (self) {
        _url = url;
        _commands = [NSMutableArray array];
        _results = results;
        _shouldOpen = YES;
    }
    return self;
}

- (BOOL)executeUpdate:(NSString *)sql, ... {
    va_list args;
    va_start(args, sql);

    NSMutableString *string = [sql mutableCopy];
    NSInteger index = [string rangeOfString:@"?"].location;
    while (index != NSNotFound) {
        id obj = va_arg(args, id);
        [string replaceCharactersInRange:NSMakeRange(index, 1) withString:[obj description]];
        index = [string rangeOfString:@"?"].location;
    }
    va_end(args);

    [_commands addObject:string];
    return YES;
}

- (id<iTermDatabaseResultSet> _Nullable)executeQuery:(NSString*)sql, ... {
    va_list args;
    va_start(args, sql);

    NSMutableString *string = [sql mutableCopy];
    NSInteger index = [string rangeOfString:@"?"].location;
    while (index != NSNotFound) {
        id obj = va_arg(args, id);
        [string replaceCharactersInRange:NSMakeRange(index, 1) withString:[obj description]];
        index = [string rangeOfString:@"?"].location;
    }
    va_end(args);

    assert(_results[string] != nil);
    return _results[string];
}

- (BOOL)open {
    if (_shouldOpen) {
        _open = YES;
    }
    return _shouldOpen;
}

- (BOOL)transaction:(BOOL (^ NS_NOESCAPE)(void))block {
    return block();
}

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

/*
 <root vk1=vv1 vk2=@123 vk3=date vk4=data>
   <k2>
     <k4[i1]>
     <k4[i2]>
       <k5 vv2=vk5>
 */
- (void)testGraphTableTransformer_HappyPath {
    NSArray *nodes = @[
        // key, identifier, parent, generation
        @[ @"k5", @"",   @"k2.k4[i2]", @1 ],
        @[ @"k4", @"i2", @"k2",        @1 ],
        @[ @"k4", @"i1", @"k2",        @1 ],
        @[ @"k2", @"",   @"",          @1 ],
        @[ @"",   @"",   @"",          @1 ],  // Root
    ];

    NSData *data = [NSData dataWithBytes:"xyz" length:3];
    NSDate *date = [NSDate date];
    NSData *(^d)(id) = ^NSData *(id obj) {
        if ([obj isKindOfClass:[NSString class]]) {
            return [iTermEncoderPODRecord withString:obj key:@""].data;
        }
        if ([obj isKindOfClass:[NSData class]]) {
            return obj;
        }
        if ([obj isKindOfClass:[NSDate class]]) {
            return [iTermEncoderPODRecord withDate:obj key:@""].data;
        }
        if ([obj isKindOfClass:[NSNumber class]]) {
            return [iTermEncoderPODRecord withNumber:obj key:@""].data;
        }
        assert(NO);
    };
    // nodeid, key, value, type
    NSArray *values = @[
        @[ @"", @"vk1", d(@"vv1"), @(iTermEncoderRecordTypeString) ],
        @[ @"", @"vk2", d(@123), @(iTermEncoderRecordTypeNumber) ],
        @[ @"", @"vk3", d(date), @(iTermEncoderRecordTypeDate) ],
        @[ @"", @"vk4", d(data), @(iTermEncoderRecordTypeData) ],

        @[ @"k2.k4[i2].k5", @"vk5", d(@"vv2"), @(iTermEncoderRecordTypeString) ]
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

- (void)testDeltaEncoder_UpdateValue {
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:nil];
    [encoder encodeChildWithKey:@"root" identifier:nil generation:1 block:^(iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeChildWithKey:@"leaf" identifier:nil generation:1 block:^(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"value1" forKey:@"key"];
        }];
    }];
    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeChildWithKey:@"root" identifier:nil generation:2 block:^(iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeChildWithKey:@"leaf" identifier:nil generation:2 block:^(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"value2" forKey:@"key"];
        }];
    }];
    __block BOOL done = NO;
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSString *context) {
        XCTAssertFalse(done);
        XCTAssertNotNil(before);
        XCTAssertNotNil(after);
        [before enumerateValuesVersus:after block:^(iTermEncoderPODRecord * _Nullable mine,
                                                    iTermEncoderPODRecord * _Nullable theirs) {
            XCTAssertEqualObjects(mine.value, @"value1");
            XCTAssertEqualObjects(theirs.value, @"value2");
            done = YES;
        }];
    }];
    XCTAssertTrue(done);
}

- (void)testDeltaEncoder_DeleteValue {
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:nil];
    [encoder encodeChildWithKey:@"root" identifier:nil generation:1 block:^(iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeChildWithKey:@"leaf" identifier:nil generation:1 block:^(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"value1" forKey:@"key"];
        }];
    }];
    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeChildWithKey:@"root" identifier:nil generation:2 block:^(iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeChildWithKey:@"leaf" identifier:nil generation:2 block:^(iTermGraphEncoder * _Nonnull subencoder) {
        }];
    }];
    __block BOOL done = NO;
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSString *context) {
        XCTAssertFalse(done);
        XCTAssertNotNil(before);
        XCTAssertNotNil(after);
        [before enumerateValuesVersus:after block:^(iTermEncoderPODRecord * _Nullable mine,
                                                    iTermEncoderPODRecord * _Nullable theirs) {
            XCTAssertEqualObjects(mine.value, @"value1");
            XCTAssertNil(theirs);
            done = YES;
        }];
    }];
    XCTAssertTrue(done);
}

- (void)testDeltaEncoder_InsertValue {
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:nil];
    [encoder encodeChildWithKey:@"root" identifier:nil generation:1 block:^(iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeChildWithKey:@"leaf" identifier:nil generation:1 block:^(iTermGraphEncoder * _Nonnull subencoder) {
        }];
    }];
    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeChildWithKey:@"root" identifier:nil generation:2 block:^(iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeChildWithKey:@"leaf" identifier:nil generation:2 block:^(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"value1" forKey:@"key"];
        }];
    }];
    __block BOOL done = NO;
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSString *context) {
        XCTAssertFalse(done);
        XCTAssertNotNil(before);
        XCTAssertNotNil(after);
        [before enumerateValuesVersus:after block:^(iTermEncoderPODRecord * _Nullable mine,
                                                    iTermEncoderPODRecord * _Nullable theirs) {
            XCTAssertEqualObjects(theirs.value, @"value1");
            XCTAssertNil(mine);
            done = YES;
        }];
    }];
    XCTAssertTrue(done);
}

- (void)testDeltaEncoder_DeleteNode {
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:nil];
    [encoder encodeChildWithKey:@"root" identifier:nil generation:1 block:^(iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeChildWithKey:@"leaf" identifier:nil generation:1 block:^(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"value1" forKey:@"key"];
        }];
    }];
    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeChildWithKey:@"root" identifier:nil generation:2 block:^(iTermGraphEncoder * _Nonnull subencoder) {
    }];
    __block BOOL done = NO;
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSString *context) {
        if ([before.key isEqualToString:@"leaf"]) {
            XCTAssertNil(after);
            [before enumerateValuesVersus:after block:^(iTermEncoderPODRecord * _Nullable mine,
                                                        iTermEncoderPODRecord * _Nullable theirs) {
                XCTAssertEqualObjects(mine.value, @"value1");
                XCTAssertNil(theirs);
                done = YES;
            }];
        }
    }];
    XCTAssertTrue(done);
}

- (void)testDeltaEncoder_InsertNode {
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:nil];
    [encoder encodeChildWithKey:@"root" identifier:nil generation:1 block:^(iTermGraphEncoder * _Nonnull subencoder) {
    }];
    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeChildWithKey:@"root" identifier:nil generation:2 block:^(iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeChildWithKey:@"leaf" identifier:nil generation:1 block:^(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"value1" forKey:@"key"];
        }];
    }];
    __block BOOL done = NO;
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSString *context) {
        if ([after.key isEqualToString:@"leaf"]) {
            XCTAssertNil(before);
            [after enumerateValuesVersus:before block:^(iTermEncoderPODRecord * _Nullable mine,
                                                        iTermEncoderPODRecord * _Nullable theirs) {
                XCTAssertNil(theirs);
                XCTAssertEqualObjects(mine.value, @"value1");
                done = YES;
            }];
        }
    }];
    XCTAssertTrue(done);
}

- (void)testDeltaEncoderArray_NoGenerationChange {
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:nil];
    [encoder encodeArrayWithKey:@"a"
                     generation:1
                    identifiers:@[ @"i1", @"i2", @"i3" ]
                          block:^(NSString * _Nonnull identifier,
                                  NSInteger index,
                                  iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeString:[NSString stringWithFormat:@"value1_%@_%@", identifier, @(index)]
                          forKey:@"k"];
    }];

    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeArrayWithKey:@"a"
                     generation:1
                    identifiers:@[ @"i1", @"i2", @"i3" ]
                          block:^(NSString * _Nonnull identifier, NSInteger index, iTermGraphEncoder * _Nonnull subencoder) {
        XCTFail(@"Should not have been called because generation didn't change");
    }];
}

- (void)testDeltaEncoderArray_ModifyValues {
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:nil];
    [encoder encodeArrayWithKey:@"a"
                     generation:1
                    identifiers:@[ @"i1", @"i2", @"i3" ]
                          block:^(NSString * _Nonnull identifier,
                                  NSInteger index,
                                  iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeString:[NSString stringWithFormat:@"value1_%@_%@", identifier, @(index)]
                          forKey:[NSString stringWithFormat:@"k_%@", identifier]];
    }];
    {
        NSSet<NSString *> *actual = [NSSet setWithArray:[self pseudoSQLFromEncoder:encoder]];
        NSSet<NSString *> *expected = [NSSet setWithArray:@[
            @"insert node key=., context=",
            @"insert node key=__array.a, context=",
            @"insert value key=k_i2, value=value1_i2_1, node=__array.a, context=",
            @"insert value key=k_i3, value=value1_i3_2, node=__array.a, context=",
            @"insert value key=k_i1, value=value1_i1_0, node=__array.a, context=",
            @"insert value key=__order, value=i1,i2,i3, node=__array.a, context=",
        ]];
        XCTAssertEqualObjects(actual, expected);
    }

    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeArrayWithKey:@"a"
                     generation:2
                    identifiers:@[ @"i1", @"i2", @"i3" ]
                          block:^(NSString * _Nonnull identifier, NSInteger index, iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeString:[NSString stringWithFormat:@"value2_%@_%@", identifier, @(index)]
                          forKey:[NSString stringWithFormat:@"k_%@", identifier]];
    }];

    {
        NSSet<NSString *> *actual = [NSSet setWithArray:[self pseudoSQLFromEncoder:encoder]];
        NSSet<NSString *> *expected = [NSSet setWithArray:@[
            @"update value where key=k_i1, node=__array.a, context= value=value2_i1_0",
            @"update value where key=k_i2, node=__array.a, context= value=value2_i2_1",
            @"update value where key=k_i3, node=__array.a, context= value=value2_i3_2",
        ]];
        XCTAssertEqualObjects(actual, expected);
    }
}

- (void)testDeltaEncoderArray_DeleteFirstValue {
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:nil];
    [encoder encodeArrayWithKey:@"a"
                     generation:1
                    identifiers:@[ @"i1", @"i2", @"i3" ]
                          block:^(NSString * _Nonnull identifier,
                                  NSInteger index,
                                  iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeChildWithKey:@"container"
                            identifier:identifier
                            generation:1
                                 block:^(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:[NSString stringWithFormat:@"value1_%@_%@", identifier, @(index)]
                              forKey:[NSString stringWithFormat:@"k_%@", identifier]];
        }];
    }];
    {
        NSSet<NSString *> *actual = [NSSet setWithArray:[self pseudoSQLFromEncoder:encoder]];
        NSSet<NSString *> *expected = [NSSet setWithArray:@[
            @"insert node key=., context=",
            @"insert node key=__array.a, context=",
            @"insert node key=container.i1, context=__array[a]",
            @"insert value key=k_i1, value=value1_i1_0, node=container.i1, context=__array[a]",
            @"insert node key=container.i2, context=__array[a]",
            @"insert value key=k_i2, value=value1_i2_1, node=container.i2, context=__array[a]",
            @"insert node key=container.i3, context=__array[a]",
            @"insert value key=k_i3, value=value1_i3_2, node=container.i3, context=__array[a]",
            @"insert value key=__order, value=i1,i2,i3, node=__array.a, context=",
        ]];
        XCTAssertEqualObjects(actual, expected);
    }

    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeArrayWithKey:@"a"
                     generation:2
                    identifiers:@[ @"i2", @"i3" ]
                          block:^(NSString * _Nonnull identifier,
                                  NSInteger index,
                                  iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeChildWithKey:@"container"
                            identifier:identifier
                            generation:1
                                 block:^(iTermGraphEncoder * _Nonnull subencoder) {
            XCTFail(@"Should not be called because generation didn't change");
        }];
    }];

    {
        NSArray<NSString *> *actual = [self pseudoSQLFromEncoder:encoder];
        NSArray<NSString *> *expected = @[
            @"update value where key=__order, node=__array.a, context= value=i2,i3",
            @"delete node where key=container.i1, context=__array[a]",
            @"delete value where key=k_i1, node=container.i1, context=__array[a]",
        ];
        XCTAssertEqualObjects(actual, expected);
    }
}

- (void)testDeltaEncoderArray_Append {
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:nil];
    [encoder encodeArrayWithKey:@"a"
                     generation:1
                    identifiers:@[ @"i1", @"i2", @"i3" ]
                          block:^(NSString * _Nonnull identifier,
                                  NSInteger index,
                                  iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeChildWithKey:@"container"
                            identifier:identifier
                            generation:1
                                 block:^(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:[NSString stringWithFormat:@"value1_%@_%@", identifier, @(index)]
                              forKey:[NSString stringWithFormat:@"k_%@", identifier]];
        }];
    }];
    {
        NSSet<NSString *> *actual = [NSSet setWithArray:[self pseudoSQLFromEncoder:encoder]];
        NSSet<NSString *> *expected = [NSSet setWithArray:@[
            @"insert node key=., context=",
            @"insert node key=__array.a, context=",
            @"insert node key=container.i1, context=__array[a]",
            @"insert value key=k_i1, value=value1_i1_0, node=container.i1, context=__array[a]",
            @"insert node key=container.i2, context=__array[a]",
            @"insert value key=k_i2, value=value1_i2_1, node=container.i2, context=__array[a]",
            @"insert node key=container.i3, context=__array[a]",
            @"insert value key=k_i3, value=value1_i3_2, node=container.i3, context=__array[a]",
            @"insert value key=__order, value=i1,i2,i3, node=__array.a, context=",
        ]];
        XCTAssertEqualObjects(actual, expected);
    }

    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeArrayWithKey:@"a"
                     generation:2
                    identifiers:@[ @"i1", @"i2", @"i3", @"i4" ]
                          block:^(NSString * _Nonnull identifier,
                                  NSInteger index,
                                  iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeChildWithKey:@"container"
                            identifier:identifier
                            generation:1
                                 block:^(iTermGraphEncoder * _Nonnull subencoder) {
            XCTAssertEqualObjects(identifier, @"i4");
            [subencoder encodeString:[NSString stringWithFormat:@"value1_%@_%@", identifier, @(index)]
                              forKey:[NSString stringWithFormat:@"k_%@", identifier]];
        }];
    }];

    {
        NSArray<NSString *> *actual = [self pseudoSQLFromEncoder:encoder];
        NSArray<NSString *> *expected = @[
            @"update value where key=__order, node=__array.a, context= value=i1,i2,i3,i4",
            @"insert node key=container.i4, context=__array[a]",
            @"insert value key=k_i4, value=value1_i4_3, node=container.i4, context=__array[a]",
        ];
        XCTAssertEqualObjects(actual, expected);
    }
}

- (NSArray<NSString *> *)pseudoSQLFromEncoder:(iTermGraphDeltaEncoder *)encoder {
    NSMutableArray<NSString *> *statements = [NSMutableArray array];
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSString *context) {
        if (before && !after) {
            [statements addObject:[NSString stringWithFormat:@"delete node where key=%@.%@, context=%@",
                                   before.key, before.identifier ?: @"", context]];
            [before enumerateValuesVersus:nil block:^(iTermEncoderPODRecord * _Nullable mine,
                                                      iTermEncoderPODRecord * _Nullable theirs) {
                [statements addObject:[NSString stringWithFormat:@"delete value where key=%@, node=%@.%@, context=%@",
                                       mine.key, before.key, before.identifier ?: @"", context]];
            }];
        } else if (!before && after) {
            [statements addObject:[NSString stringWithFormat:@"insert node key=%@.%@, context=%@",
                                   after.key, after.identifier ?: @"",
                                   context]];
            [after enumerateValuesVersus:nil block:^(iTermEncoderPODRecord * _Nullable record,
                                                     iTermEncoderPODRecord * _Nullable na) {
                [statements addObject:[NSString stringWithFormat:@"insert value key=%@, value=%@, node=%@.%@, context=%@",
                                       record.key, record.value, after.key, after.identifier ?: @"", context]];
            }];
        } else if (before && after) {
            [before enumerateValuesVersus:after block:^(iTermEncoderPODRecord * _Nullable mine,
                                                        iTermEncoderPODRecord * _Nullable theirs) {
                if (mine && theirs) {
                    if (![mine isEqual:theirs]) {
                        [statements addObject:[NSString stringWithFormat:@"update value where key=%@, node=%@.%@, context=%@ value=%@",
                                               mine.key, before.key, before.identifier ?: @"", context, theirs.value]];
                    }
                } else if (!mine && theirs) {
                    [statements addObject:[NSString stringWithFormat:@"insert value key=%@, value=%@, node=%@.%@, context=%@",
                                           theirs.key, theirs.value, before.key, before.identifier ?: @"", context]];
                } else if (mine && !theirs) {
                    [statements addObject:[NSString stringWithFormat:@"delete value where key=%@, node=%@.%@, context=%@",
                                           mine.key, before.key, before.identifier ?: @"", context]];
                } else {
                    XCTFail(@"At least one of before/after should be nonnil");
                }
            }];
        } else {
            XCTFail(@"At least one of before/after should be nonnil");
        }
    }];
    return statements;
}

- (void)testDeltaEncoder {
    /*
       [root k1=k1_v1]
         [k2 k3=k3_v1]
           [k4 k5=k5v1]
           [k6[i1] k7=k7_v1]
           [k6[i2] k9=k9_v1 k9a=k9a_v1]
           [k6[i3] k10=k10_v1]
     */
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

    /*
       [root k1=k1_v2]
         [k2]
           [k4 k5=k5v1]
           [k6[i2] k9=k9_v2 k9a=k9a_v1 k9b=k9b_v1]
           [k6[i3] k10=k10_v1]
           [k6[i4] k11=k11_v1]
     */
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

    NSArray<NSString *> *actual = [self pseudoSQLFromEncoder:encoder];
    NSArray<NSString *> *expected = @[
        @"update value where key=k1, node=., context= value=k1_v2",
        @"delete value where key=k3, node=k2., context=",
        @"delete node where key=k6.i1, context=k2",
        @"delete value where key=k7, node=k6.i1, context=k2",
        @"update value where key=k9, node=k6.i2, context=k2 value=k9_v2",
        @"insert value key=k9b, value=k9b_v1, node=k6.i2, context=k2",
        @"insert node key=k6.i4, context=k2",
        @"insert value key=k11, value=k11_v1, node=k6.i4, context=k2"
    ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testGraphDatabase_InitialAdd {
    NSMutableDictionary<NSString *,id<iTermDatabaseResultSet>> *results = [NSMutableDictionary dictionary];
    results[@"select * from Node"] = [iTermMockDatabaseResultSet withRows:@[]];
    results[@"select * from Value"] = [iTermMockDatabaseResultSet withRows:@[]];

    iTermMockDatabaseFactory *mockDB = [[iTermMockDatabaseFactory alloc] initWithResults:results];
    iTermGraphDatabase *gdb = [[iTermGraphDatabase alloc] initWithURL:[NSURL fileURLWithPath:@"/db"]
                                                      databaseFactory:mockDB];
    XCTAssertNotNil(gdb);
    iTermMockDatabase *db = mockDB.database;
    XCTAssertNotNil(db);

    XCTAssertNil(gdb.record);
    [gdb.thread performDeferredBlocksAfter:^{
        [gdb update:^(iTermGraphEncoder * _Nonnull encoder) {
            [encoder encodeChildWithKey:@"mynode" identifier:nil generation:1 block:^(iTermGraphEncoder * _Nonnull subencoder) {
                [subencoder encodeString:@"red" forKey:@"color"];
                [subencoder encodeNumber:@123 forKey:@"number"];
            }];
        }];
    }];

    NSArray<NSString *> *expectedCommands = @[
        @"create table Node (key text, identifier text, context text, generation integer)",
        @"create table Value (key text, context text, value blob, type integer)",
        @"insert into Node (key, identifier, context, generation) values (, , , 1)",
        @"insert into Node (key, identifier, context, generation) values (mynode, , , 1)",
        @"insert into Value (key, value, context, type) values (color, red, mynode, 0)",
        @"insert into Value (key, value, context, type) values (number, 123, mynode, 1)"
    ];
    XCTAssertEqualObjects(db.commands, expectedCommands);
}

- (void)testGraphDatabase_Load {
    NSMutableDictionary<NSString *,id<iTermDatabaseResultSet>> *results = [NSMutableDictionary dictionary];
    results[@"select * from Node"] = [iTermMockDatabaseResultSet withRows:@[
        @{ @"key": @"",
           @"identifier": @"",
           @"context": @"",
           @"generation": @1 },

        @{ @"key": @"mynode",
           @"identifier": @"",
           @"context": @"",
           @"generation": @1 },
    ]];
    const double d = 123;
    results[@"select * from Value"] = [iTermMockDatabaseResultSet withRows:@[
        @{ @"key": @"color",
           @"value": [@"red" dataUsingEncoding:NSUTF8StringEncoding],
           @"context": @"mynode",
           @"type": @0 },

        @{ @"key": @"number",
           @"value": [NSData dataWithBytes:&d length:sizeof(d)],
           @"context": @"mynode",
           @"type": @1 },
    ]];

    iTermMockDatabaseFactory *mockDB = [[iTermMockDatabaseFactory alloc] initWithResults:results];
    iTermGraphDatabase *gdb = [[iTermGraphDatabase alloc] initWithURL:[NSURL fileURLWithPath:@"/db"]
                                                      databaseFactory:mockDB];
    XCTAssertNotNil(gdb);
    iTermMockDatabase *db = mockDB.database;
    XCTAssertNotNil(db);

    NSArray<iTermEncoderPODRecord *> *pods = @[
        [iTermEncoderPODRecord withString:@"red" key:@"color"],
        [iTermEncoderPODRecord withNumber:@123 key:@"number"]
    ];
    iTermEncoderGraphRecord *mynode =
        [iTermEncoderGraphRecord withPODs:pods
                                   graphs:@[]
                               generation:1
                                      key:@"mynode"
                               identifier:nil];
    iTermEncoderGraphRecord *expectedRecord =
    [iTermEncoderGraphRecord withPODs:@[]
                               graphs:@[ mynode ]
                           generation:1
                                  key:@""
                           identifier:nil];

    XCTAssertEqualObjects(gdb.record, expectedRecord);
}

@end
