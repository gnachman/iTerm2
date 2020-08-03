//
//  iTermCoding.m
//  iTerm2XCTests
//
//  Created by George Nachman on 7/26/20.
//

#import <XCTest/XCTest.h>

#import "NSData+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "NSWorkspace+iTerm.h"
#import "iTermEncoderAdapter.h"
#import "iTermGraphEncoder.h"
#import "iTermGraphDatabase.h"
#import "iTermGraphDeltaEncoder.h"
#import "iTermGraphTableTransformer.h"
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
@property (nonatomic, readonly) NSMutableArray<NSString *> *commands;
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

- (instancetype)initWithResults:(NSMutableDictionary<NSString *, id<iTermDatabaseResultSet>> *)results
                       database:(iTermMockDatabase * _Nullable)database NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@implementation iTermMockDatabaseFactory

- (instancetype)initWithResults:(NSMutableDictionary<NSString *, id<iTermDatabaseResultSet>> *)results
                       database:(iTermMockDatabase * _Nullable)database {
    self = [super init];
    if (self) {
        _results = results;
        _database = database;
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
    BOOL _open;
    NSInteger _lastRowID;
    NSInteger _rowID;
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
        if ([obj isKindOfClass:[NSData class]]) {
            NSString *string = [[NSString alloc] initWithData:obj encoding:NSUTF8StringEncoding];
            if (string) {
                obj = string;
            } else if ([(NSData *)obj length] == 8) {
                double d;
                memmove(&d, [(NSData *)obj bytes], sizeof(d));
                obj = @(d);
            } else {
                obj = [(NSData *)obj it_hexEncoded];
            }
        }
        [string replaceCharactersInRange:NSMakeRange(index, 1) withString:[obj description]];
        index = [string rangeOfString:@"?"].location;
    }
    va_end(args);
    if ([sql.lowercaseString hasPrefix:@"insert"]) {
        _lastRowID = ++_rowID;
    } else {
        _lastRowID = 0;
    }

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

- (BOOL)close {
    _open = NO;
    return YES;
}

- (BOOL)transaction:(BOOL (^ NS_NOESCAPE)(void))block {
    return block();
}

- (NSNumber * _Nullable)lastInsertRowId {
    return @(_lastRowID);
}


@end

@implementation iTermCoding {
    NSInteger _rowid;
}

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

    NSDate *date = [NSDate dateWithTimeIntervalSince1970:1000000000];
    record = [iTermEncoderPODRecord withDate:date key:@"k"];
    XCTAssertEqual(record.type, iTermEncoderRecordTypeDate);
    XCTAssertEqualObjects(record.key, @"k");
    XCTAssertEqualObjects(record.value, date);
}

- (void)testInvalidDataForPODRecord {
    iTermEncoderPODRecord *record;
    record = [iTermEncoderPODRecord withData:[NSData dataWithBytes:"\xff\xff" length:1]
                                        type:iTermEncoderRecordTypeString
                                         key:@""];
    XCTAssertNil(record);

    record = [iTermEncoderPODRecord withData:[NSData dataWithBytes:"0" length:1]
                                        type:iTermEncoderRecordTypeNumber
                                         key:@""];
    XCTAssertNil(record);

    record = [iTermEncoderPODRecord withData:[NSData dataWithBytes:"0" length:1]
                                        type:iTermEncoderRecordTypeDate
                                         key:@""];
    XCTAssertNil(record);
}

- (void)testPODRecordIgnoresNils {
    XCTAssertNil([iTermEncoderPODRecord withString:(id _Nonnull)nil key:@""]);
    XCTAssertNil([iTermEncoderPODRecord withNumber:(id _Nonnull)nil key:@""]);
    XCTAssertNil([iTermEncoderPODRecord withData:(id _Nonnull)nil key:@""]);
    XCTAssertNil([iTermEncoderPODRecord withDate:(id _Nonnull)nil key:@""]);
}

- (void)testPODRecordCrossTypeComparison {
    NSString *string = @"abc";
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    iTermEncoderPODRecord *lhs = [iTermEncoderPODRecord withString:string key:@""];
    iTermEncoderPODRecord *rhs = [iTermEncoderPODRecord withData:data key:@""];
    XCTAssertNotEqualObjects(lhs, rhs);
}

- (void)testPODRecordKeyComparison {
    iTermEncoderPODRecord *lhs = [iTermEncoderPODRecord withString:@"X" key:@"1"];
    iTermEncoderPODRecord *rhs = [iTermEncoderPODRecord withString:@"X" key:@"2"];
    XCTAssertNotEqualObjects(lhs, rhs);
}

- (void)testPODRecordNilComparison {
    iTermEncoderPODRecord *lhs = [iTermEncoderPODRecord withString:@"X" key:@"1"];
    XCTAssertFalse([lhs isEqual:nil]);
}

- (void)testPODRecordSelfComparison {
    iTermEncoderPODRecord *record = [iTermEncoderPODRecord withString:@"X" key:@"1"];
    XCTAssertEqualObjects(record, record);
}

- (void)testPODRecordDataRoundTrips {
    NSData *data = [NSData dataWithBytes:"abc" length:3];
    iTermEncoderPODRecord *record = [iTermEncoderPODRecord withData:data key:@"1"];
    XCTAssertEqualObjects(data, record.data);
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
                                    identifier:@""
                                         rowid:@1];

    NSDictionary<NSString *, iTermEncoderPODRecord *> *expectedRecords =
    @{ @"one": pods[0],
       @"letter": pods[1] };
    XCTAssertEqualObjects(expectedRecords, record.podRecords);
    XCTAssertEqualObjects(@[], record.graphRecords);
    XCTAssertEqual(3, record.generation);
    XCTAssertEqualObjects(@"root", record.key);
    XCTAssertEqualObjects(@"", record.identifier);
    XCTAssertEqualObjects(@1, record.rowid);
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
    @[ [iTermEncoderPODRecord withDate:[NSDate dateWithTimeIntervalSince1970:1000000000] key:@"now"],
       [iTermEncoderPODRecord withData:data key:@"data"] ];

    NSArray<iTermEncoderGraphRecord *> *graphs =
    @[
        [iTermEncoderGraphRecord withPODs:pods1 graphs:@[] generation:3 key:@"k" identifier:@"id1" rowid:@2],
        [iTermEncoderGraphRecord withPODs:pods2 graphs:@[] generation:5 key:@"k" identifier:@"id2" rowid:@3],
    ];
    iTermEncoderGraphRecord *record;
    record = [iTermEncoderGraphRecord withPODs:pods3
                                        graphs:graphs
                                    generation:7
                                           key:@"root"
                                    identifier:@""
                                         rowid:@1];

    NSDictionary<NSString *, iTermEncoderPODRecord *> *expectedPODRecords =
    @{ @"now": pods3[0],
       @"data": pods3[1] };
    XCTAssertEqualObjects(expectedPODRecords, record.podRecords);
    XCTAssertEqualObjects(graphs, record.graphRecords);
    XCTAssertEqual(7, record.generation);
    XCTAssertEqualObjects(record.key, @"root");
    XCTAssertEqualObjects(@"", record.identifier);
    XCTAssertEqualObjects(@1, record.rowid);
}

- (void)testGraphEncoder {
    iTermGraphEncoder *encoder = [[iTermGraphEncoder alloc] initWithKey:@"root"
                                                             identifier:@""
                                                             generation:1];
    [encoder encodeString:@"red" forKey:@"color"];
    [encoder encodeNumber:@1 forKey:@"count"];
    [encoder encodeData:[NSData dataWithBytes:"abc" length:3] forKey:@"blob"];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:1000000000];
    [encoder encodeDate:date forKey:@"date"];
    [encoder encodeChildWithKey:@"left" identifier:@"" generation:2 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeString:@"bob" forKey:@"name"];
        return YES;
    }];
    [encoder encodeChildWithKey:@"right" identifier:@"" generation:3 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeNumber:@23 forKey:@"age"];
        return YES;
    }];

    iTermEncoderGraphRecord *actual = encoder.record;

    NSArray *expectedPODs = @[ [iTermEncoderPODRecord withString:@"red" key:@"color"],
                               [iTermEncoderPODRecord withNumber:@1 key:@"count"],
                               [iTermEncoderPODRecord withData:[NSData dataWithBytes:"abc" length:3] key:@"blob"],
                               [iTermEncoderPODRecord withDate:date key:@"date"] ];
    iTermEncoderPODRecord *name = [iTermEncoderPODRecord withString:@"bob" key:@"name"];
    iTermEncoderPODRecord *age = [iTermEncoderPODRecord withNumber:@23 key:@"age"];
    NSArray *expectedGraphs =
    @[ [iTermEncoderGraphRecord withPODs:@[ name ] graphs:@[] generation:2 key:@"left" identifier:@"" rowid:nil],
       [iTermEncoderGraphRecord withPODs:@[ age ] graphs:@[] generation:3 key:@"right" identifier:@"" rowid:nil] ];
    iTermEncoderGraphRecord *expected = [iTermEncoderGraphRecord withPODs:expectedPODs
                                                                   graphs:expectedGraphs
                                                               generation:1
                                                                      key:@"root"
                                                               identifier:@""
                                                                    rowid:nil];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testGraphEncoderDictionary {
    iTermGraphEncoder *encoder = [[iTermGraphEncoder alloc] initWithKey:@"root"
                                                             identifier:@""
                                                             generation:1];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:1000000000];
    NSDictionary *dict = @{
        @"string": @"STRING",
        @"number": @123,
        @"data": [NSData dataWithBytes:"123" length:3],
        @"date": date,
        @"array": @[
                @"string1",
                @"string2",
                @"date",
                @{
                    @"foo": @"bar"
                },
                @[ @1, @2, @3 ],
                [NSNull null]
        ]
    };
    [encoder encodeDictionary:dict withKey:@"root" generation:1];
    iTermEncoderGraphRecord *record = encoder.record;

    NSDictionary *plist = [NSDictionary castFrom:record.propertyListValue];
    XCTAssertEqualObjects(plist[@"root"], dict);
}

- (void)testImplicitDictionaryValue {
    iTermGraphEncoder *encoder = [[iTermGraphEncoder alloc] initWithKey:@"ignored"
                                                             identifier:@""
                                                             generation:1];
    [encoder encodeString:@"string" forKey:@"key"];
    [encoder encodeChildWithKey:@"dict" identifier:@"" generation:1 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeString:@"foo" forKey:@"bar"];
        return YES;
    }];
    NSDictionary *expected = @{
        @"key": @"string",
        @"dict": @{
                @"bar": @"foo"
        }
    };
    XCTAssertEqualObjects(expected, encoder.record.propertyListValue);
}

- (void)testCompareGraphRecordUsesGeneration {
    iTermEncoderGraphRecord *lhs = [iTermEncoderGraphRecord withPODs:@[]
                                                              graphs:@[]
                                                          generation:1
                                                                 key:@""
                                                          identifier:@""
                                                               rowid:@2];
    iTermEncoderGraphRecord *rhs = [iTermEncoderGraphRecord withPODs:@[]
                                                              graphs:@[]
                                                          generation:2
                                                                 key:@""
                                                          identifier:@""
                                                               rowid:@3];
    NSComparisonResult comp = [lhs compareGraphRecord:rhs];
    XCTAssertEqual(comp, NSOrderedAscending);

    rhs = [iTermEncoderGraphRecord withPODs:@[]
                                     graphs:@[]
                                 generation:1
                                        key:@""
                                 identifier:@""
                                      rowid:@1];
    comp = [lhs compareGraphRecord:rhs];
    XCTAssertEqual(comp, NSOrderedSame);
}

- (void)testGraphRecordEquality {
    iTermEncoderGraphRecord *lhs = [iTermEncoderGraphRecord withPODs:@[]
                                                              graphs:@[]
                                                          generation:1
                                                                 key:@""
                                                          identifier:@""
                                                               rowid:@1];
    XCTAssertNotEqualObjects(lhs, (id _Nonnull)nil);
    XCTAssertEqualObjects(lhs, lhs);
    XCTAssertNotEqualObjects(lhs, @123);

    iTermEncoderGraphRecord *rhs = [iTermEncoderGraphRecord withPODs:@[]
                                                              graphs:@[]
                                                          generation:1
                                                                 key:@"x"
                                                          identifier:@""
                                                               rowid:@1];
    XCTAssertNotEqualObjects(lhs, rhs);

    iTermEncoderPODRecord *x = [iTermEncoderPODRecord withString:@"xv" key:@"xk"];
    rhs = [iTermEncoderGraphRecord withPODs:@[x]
                                     graphs:@[]
                                 generation:1
                                        key:@"x"
                                 identifier:@""
                                      rowid:@1];
    XCTAssertNotEqualObjects(lhs, rhs);

    rhs = [iTermEncoderGraphRecord withPODs:@[]
                                     graphs:@[lhs]
                                 generation:1
                                        key:@""
                                 identifier:@""
                                      rowid:@1];
    XCTAssertNotEqualObjects(lhs, rhs);

    rhs = [iTermEncoderGraphRecord withPODs:@[]
                                     graphs:@[]
                                 generation:2
                                        key:@""
                                 identifier:@""
                                      rowid:@1];
    XCTAssertNotEqualObjects(lhs, rhs);

    rhs = [iTermEncoderGraphRecord withPODs:@[]
                                     graphs:@[]
                                 generation:1
                                        key:@""
                                 identifier:@"bogus"
                                      rowid:@1];
    XCTAssertNotEqualObjects(lhs, rhs);

    rhs = [iTermEncoderGraphRecord withPODs:@[]
                                     graphs:@[]
                                 generation:1
                                        key:@"x"
                                 identifier:@""
                                      rowid:@2];
    XCTAssertNotEqualObjects(lhs, rhs);
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
        // key, identifier, parent, rowid
        @[ @"k5", @"",   @3, @5 ],
        @[ @"k4", @"i1", @2, @4 ],
        @[ @"k4", @"i2", @2, @3 ],
        @[ @"k2", @"",   @1, @2 ],
        @[ @"",   @"",   @0, @1 ],
    ];

    NSData *data = [NSData dataWithBytes:"xyz" length:3];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:1000000000];
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
        @[ @1, @"vk1", d(@"vv1"), @(iTermEncoderRecordTypeString) ],
        @[ @1, @"vk2", d(@123), @(iTermEncoderRecordTypeNumber) ],
        @[ @1, @"vk3", d(date), @(iTermEncoderRecordTypeDate) ],
        @[ @1, @"vk4", d(data), @(iTermEncoderRecordTypeData) ],
        @[ @5, @"vk5", d(@"vv2"), @(iTermEncoderRecordTypeString) ]
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
                               generation:0
                                      key:@"k5"
                               identifier:@""
                                    rowid:@5],
    ];
    NSArray<iTermEncoderGraphRecord *> *expectedK2Children = @[
        [iTermEncoderGraphRecord withPODs:@[]
                                   graphs:expectedK4Children
                               generation:0
                                      key:@"k4"
                               identifier:@"i2"
                                    rowid:@3],
        [iTermEncoderGraphRecord withPODs:@[]
                                   graphs:@[]
                               generation:0
                                      key:@"k4"
                               identifier:@"i1"
                                    rowid:@4],
    ];
    NSArray<iTermEncoderGraphRecord *> *expectedRootGraphs = @[
        [iTermEncoderGraphRecord withPODs:@[]
                                   graphs:expectedK2Children
                               generation:0
                                      key:@"k2"
                               identifier:@""
                                    rowid:@2],

    ];
    iTermEncoderGraphRecord *expected =
    [iTermEncoderGraphRecord withPODs:expectedRootPODs
                               graphs:expectedRootGraphs
                           generation:0
                                  key:@""
                           identifier:@""
                                rowid:@1];

    iTermEncoderGraphRecord *actual = transformer.root;
    XCTAssertEqualObjects(expected, actual);
}

- (void)testGraphTableTransformer_MissingFieldInNodeRow {
    NSArray *nodes = @[
        // key, identifier, parent, generation
        @[ @"",   @"" ],
    ];
    NSArray *values = @[];

    iTermGraphTableTransformer *transformer =
    [[iTermGraphTableTransformer alloc] initWithNodeRows:nodes
                                               valueRows:values];

    iTermEncoderGraphRecord *record = transformer.root;
    XCTAssertNil(record);
}

- (void)testGraphTableTransformer_MistypedFieldInNodeRow {
    NSArray *nodes = @[
        // key, identifier, parent
        @[ @"",   @666,   @"" ],
    ];
    NSArray *values = @[];

    iTermGraphTableTransformer *transformer =
    [[iTermGraphTableTransformer alloc] initWithNodeRows:nodes
                                               valueRows:values];

    iTermEncoderGraphRecord *record = transformer.root;
    XCTAssertNil(record);
}

- (void)testGraphTableTransformer_TwoRoots {
    NSArray *nodes = @[
        // key, identifier, parent
        @[ @"",   @"",   @"" ],
        @[ @"",   @"",   @"" ],
    ];
    NSArray *values = @[];

    iTermGraphTableTransformer *transformer =
    [[iTermGraphTableTransformer alloc] initWithNodeRows:nodes
                                               valueRows:values];

    iTermEncoderGraphRecord *record = transformer.root;
    XCTAssertNil(record);
}

- (void)testGraphTableTransformer_ChildWithBadParent {
    NSArray *nodes = @[
        // key, identifier, parent, generation
        @[ @"",   @"",   @"" ],
        @[ @"child",   @"",   @"bogus" ],
    ];
    NSArray *values = @[];

    iTermGraphTableTransformer *transformer =
    [[iTermGraphTableTransformer alloc] initWithNodeRows:nodes
                                               valueRows:values];

    iTermEncoderGraphRecord *record = transformer.root;
    XCTAssertNil(record);
}

- (void)testGraphTableTransformer_MissingFieldInValueRow {
    NSArray *nodes = @[
        // key, identifier, parent, generation
        @[ @"",   @"",   @"" ],
    ];
    NSArray *values = @[
        @[ /* no key */ @"vk4", [NSData dataWithBytes:"123" length:3], @(iTermEncoderRecordTypeData) ]
    ];

    iTermGraphTableTransformer *transformer =
    [[iTermGraphTableTransformer alloc] initWithNodeRows:nodes
                                               valueRows:values];

    iTermEncoderGraphRecord *record = transformer.root;
    XCTAssertNil(record);
}

- (void)testGraphTableTransformer_MistypedFieldInValueRow {
    NSArray *nodes = @[
        // key, identifier, parent, generation
        @[ @"",   @"",   @"" ],
    ];
    NSArray *values = @[
        @[ @666, @"vk4", [NSData dataWithBytes:"123" length:3], @(iTermEncoderRecordTypeData) ]
    ];

    iTermGraphTableTransformer *transformer =
    [[iTermGraphTableTransformer alloc] initWithNodeRows:nodes
                                               valueRows:values];

    iTermEncoderGraphRecord *record = transformer.root;
    XCTAssertNil(record);
}

- (void)testGraphTableTransformer_CorruptTypeFieldInValueRow {
    NSArray *nodes = @[
        // key, identifier, parent, generation
        @[ @"",   @"",   @"" ],
    ];
    NSArray *values = @[
        @[ @"", @"vk4", [NSData dataWithBytes:"123" length:3], @99 ]
    ];

    iTermGraphTableTransformer *transformer =
    [[iTermGraphTableTransformer alloc] initWithNodeRows:nodes
                                               valueRows:values];

    iTermEncoderGraphRecord *record = transformer.root;
    XCTAssertNil(record);
}

- (void)testGraphTableTransformer_ReferenceToBogusNodeInValueRow {
    NSArray *nodes = @[
        // key, identifier, parent, generation
        @[ @"",   @"",   @"" ],
    ];
    NSArray *values = @[
        @[ @"bogus", @"vk4", [NSData dataWithBytes:"123" length:3], @(iTermEncoderRecordTypeData) ]
    ];

    iTermGraphTableTransformer *transformer =
    [[iTermGraphTableTransformer alloc] initWithNodeRows:nodes
                                               valueRows:values];

    iTermEncoderGraphRecord *record = transformer.root;
    XCTAssertNil(record);
}

- (void)testDeltaEncoder_UpdateValue {
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:nil];
    [encoder encodeChildWithKey:@"root" identifier:@"" generation:1 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
        return [subencoder encodeChildWithKey:@"leaf" identifier:@"" generation:1 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"value1" forKey:@"key"];
            return YES;
        }];
    }];
    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeChildWithKey:@"root" identifier:@"" generation:2 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
        return [subencoder encodeChildWithKey:@"leaf" identifier:@"" generation:2 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"value2" forKey:@"key"];
            return YES;
        }];
    }];
    __block BOOL done = NO;
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSNumber *rowid) {
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
    [encoder encodeChildWithKey:@"root" identifier:@"" generation:1 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
        return [subencoder encodeChildWithKey:@"leaf" identifier:@"" generation:1 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"value1" forKey:@"key"];
            return YES;
        }];
    }];
    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeChildWithKey:@"root" identifier:@"" generation:2 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
        return [subencoder encodeChildWithKey:@"leaf" identifier:@"" generation:2 block:^(iTermGraphEncoder * _Nonnull subencoder) {
            return YES;
        }];
    }];
    __block BOOL done = NO;
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSNumber *parent) {
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
    [encoder encodeChildWithKey:@"root" identifier:@"" generation:1 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
        return [subencoder encodeChildWithKey:@"leaf" identifier:@"" generation:1 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
            return YES;
        }];
    }];
    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeChildWithKey:@"root" identifier:@"" generation:2 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
        return [subencoder encodeChildWithKey:@"leaf" identifier:@"" generation:2 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"value1" forKey:@"key"];
            return YES;
        }];
    }];
    __block BOOL done = NO;
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSNumber *rowid) {
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
    [encoder encodeChildWithKey:@"root" identifier:@"" generation:1 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
        return [subencoder encodeChildWithKey:@"leaf" identifier:@"" generation:1 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"value1" forKey:@"key"];
            return YES;
        }];
    }];
    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeChildWithKey:@"root" identifier:@"" generation:2 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
        return YES;
    }];
    __block BOOL done = NO;
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSNumber *rowid) {
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
    [encoder encodeChildWithKey:@"root" identifier:@"" generation:1 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
        return YES;
    }];
    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeChildWithKey:@"root" identifier:@"" generation:2 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
        return [subencoder encodeChildWithKey:@"leaf" identifier:@"" generation:1 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"value1" forKey:@"key"];
            return YES;
        }];
    }];
    __block BOOL done = NO;
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSNumber *rowid) {
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
                        options:0
                          block:^BOOL (NSString * _Nonnull identifier,
                                       NSInteger index,
                                       iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeString:[NSString stringWithFormat:@"value1_%@_%@", identifier, @(index)]
                          forKey:@"k"];
        return YES;
    }];

    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeArrayWithKey:@"a"
                     generation:1
                    identifiers:@[ @"i1", @"i2", @"i3" ]
                          options:0
                          block:^BOOL (NSString * _Nonnull identifier, NSInteger index, iTermGraphEncoder * _Nonnull subencoder) {
        XCTFail(@"Should not have been called because generation didn't change");
        return YES;
    }];
}

// root (0)
//   __array[a] (1)
//     [i1 k_i1=value1_i1_0] (2)
//     [i2 k_i2=value1_i2_1] (3)
//     [i2 k_i2=value1_i3_1] (3)
- (void)testDeltaEncoderArray_ModifyValues {
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:nil];
    [encoder encodeArrayWithKey:@"a"
                     generation:1
                    identifiers:@[ @"i1", @"i2", @"i3" ]
                          options:0
                          block:^BOOL (NSString * _Nonnull identifier,
                                       NSInteger index,
                                       iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeString:[NSString stringWithFormat:@"value1_%@_%@", identifier, @(index)]
                          forKey:[NSString stringWithFormat:@"k_%@", identifier]];
        return YES;
    }];
    {
        NSArray<NSString *> *actual = [self pseudoSQLFromEncoder:encoder];
        NSArray<NSString *> *expected = @[
            @"insert node key=, identifier=, parent=0 -> 1",  // root
            @"insert node key=__array, identifier=a, parent=1 -> 2",
            @"insert value key=__order, value=i1\ti2\ti3, node=2, type=0",
            @"insert node key=, identifier=i1, parent=2 -> 3",
            @"insert value key=k_i1, value=value1_i1_0, node=3, type=0",
            @"insert node key=, identifier=i2, parent=2 -> 4",
            @"insert value key=k_i2, value=value1_i2_1, node=4, type=0",
            @"insert node key=, identifier=i3, parent=2 -> 5",
            @"insert value key=k_i3, value=value1_i3_2, node=5, type=0",
        ];
        XCTAssertEqualObjects(actual, expected);
    }

    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeArrayWithKey:@"a"
                     generation:2
                    identifiers:@[ @"i1", @"i2", @"i3" ]
                          options:0
                          block:^BOOL (NSString * _Nonnull identifier, NSInteger index, iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeString:[NSString stringWithFormat:@"value2_%@_%@", identifier, @(index)]
                          forKey:[NSString stringWithFormat:@"k_%@", identifier]];
        return YES;
    }];

    {
        NSArray<NSString *> *actual = [self pseudoSQLFromEncoder:encoder];
        NSArray<NSString *> *expected = @[
            @"update value where key=k_i1 and node=3 set value=value2_i1_0",
            @"update value where key=k_i2 and node=4 set value=value2_i2_1",
            @"update value where key=k_i3 and node=5 set value=value2_i3_2",
        ];
        XCTAssertEqualObjects(actual, expected);
    }
}

- (void)testDeltaEncoderArray_DeleteFirstValue {
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:nil];
    [encoder encodeArrayWithKey:@"a"
                     generation:1
                    identifiers:@[ @"i1", @"i2", @"i3" ]
                          options:0
                          block:^BOOL (NSString * _Nonnull identifier,
                                       NSInteger index,
                                       iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeString:[NSString stringWithFormat:@"value1_%@_%@", identifier, @(index)]
                          forKey:[NSString stringWithFormat:@"k_%@", identifier]];
        return YES;
    }];
    {
        NSArray<NSString *> *actual = [self pseudoSQLFromEncoder:encoder];
        NSArray<NSString *> *expected = @[
            @"insert node key=, identifier=, parent=0 -> 1",  // root
            @"insert node key=__array, identifier=a, parent=1 -> 2",
            @"insert value key=__order, value=i1\ti2\ti3, node=2, type=0",
            @"insert node key=, identifier=i1, parent=2 -> 3",
            @"insert value key=k_i1, value=value1_i1_0, node=3, type=0",
            @"insert node key=, identifier=i2, parent=2 -> 4",
            @"insert value key=k_i2, value=value1_i2_1, node=4, type=0",
            @"insert node key=, identifier=i3, parent=2 -> 5",
            @"insert value key=k_i3, value=value1_i3_2, node=5, type=0",
        ];
        XCTAssertEqualObjects(actual, expected);
    }

    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeArrayWithKey:@"a"
                     generation:2
                    identifiers:@[ @"i2", @"i3" ]
                          options:0
                          block:^BOOL (NSString * _Nonnull identifier, NSInteger index, iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeString:[NSString stringWithFormat:@"value2_%@_%@", identifier, @(index)]
                          forKey:[NSString stringWithFormat:@"k_%@", identifier]];
        return YES;
    }];

    {
        NSArray<NSString *> *actual = [self pseudoSQLFromEncoder:encoder];
        NSArray<NSString *> *expected = @[
            @"update value where key=__order and node=2 set value=i2\ti3",
            @"delete node where rowid=3",
            @"delete value where node=3",
            @"update value where key=k_i2 and node=4 set value=value2_i2_0",
            @"update value where key=k_i3 and node=5 set value=value2_i3_1",
        ];
        XCTAssertEqualObjects(actual, expected);
    }
}

- (void)testDeltaEncoderArray_Append {
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:nil];
    [encoder encodeArrayWithKey:@"a"
                     generation:1
                    identifiers:@[ @"i1", @"i2", @"i3" ]
                          options:0
                          block:^BOOL (NSString * _Nonnull identifier,
                                       NSInteger index,
                                       iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeString:[NSString stringWithFormat:@"value1_%@_%@", identifier, @(index)]
                          forKey:[NSString stringWithFormat:@"k_%@", identifier]];
        return YES;
    }];
    {
        NSArray<NSString *> *actual = [self pseudoSQLFromEncoder:encoder];
        NSArray<NSString *> *expected = @[
            @"insert node key=, identifier=, parent=0 -> 1",  // root
            @"insert node key=__array, identifier=a, parent=1 -> 2",
            @"insert value key=__order, value=i1\ti2\ti3, node=2, type=0",
            @"insert node key=, identifier=i1, parent=2 -> 3",
            @"insert value key=k_i1, value=value1_i1_0, node=3, type=0",
            @"insert node key=, identifier=i2, parent=2 -> 4",
            @"insert value key=k_i2, value=value1_i2_1, node=4, type=0",
            @"insert node key=, identifier=i3, parent=2 -> 5",
            @"insert value key=k_i3, value=value1_i3_2, node=5, type=0",
        ];
        XCTAssertEqualObjects(actual, expected);
    }

    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeArrayWithKey:@"a"
                     generation:2
                    identifiers:@[ @"i1", @"i2", @"i3", @"i4" ]
                          options:0
                          block:^BOOL (NSString * _Nonnull identifier, NSInteger index, iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeString:[NSString stringWithFormat:@"value1_%@_%@", identifier, @(index)]
                          forKey:[NSString stringWithFormat:@"k_%@", identifier]];
        return YES;
    }];

    {
        NSArray<NSString *> *actual = [self pseudoSQLFromEncoder:encoder];
        NSArray<NSString *> *expected = @[
            @"update value where key=__order and node=2 set value=i1\ti2\ti3\ti4",
            @"insert node key=, identifier=i4, parent=2 -> 6",
            @"insert value key=k_i4, value=value1_i4_3, node=6, type=0",
        ];
        XCTAssertEqualObjects(actual, expected);
    }
}

- (NSArray<NSString *> *)pseudoSQLFromEncoder:(iTermGraphDeltaEncoder *)encoder {
    NSMutableArray<NSString *> *statements = [NSMutableArray array];
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSNumber *parentRowID) {
        if (before && !after) {
            [statements addObject:[NSString stringWithFormat:@"delete node where rowid=%@", before.rowid]];
            [before enumerateValuesVersus:nil block:^(iTermEncoderPODRecord * _Nullable mine,
                                                      iTermEncoderPODRecord * _Nullable theirs) {
                [statements addObject:[NSString stringWithFormat:@"delete value where node=%@", before.rowid]];
            }];
        } else if (!before && after) {
            after.rowid = @(++_rowid);
            [statements addObject:[NSString stringWithFormat:@"insert node key=%@, identifier=%@, parent=%@ -> %@",
                                   after.key, after.identifier, parentRowID ?: @0, after.rowid]];
            [after enumerateValuesVersus:nil block:^(iTermEncoderPODRecord * _Nullable record,
                                                     iTermEncoderPODRecord * _Nullable na) {
                [statements addObject:[NSString stringWithFormat:@"insert value key=%@, value=%@, node=%@, type=%@",
                                       record.key, record.value, after.rowid, @(record.type)]];
            }];
        } else if (before && after) {
            [before enumerateValuesVersus:after block:^(iTermEncoderPODRecord * _Nullable mine,
                                                        iTermEncoderPODRecord * _Nullable theirs) {
                if (mine && theirs) {
                    if (![mine isEqual:theirs]) {
                        assert(before.rowid);
                        [statements addObject:[NSString stringWithFormat:@"update value where key=%@ and node=%@ set value=%@",
                                               mine.key, before.rowid, theirs.value]];
                    }
                } else if (!mine && theirs) {
                    [statements addObject:[NSString stringWithFormat:@"insert value key=%@, value=%@, type=%@, node=%@",
                                           theirs.key, theirs.value, @(theirs.type), before.rowid]];
                } else if (mine && !theirs) {
                    [statements addObject:[NSString stringWithFormat:@"delete value where key=%@, node=%@",
                                           mine.key, before.rowid]];
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
    [encoder encodeChildWithKey:@"k2" identifier:@"" generation:1 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
        [subencoder encodeString:@"k3_v1" forKey:@"k3"];

        [subencoder encodeChildWithKey:@"k4" identifier:@"" generation:1 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"k5_v1" forKey:@"k5"];
            return YES;
        }];
        [subencoder encodeChildWithKey:@"k6" identifier:@"i1" generation:1 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"k7_v1" forKey:@"k7"];
            return YES;
        }];
        [subencoder encodeChildWithKey:@"k6" identifier:@"i2" generation:1 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"k9_v1" forKey:@"k9"];
            [subencoder encodeString:@"k9a_v1" forKey:@"k9a"];
            return YES;
        }];
        [subencoder encodeChildWithKey:@"k6" identifier:@"i3" generation:1 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"k10_v1" forKey:@"k10"];
            return YES;
        }];
        return YES;
    }];

    // This has the side-effect of assigning row IDs to the records so the next batch of SQL will
    // be correct.
    NSArray<NSString *> *actual = [self pseudoSQLFromEncoder:encoder];
    NSArray<NSString *> *expected = @[
        @"insert node key=, identifier=, parent=0 -> 1",
        @"insert value key=k1, value=k1_v1, node=1, type=0",
        @"insert node key=k2, identifier=, parent=1 -> 2",
        @"insert value key=k3, value=k3_v1, node=2, type=0",
        @"insert node key=k4, identifier=, parent=2 -> 3",
        @"insert value key=k5, value=k5_v1, node=3, type=0",
        @"insert node key=k6, identifier=i1, parent=2 -> 4",
        @"insert value key=k7, value=k7_v1, node=4, type=0",
        @"insert node key=k6, identifier=i2, parent=2 -> 5",
        @"insert value key=k9, value=k9_v1, node=5, type=0",
        @"insert value key=k9a, value=k9a_v1, node=5, type=0",
        @"insert node key=k6, identifier=i3, parent=2 -> 6",
        @"insert value key=k10, value=k10_v1, node=6, type=0",
    ];
    XCTAssertEqualObjects(actual, expected);

    /*
       [root k1=k1_v1->k1_v2]
         [k2 k3=k3_v1->(unset)]
           [k4 k5=k5v1]
           del k6[i1]
           [k6[i2] k9=k9_v1->k9_v2 k9a=k9a_v1 k9b=(unset)->k9b_v1]
           [k6[i3] k10=k10_v1]
           add [k6[i4] k11=k11_v1]
     */
    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeString:@"k1_v2" forKey:@"k1"];
    [encoder encodeChildWithKey:@"k2" identifier:@"" generation:2 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
        // Omit k3
        [subencoder encodeChildWithKey:@"k4" identifier:@"" generation:1 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
            XCTFail(@"Shouldn't reach this because generation is unchanged.");
            return YES;
        }];
        // omit k6.i1
        [subencoder encodeChildWithKey:@"k6" identifier:@"i2" generation:2 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"k9_v2" forKey:@"k9"];
            [subencoder encodeString:@"k9a_v1" forKey:@"k9a"];
            [subencoder encodeString:@"k9b_v1" forKey:@"k9b"];
            return YES;
        }];
        [subencoder encodeChildWithKey:@"k6" identifier:@"i3" generation:1 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
            XCTFail(@"Shouldn't reach this because generation is unchanged.");
            return YES;
        }];
        [subencoder encodeChildWithKey:@"k6" identifier:@"i4" generation:1 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"k11_v1" forKey:@"k11"];
            return YES;
        }];
        return YES;
    }];

    actual = [self pseudoSQLFromEncoder:encoder];
    expected = @[
        @"update value where key=k1 and node=1 set value=k1_v2",
        @"delete value where key=k3, node=2",
        @"delete node where rowid=4",
        @"delete value where node=4",
        @"update value where key=k9 and node=5 set value=k9_v2",
        @"insert value key=k9b, value=k9b_v1, type=0, node=5",
        @"insert node key=k6, identifier=i4, parent=2 -> 7",
        @"insert value key=k11, value=k11_v1, node=7, type=0"
    ];
    XCTAssertEqualObjects(actual, expected);
}

- (iTermGraphDatabase *)graphDatabaseAfterInitialAdd {
    NSMutableDictionary<NSString *,id<iTermDatabaseResultSet>> *results = [NSMutableDictionary dictionary];
    results[@"select key, identifier, parent, rowid from Node"] = [iTermMockDatabaseResultSet withRows:@[]];
    results[@"select * from Value"] = [iTermMockDatabaseResultSet withRows:@[]];

    iTermMockDatabaseFactory *mockDB = [[iTermMockDatabaseFactory alloc] initWithResults:results
                                                                                database:nil];
    iTermGraphDatabase *gdb = [[iTermGraphDatabase alloc] initWithURL:[NSURL fileURLWithPath:@"/db"]
                                                      databaseFactory:mockDB];
    XCTAssertNotNil(gdb);
    iTermMockDatabase *db = mockDB.database;
    XCTAssertNotNil(db);

    XCTAssertNil(gdb.record);
    [gdb.thread performDeferredBlocksAfter:^{
        [gdb update:^(iTermGraphEncoder * _Nonnull encoder) {
            [encoder encodeChildWithKey:@"mynode" identifier:@"" generation:1 block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
                [subencoder encodeString:@"red" forKey:@"color"];
                [subencoder encodeNumber:@123 forKey:@"number"];
                return YES;
            }];
        }
         completion:nil];
    }];
    return gdb;
}

- (void)testGraphDatabase_InitialAdd {
    iTermGraphDatabase *gdb = [self graphDatabaseAfterInitialAdd];
    iTermMockDatabase *db = (iTermMockDatabase *)gdb.db;

    NSArray<NSString *> *expectedCommands = @[
        @"create table if not exists Node (key text, identifier text, parent integer)",
        @"create table if not exists Value (key text, node integer, value blob, type integer)",
        @"insert into Node (key, identifier, parent) values (, , 0)",
        @"insert into Node (key, identifier, parent) values (mynode, , 1)",
        @"insert into Value (key, value, node, type) values (color, red, 2, 0)",
        @"insert into Value (key, value, node, type) values (number, 123, 2, 1)",
    ];
    XCTAssertEqualObjects(db.commands, expectedCommands);
}

- (void)testGraphDatabase_Load {
    NSMutableDictionary<NSString *,id<iTermDatabaseResultSet>> *results = [NSMutableDictionary dictionary];
    results[@"select key, identifier, parent, rowid from Node"] = [iTermMockDatabaseResultSet withRows:@[
        @{ @"key": @"",
           @"identifier": @"",
           @"parent": @0,
           @"rowid": @1
        },

        @{ @"key": @"mynode",
           @"identifier": @"",
           @"parent": @1,
           @"rowid": @2
        },
    ]];
    const double d = 123;
    results[@"select * from Value"] = [iTermMockDatabaseResultSet withRows:@[
        @{ @"key": @"color",
           @"value": [@"red" dataUsingEncoding:NSUTF8StringEncoding],
           @"node": @2,
           @"type": @0 },

        @{ @"key": @"number",
           @"value": [NSData dataWithBytes:&d length:sizeof(d)],
           @"node": @2,
           @"type": @1 },
    ]];

    iTermMockDatabaseFactory *mockDB = [[iTermMockDatabaseFactory alloc] initWithResults:results
                                                                                database:nil];
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
                               generation:0
                                      key:@"mynode"
                               identifier:@""
                                    rowid:@2];
    iTermEncoderGraphRecord *expectedRecord =
    [iTermEncoderGraphRecord withPODs:@[]
                               graphs:@[ mynode ]
                           generation:0
                                  key:@""
                           identifier:@""
                                rowid:@1];

    XCTAssertEqualObjects(gdb.record, expectedRecord);
}

- (void)testGraphDatabaseCannotOpen {
    NSURL *url = [NSURL fileURLWithPath:@"/db"];
    iTermMockDatabase *db = [[iTermMockDatabase alloc] initWithURL:url
                                                           results:[NSMutableDictionary dictionary]];
    iTermMockDatabaseFactory *mockDB = [[iTermMockDatabaseFactory alloc] initWithResults:[NSMutableDictionary dictionary]
                                                                                database:db];
    db.shouldOpen = NO;
    iTermGraphDatabase *gdb = [[iTermGraphDatabase alloc] initWithURL:[NSURL fileURLWithPath:@"/db"]
                                                      databaseFactory:mockDB];
    XCTAssertNil(gdb);
}

- (void)testGraphDatabase_DeleteNode {
    NSMutableDictionary<NSString *,id<iTermDatabaseResultSet>> *results = [NSMutableDictionary dictionary];
    results[@"select key, identifier, parent, rowid from Node"] = [iTermMockDatabaseResultSet withRows:@[]];
    results[@"select * from Value"] = [iTermMockDatabaseResultSet withRows:@[]];

    iTermMockDatabaseFactory *mockDB = [[iTermMockDatabaseFactory alloc] initWithResults:results
                                                                                database:nil];
    iTermGraphDatabase *gdb = [[iTermGraphDatabase alloc] initWithURL:[NSURL fileURLWithPath:@"/db"]
                                                      databaseFactory:mockDB];
    iTermMockDatabase *db = mockDB.database;

    XCTAssertNil(gdb.record);
    [gdb.thread performDeferredBlocksAfter:^{
        [gdb update:^(iTermGraphEncoder * _Nonnull encoder) {
            [encoder encodeChildWithKey:@"wrapper"
                             identifier:@""
                             generation:1
                                  block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
                return [subencoder encodeChildWithKey:@"mynode"
                                    identifier:@""
                                    generation:1
                                         block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
                    [subencoder encodeString:@"Hello" forKey:@"World"];
                    return YES;
                }];
            }];
        }
         completion:nil];
    }];
    NSArray<NSString *> *expectedCommands = @[
        @"create table if not exists Node (key text, identifier text, parent integer)",
        @"create table if not exists Value (key text, node integer, value blob, type integer)",
        @"insert into Node (key, identifier, parent) values (, , 0)",
        @"insert into Node (key, identifier, parent) values (wrapper, , 1)",
        @"insert into Node (key, identifier, parent) values (mynode, , 2)",
        @"insert into Value (key, value, node, type) values (World, Hello, 3, 0)",
    ];
    XCTAssertEqualObjects(db.commands, expectedCommands);
    [db.commands removeAllObjects];

    [gdb.thread performDeferredBlocksAfter:^{
        [gdb update:^(iTermGraphEncoder * _Nonnull encoder) {
            [encoder encodeChildWithKey:@"wrapper"
                             identifier:@""
                             generation:2
                                  block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
                return YES;
            }];
        }
         completion:nil];
    }];

    expectedCommands = @[
        @"delete from Node where rowid=3",
        @"delete from Value where node=3"
    ];
    XCTAssertEqualObjects(db.commands, expectedCommands);
}

- (void)testGraphDatabase_InsertNode {
    NSMutableDictionary<NSString *,id<iTermDatabaseResultSet>> *results = [NSMutableDictionary dictionary];
    results[@"select key, identifier, parent, rowid from Node"] = [iTermMockDatabaseResultSet withRows:@[]];
    results[@"select * from Value"] = [iTermMockDatabaseResultSet withRows:@[]];

    iTermMockDatabaseFactory *mockDB = [[iTermMockDatabaseFactory alloc] initWithResults:results
                                                                                database:nil];
    iTermGraphDatabase *gdb = [[iTermGraphDatabase alloc] initWithURL:[NSURL fileURLWithPath:@"/db"]
                                                      databaseFactory:mockDB];
    iTermMockDatabase *db = mockDB.database;

    XCTAssertNil(gdb.record);
    [gdb.thread performDeferredBlocksAfter:^{
        [gdb update:^(iTermGraphEncoder * _Nonnull encoder) {
            [encoder encodeChildWithKey:@"wrapper"
                             identifier:@""
                             generation:1
                                  block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
                return [subencoder encodeChildWithKey:@"mynode"
                                    identifier:@""
                                    generation:1
                                         block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
                    [subencoder encodeString:@"Hello" forKey:@"World"];
                    return YES;
                }];
            }];
        }
         completion:nil];
    }];
    NSArray<NSString *> *expectedCommands = @[
        @"create table if not exists Node (key text, identifier text, parent integer)",
        @"create table if not exists Value (key text, node integer, value blob, type integer)",
        @"insert into Node (key, identifier, parent) values (, , 0)",
        @"insert into Node (key, identifier, parent) values (wrapper, , 1)",
        @"insert into Node (key, identifier, parent) values (mynode, , 2)",
        @"insert into Value (key, value, node, type) values (World, Hello, 3, 0)",
    ];
    XCTAssertEqualObjects(db.commands, expectedCommands);
    [db.commands removeAllObjects];

    [gdb.thread performDeferredBlocksAfter:^{
        [gdb update:^(iTermGraphEncoder * _Nonnull encoder) {
            [encoder encodeChildWithKey:@"wrapper"
                             identifier:@""
                             generation:2
                                  block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
                [subencoder encodeChildWithKey:@"mynode"
                                    identifier:@""
                                    generation:1
                                         block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
                    [subencoder encodeString:@"Hello" forKey:@"World"];
                    return YES;
                }];
                return [subencoder encodeChildWithKey:@"othernode"
                                    identifier:@""
                                    generation:1
                                         block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
                    [subencoder encodeString:@"Goodbye" forKey:@"Everybody"];
                    return YES;
                }];
            }];
        }
         completion:nil];
    }];

    expectedCommands = @[
        @"insert into Node (key, identifier, parent) values (othernode, , 2)",
        @"insert into Value (key, value, node, type) values (Everybody, Goodbye, 5, 0)"
    ];
    XCTAssertEqualObjects(db.commands, expectedCommands);
}

- (void)testGraphDatabase_UpdateValue {
    NSMutableDictionary<NSString *,id<iTermDatabaseResultSet>> *results = [NSMutableDictionary dictionary];
    results[@"select key, identifier, parent, rowid from Node"] = [iTermMockDatabaseResultSet withRows:@[]];
    results[@"select * from Value"] = [iTermMockDatabaseResultSet withRows:@[]];

    iTermMockDatabaseFactory *mockDB = [[iTermMockDatabaseFactory alloc] initWithResults:results
                                                                                database:nil];
    iTermGraphDatabase *gdb = [[iTermGraphDatabase alloc] initWithURL:[NSURL fileURLWithPath:@"/db"]
                                                      databaseFactory:mockDB];
    iTermMockDatabase *db = mockDB.database;

    XCTAssertNil(gdb.record);
    [gdb.thread performDeferredBlocksAfter:^{
        [gdb update:^(iTermGraphEncoder * _Nonnull encoder) {
            [encoder encodeChildWithKey:@"wrapper"
                             identifier:@""
                             generation:1
                                  block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
                return [subencoder encodeChildWithKey:@"mynode"
                                    identifier:@""
                                    generation:1
                                         block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
                    [subencoder encodeString:@"Hello" forKey:@"World"];
                    return YES;
                }];
            }];
        }
         completion:nil];
    }];
    NSArray<NSString *> *expectedCommands = @[
        @"create table if not exists Node (key text, identifier text, parent integer)",
        @"create table if not exists Value (key text, node integer, value blob, type integer)",
        @"insert into Node (key, identifier, parent) values (, , 0)",
        @"insert into Node (key, identifier, parent) values (wrapper, , 1)",
        @"insert into Node (key, identifier, parent) values (mynode, , 2)",
        @"insert into Value (key, value, node, type) values (World, Hello, 3, 0)",
    ];
    XCTAssertEqualObjects(db.commands, expectedCommands);
    [db.commands removeAllObjects];

    [gdb.thread performDeferredBlocksAfter:^{
        [gdb update:^(iTermGraphEncoder * _Nonnull encoder) {
            [encoder encodeChildWithKey:@"wrapper"
                             identifier:@""
                             generation:2
                                  block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
                return [subencoder encodeChildWithKey:@"mynode"
                                           identifier:@""
                                           generation:2
                                                block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
                    [subencoder encodeString:@"Goodbye" forKey:@"World"];
                    return YES;
                }];
            }];
        }
         completion:nil];
    }];

    expectedCommands = @[
        @"update Value set value=Goodbye, type=0 where key=World and node=3"
    ];
    XCTAssertEqualObjects(db.commands, expectedCommands);
}

- (void)testGraphDatabase_InsertValue {
    NSMutableDictionary<NSString *,id<iTermDatabaseResultSet>> *results = [NSMutableDictionary dictionary];
    results[@"select key, identifier, parent, rowid from Node"] = [iTermMockDatabaseResultSet withRows:@[]];
    results[@"select * from Value"] = [iTermMockDatabaseResultSet withRows:@[]];

    iTermMockDatabaseFactory *mockDB = [[iTermMockDatabaseFactory alloc] initWithResults:results
                                                                                database:nil];
    iTermGraphDatabase *gdb = [[iTermGraphDatabase alloc] initWithURL:[NSURL fileURLWithPath:@"/db"]
                                                      databaseFactory:mockDB];
    iTermMockDatabase *db = mockDB.database;

    XCTAssertNil(gdb.record);
    [gdb.thread performDeferredBlocksAfter:^{
        [gdb update:^(iTermGraphEncoder * _Nonnull encoder) {
            [encoder encodeChildWithKey:@"wrapper"
                             identifier:@""
                             generation:1
                                  block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
                return [subencoder encodeChildWithKey:@"mynode"
                                    identifier:@""
                                    generation:1
                                         block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
                    [subencoder encodeString:@"Hello" forKey:@"World"];
                    return YES;
                }];
            }];
        }
         completion:nil];
    }];
    NSArray<NSString *> *expectedCommands = @[
        @"create table if not exists Node (key text, identifier text, parent integer)",
        @"create table if not exists Value (key text, node integer, value blob, type integer)",
        @"insert into Node (key, identifier, parent) values (, , 0)",
        @"insert into Node (key, identifier, parent) values (wrapper, , 1)",
        @"insert into Node (key, identifier, parent) values (mynode, , 2)",
        @"insert into Value (key, value, node, type) values (World, Hello, 3, 0)",
    ];
    XCTAssertEqualObjects(db.commands, expectedCommands);
    [db.commands removeAllObjects];

    [gdb.thread performDeferredBlocksAfter:^{
        [gdb update:^(iTermGraphEncoder * _Nonnull encoder) {
            [encoder encodeChildWithKey:@"wrapper"
                             identifier:@""
                             generation:2
                                  block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
                return [subencoder encodeChildWithKey:@"mynode"
                                    identifier:@""
                                    generation:2
                                         block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
                    [subencoder encodeString:@"Hello" forKey:@"World"];
                    [subencoder encodeString:@"Goodbye" forKey:@"Everybody"];
                    return YES;
                }];
            }];
        }
         completion:nil];
    }];

    expectedCommands = @[
        @"insert into Value (key, value, node, type) values (Everybody, Goodbye, 3, 0)"
    ];
    XCTAssertEqualObjects(db.commands, expectedCommands);
}

- (void)testGraphDatabase_DeleteValue {
    NSMutableDictionary<NSString *,id<iTermDatabaseResultSet>> *results = [NSMutableDictionary dictionary];
    results[@"select key, identifier, parent, rowid from Node"] = [iTermMockDatabaseResultSet withRows:@[]];
    results[@"select * from Value"] = [iTermMockDatabaseResultSet withRows:@[]];

    iTermMockDatabaseFactory *mockDB = [[iTermMockDatabaseFactory alloc] initWithResults:results
                                                                                database:nil];
    iTermGraphDatabase *gdb = [[iTermGraphDatabase alloc] initWithURL:[NSURL fileURLWithPath:@"/db"]
                                                      databaseFactory:mockDB];
    iTermMockDatabase *db = mockDB.database;

    XCTAssertNil(gdb.record);
    [gdb.thread performDeferredBlocksAfter:^{
        [gdb update:^(iTermGraphEncoder * _Nonnull encoder) {
            [encoder encodeChildWithKey:@"wrapper"
                             identifier:@""
                             generation:1
                                  block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
                return [subencoder encodeChildWithKey:@"mynode"
                                           identifier:@""
                                           generation:1
                                                block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
                    [subencoder encodeString:@"Hello" forKey:@"World"];
                    return YES;
                }];
            }];
        }
         completion:nil];
    }];
    NSArray<NSString *> *expectedCommands = @[
        @"create table if not exists Node (key text, identifier text, parent integer)",
        @"create table if not exists Value (key text, node integer, value blob, type integer)",
        @"insert into Node (key, identifier, parent) values (, , 0)",
        @"insert into Node (key, identifier, parent) values (wrapper, , 1)",
        @"insert into Node (key, identifier, parent) values (mynode, , 2)",
        @"insert into Value (key, value, node, type) values (World, Hello, 3, 0)",
    ];
    XCTAssertEqualObjects(db.commands, expectedCommands);
    [db.commands removeAllObjects];

    [gdb.thread performDeferredBlocksAfter:^{
        [gdb update:^(iTermGraphEncoder * _Nonnull encoder) {
            [encoder encodeChildWithKey:@"wrapper"
                             identifier:@""
                             generation:2
                                  block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
                return [subencoder encodeChildWithKey:@"mynode"
                                    identifier:@""
                                    generation:2
                                         block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
                    return YES;
                }];
            }];
        }
         completion:nil];
    }];

    expectedCommands = @[
        @"delete from Value where key=World and node=3"
    ];
    XCTAssertEqualObjects(db.commands, expectedCommands);
}

- (void)testSQLiteRoundTripPropertyList {
    NSString *file = [[NSWorkspace sharedWorkspace] temporaryFileNameWithPrefix:@"test" suffix:@"db"];
    NSURL *url = [NSURL fileURLWithPath:file];
    iTermGraphDatabase *db =
    [[iTermGraphDatabase alloc] initWithURL:url
                            databaseFactory:[[iTermSqliteDatabaseFactory alloc] init]];
    NSDictionary *dict = @{
        @"root": @{
            @"key": @"value",
            @"nothing": [NSNull null],
            @"array": @[ @3, @2, @1 ]
        }
    };
    [db update:^(iTermGraphEncoder * _Nonnull encoder) {
        [encoder encodeDictionary:dict[@"root"] withKey:@"root" generation:1];
    }
    completion:nil];
    [db.db close];

    db = [[iTermGraphDatabase alloc] initWithURL:url
                            databaseFactory:[[iTermSqliteDatabaseFactory alloc] init]];
    XCTAssertEqualObjects(db.record.propertyListValue, dict);

}

- (void)testSQLiteRoundTripManual {
    NSString *file = [[NSWorkspace sharedWorkspace] temporaryFileNameWithPrefix:@"test" suffix:@"db"];
    NSURL *url = [NSURL fileURLWithPath:file];
    iTermGraphDatabase *db =
    [[iTermGraphDatabase alloc] initWithURL:url
                            databaseFactory:[[iTermSqliteDatabaseFactory alloc] init]];
    [db update:^(iTermGraphEncoder * _Nonnull encoder) {
        [encoder encodeChildWithKey:@"root" identifier:@"" generation:1 block:^BOOL (iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"string" forKey:@"STRING"];
            [subencoder encodeArrayWithKey:@"values" generation:1 identifiers:@[ @"i1", @"i2" ] options:0 block:^BOOL (NSString * _Nonnull identifier, NSInteger index, iTermGraphEncoder * _Nonnull subencoder) {
                [subencoder encodeString:[identifier stringRepeatedTimes:10] forKey:identifier];
                return YES;
            }];
            return YES;
        }];
    }
    completion:nil];
    [db.db close];

    db = [[iTermGraphDatabase alloc] initWithURL:url
                            databaseFactory:[[iTermSqliteDatabaseFactory alloc] init]];
    [db update:^(iTermGraphEncoder * _Nonnull encoder) {
        [encoder encodeChildWithKey:@"root" identifier:@"" generation:2 block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder encodeString:@"string" forKey:@"STRING"];
            [subencoder encodeArrayWithKey:@"values" generation:2 identifiers:@[ @"i2", @"i3" ] options:0 block:^BOOL (NSString * _Nonnull identifier, NSInteger index, iTermGraphEncoder * _Nonnull subencoder) {
                [subencoder encodeString:[identifier stringRepeatedTimes:10] forKey:identifier];
                return YES;
            }];
            return YES;
        }];
    }
    completion:nil];

    NSDictionary *expected = @{
        @"root": @{
                @"STRING": @"string",
                @"values": @[
                        @{ @"i2": @"i2i2i2i2i2i2i2i2i2i2" },
                        @{ @"i3": @"i3i3i3i3i3i3i3i3i3i3" }]
        }
    };
    XCTAssertEqualObjects(expected, db.record.propertyListValue);
}

- (void)testAdapterArray {
    NSString *file = [[NSWorkspace sharedWorkspace] temporaryFileNameWithPrefix:@"test" suffix:@"db"];
    NSURL *url = [NSURL fileURLWithPath:file];
    iTermGraphDatabase *db =
    [[iTermGraphDatabase alloc] initWithURL:url
                            databaseFactory:[[iTermSqliteDatabaseFactory alloc] init]];
    NSArray *myArray = @[ @2, @4, @6, @8 ];
    NSArray *arrayOfDicts = @[ @{ @"x": @"X" },
                               @{ @"y": @"Y" }];
    [db update:^(iTermGraphEncoder * _Nonnull encoder) {
        iTermGraphEncoderAdapter *adapter = [[iTermGraphEncoderAdapter alloc] initWithGraphEncoder:encoder];
        adapter[@"myArray"] = myArray;
        adapter[@"arrayOfDicts"] = arrayOfDicts;
    }
    completion:nil];
    [db.db close];

    db =
    [[iTermGraphDatabase alloc] initWithURL:url
                            databaseFactory:[[iTermSqliteDatabaseFactory alloc] init]];
    NSDictionary *plist = db.record.propertyListValue;
    XCTAssertEqualObjects(plist[@"myArray"], myArray);
    XCTAssertEqualObjects(plist[@"arrayOfDicts"], arrayOfDicts);
}

- (void)testDictWithArrays {
    NSString *file = [[NSWorkspace sharedWorkspace] temporaryFileNameWithPrefix:@"test" suffix:@"db"];
    NSURL *url = [NSURL fileURLWithPath:file];
    iTermGraphDatabase *db =
    [[iTermGraphDatabase alloc] initWithURL:url
                            databaseFactory:[[iTermSqliteDatabaseFactory alloc] init]];
    [db update:^(iTermGraphEncoder * _Nonnull encoder) {
        iTermGraphEncoderAdapter *adapter = [[iTermGraphEncoderAdapter alloc] initWithGraphEncoder:encoder];
        [adapter encodeArrayWithKey:@"Tabs"
                        identifiers:@[ @"tab1" ]
                         generation:iTermGenerationAlwaysEncode
                              block:^BOOL(id<iTermEncoderAdapter>  _Nonnull encoder, NSInteger i, NSString * _Nonnull identifier) {
            return [encoder encodeDictionaryWithKey:@"Root"
                                         generation:iTermGenerationAlwaysEncode
                                              block:^BOOL(id<iTermEncoderAdapter>  _Nonnull encoder) {
                [encoder encodeArrayWithKey:@"Subviews"
                                identifiers:@[ @"view1" ]
                                 generation:iTermGenerationAlwaysEncode
                                      block:^BOOL(id<iTermEncoderAdapter>  _Nonnull encoder, NSInteger i, NSString * _Nonnull identifier) {
                    return [encoder encodeDictionaryWithKey:@"session"
                                                 generation:iTermGenerationAlwaysEncode
                                                      block:^BOOL(id<iTermEncoderAdapter>  _Nonnull encoder) {
                        return [encoder encodeDictionaryWithKey:@"contents"
                                                     generation:iTermGenerationAlwaysEncode
                                                          block:^BOOL(id<iTermEncoderAdapter>  _Nonnull encoder) {
                            [encoder mergeDictionary:@{
                                @"cll": @[ @2, @4, @6, @8 ],
                                @"metadata": @[ @1, @"foo" ]
                            }];
                            return YES;
                        }];
                    }];
                }];
                return YES;
            }];
        }];
    }
    completion:nil];
    [db.db close];

    db =
    [[iTermGraphDatabase alloc] initWithURL:url
                            databaseFactory:[[iTermSqliteDatabaseFactory alloc] init]];
    NSDictionary *plist = db.record.propertyListValue;
    NSArray *tabs = plist[@"Tabs"];
    XCTAssertNotNil(tabs);
    NSDictionary *tab = tabs[0];
    XCTAssertNotNil(tab);
    NSDictionary *root = tab[@"Root"];
    XCTAssertNotNil(root);
    NSArray *subviews = root[@"Subviews"];
    XCTAssertNotNil(subviews);
    NSDictionary *subview = subviews[0];
    XCTAssertNotNil(subview);
    NSDictionary *session = subview[@"session"];
    XCTAssertNotNil(session);
    NSDictionary *contents = session[@"contents"];
    XCTAssertNotNil(contents);
    NSArray *cll = contents[@"cll"];
    NSArray *expected = @[ @2, @4, @6, @8 ];
    XCTAssertEqualObjects(cll, expected);

    NSArray *metadata = contents[@"metadata"];
    expected = @[ @1, @"foo" ];
    XCTAssertEqualObjects(metadata, expected);
}

@end
