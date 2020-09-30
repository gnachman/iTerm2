//
//  iTermCoding.m
//  iTerm2XCTests
//
//  Created by George Nachman on 7/26/20.
//
#if 0
#import <XCTest/XCTest.h>

#import "NSArray+iTerm.h"
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

@interface NSString(Coding)
@end
@implementation NSString(Coding)
- (NSString *)compactDescription {
    return self;
}
@end

@interface NSData(Coding)
@end
@implementation NSData(Coding)
- (NSString *)compactDescription {
    NSString *string = [[NSString alloc] initWithData:self encoding:NSUTF8StringEncoding];
    if (string) {
        return string;
    }
    return [self it_hexEncoded];
}
@end

@interface NSDate(Coding)
@end
@implementation NSDate(Coding)
- (NSString *)compactDescription {
    return [@(self.timeIntervalSince1970) stringValue];
}
@end

@interface NSNull(Coding)
@end
@implementation NSNull(Coding)
- (NSString *)compactDescription {
    return @"{null}";
}
@end

@interface NSArray(Coding)
@end
@implementation NSArray(Coding)
- (NSString *)compactDescription {
    return [NSString stringWithFormat:@"[%@]",
            [[self mapWithBlock:^id(id anObject) {
        return [anObject compactDescription];
    }] componentsJoinedByString:@", "]];
}
@end

@interface NSDictionary(Coding)
@end
@implementation NSDictionary(Coding)
- (NSString *)compactDescription {
    NSString *kvps = [[self.allKeys mapWithBlock:^id(id anObject) {
        return [NSString stringWithFormat:@"%@=%@", [anObject compactDescription], [self[anObject] compactDescription]];
    }] componentsJoinedByString:@", "];
    return [NSString stringWithFormat:@"{%@}", kvps];
}
@end

@interface iTermEncoderGraphRecord (Testing)
@end

@implementation iTermEncoderGraphRecord (Testing)
- (NSString *)formattedData {
    return [[self.pod.allKeys mapWithBlock:^id(NSString *key) {
        return [NSString stringWithFormat:@"%@=%@", [self.pod[key] compactDescription]];
    }] componentsJoinedByString:@" "];
}
@end

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

- (void)unlink {
    assert(!_open);
}



@end

@implementation iTermCoding {
    NSInteger _rowid;
}

- (void)testGraphRecord_OnlyPOD {
    NSArray<iTermEncoderGraphRecord *> *graphs = nil;
    iTermEncoderGraphRecord *record;
    record = [iTermEncoderGraphRecord withPODs:@{ @"one": @1, @"letter": @"x"}
                                        graphs:graphs
                                    generation:3
                                           key:@"root"
                                    identifier:@""
                                         rowid:@1];

    NSDictionary<NSString *, id> *expectedPOD =
    @{ @"one": @1,
       @"letter": @"x" };
    XCTAssertEqualObjects(expectedPOD, record.pod);
    XCTAssertEqualObjects(@[], record.graphRecords);
    XCTAssertEqual(3, record.generation);
    XCTAssertEqualObjects(@"root", record.key);
    XCTAssertEqualObjects(@"", record.identifier);
    XCTAssertEqualObjects(@1, record.rowid);
}

- (void)testGraphRecord {
    NSDictionary *pods1 = @{ @"one": @1, @"letter": @"x" };
    NSDictionary *pods2 = @{ @"one": @2, @"letter": @"y" };
    NSData *data = [NSData dataWithBytes:"xyz" length:3];
    NSDictionary *pods3 = @{ @"now": [NSDate dateWithTimeIntervalSince1970:1000000000],
                             @"data": data };
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

    XCTAssertEqualObjects(pods3, record.pod);
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

    NSDictionary *expectedPODs = @{
        @"color": @"red",
        @"count": @1,
        @"blob": [NSData dataWithBytes:"abc" length:3],
        @"date": date,
    };
    NSArray *expectedGraphs =
    @[ [iTermEncoderGraphRecord withPODs:@{ @"name": @"bob" } graphs:@[] generation:2 key:@"left" identifier:@"" rowid:nil],
       [iTermEncoderGraphRecord withPODs:@{ @"age": @23 } graphs:@[] generation:3 key:@"right" identifier:@"" rowid:nil] ];
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
    iTermEncoderGraphRecord *lhs = [iTermEncoderGraphRecord withPODs:@{}
                                                              graphs:@[]
                                                          generation:1
                                                                 key:@""
                                                          identifier:@""
                                                               rowid:@2];
    iTermEncoderGraphRecord *rhs = [iTermEncoderGraphRecord withPODs:@{}
                                                              graphs:@[]
                                                          generation:2
                                                                 key:@""
                                                          identifier:@""
                                                               rowid:@3];
    NSComparisonResult comp = [lhs compareGraphRecord:rhs];
    XCTAssertEqual(comp, NSOrderedAscending);

    rhs = [iTermEncoderGraphRecord withPODs:@{}
                                     graphs:@[]
                                 generation:1
                                        key:@""
                                 identifier:@""
                                      rowid:@1];
    comp = [lhs compareGraphRecord:rhs];
    XCTAssertEqual(comp, NSOrderedSame);
}

- (void)testGraphRecordEquality {
    iTermEncoderGraphRecord *lhs = [iTermEncoderGraphRecord withPODs:@{}
                                                              graphs:@[]
                                                          generation:1
                                                                 key:@""
                                                          identifier:@""
                                                               rowid:@1];
    XCTAssertNotEqualObjects(lhs, (id _Nonnull)nil);
    XCTAssertEqualObjects(lhs, lhs);
    XCTAssertNotEqualObjects(lhs, @123);

    iTermEncoderGraphRecord *rhs = [iTermEncoderGraphRecord withPODs:@{}
                                                              graphs:@[]
                                                          generation:1
                                                                 key:@"x"
                                                          identifier:@""
                                                               rowid:@1];
    XCTAssertNotEqualObjects(lhs, rhs);

    rhs = [iTermEncoderGraphRecord withPODs:@{ @"xk": @"xy" }
                                     graphs:@[]
                                 generation:1
                                        key:@"x"
                                 identifier:@""
                                      rowid:@1];
    XCTAssertNotEqualObjects(lhs, rhs);

    rhs = [iTermEncoderGraphRecord withPODs:@{}
                                     graphs:@[lhs]
                                 generation:1
                                        key:@""
                                 identifier:@""
                                      rowid:@1];
    XCTAssertNotEqualObjects(lhs, rhs);

    rhs = [iTermEncoderGraphRecord withPODs:@{}
                                     graphs:@[]
                                 generation:2
                                        key:@""
                                 identifier:@""
                                      rowid:@1];
    XCTAssertNotEqualObjects(lhs, rhs);

    rhs = [iTermEncoderGraphRecord withPODs:@{}
                                     graphs:@[]
                                 generation:1
                                        key:@""
                                 identifier:@"bogus"
                                      rowid:@1];
    XCTAssertNotEqualObjects(lhs, rhs);

    rhs = [iTermEncoderGraphRecord withPODs:@{}
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
    NSData *(^ser)(NSDictionary *) = ^NSData *(NSDictionary *dict) {
        return [NSData it_dataWithSecurelyArchivedObject:dict error:nil];
    };
    NSData *data = [NSData dataWithBytes:"xyz" length:3];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:1000000000];
    NSDictionary *rootPOD = @{ @"vk1": @"vv1", @"vk2": @123, @"vk3": date, @"vk4": data };
    NSDictionary *k5POD = @{ @"vv2": @"vk5" };
    NSArray *nodes = @[
        // key, identifier, parent, rowid, data
        @[ @"k5", @"",   @3, @5, ser(k5POD) ],
        @[ @"k4", @"i1", @2, @4, [NSData data] ],
        @[ @"k4", @"i2", @2, @3, [NSData data] ],
        @[ @"k2", @"",   @1, @2, [NSData data] ],
        @[ @"",   @"",   @0, @1, ser(rootPOD) ],
    ];

    iTermGraphTableTransformer *transformer =
    [[iTermGraphTableTransformer alloc] initWithNodeRows:nodes];

    iTermEncoderGraphRecord *record = transformer.root;
    XCTAssertNotNil(record);

    NSArray<iTermEncoderGraphRecord *> *expectedK4Children = @[
        [iTermEncoderGraphRecord withPODs:k5POD
                                   graphs:@[]
                               generation:0
                                      key:@"k5"
                               identifier:@""
                                    rowid:@5],
    ];
    NSArray<iTermEncoderGraphRecord *> *expectedK2Children = @[
        [iTermEncoderGraphRecord withPODs:@{}
                                   graphs:expectedK4Children
                               generation:0
                                      key:@"k4"
                               identifier:@"i2"
                                    rowid:@3],
        [iTermEncoderGraphRecord withPODs:@{}
                                   graphs:@[]
                               generation:0
                                      key:@"k4"
                               identifier:@"i1"
                                    rowid:@4],
    ];
    NSArray<iTermEncoderGraphRecord *> *expectedRootGraphs = @[
        [iTermEncoderGraphRecord withPODs:@{}
                                   graphs:expectedK2Children
                               generation:0
                                      key:@"k2"
                               identifier:@""
                                    rowid:@2],

    ];
    iTermEncoderGraphRecord *expected =
    [iTermEncoderGraphRecord withPODs:rootPOD
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
        // key, identifier, parent, rowid, data
        @[ @"",  @"" ],
    ];

    iTermGraphTableTransformer *transformer =
    [[iTermGraphTableTransformer alloc] initWithNodeRows:nodes];

    iTermEncoderGraphRecord *record = transformer.root;
    XCTAssertNil(record);
}

- (void)testGraphTableTransformer_MistypedFieldInNodeRow {
    NSArray *nodes = @[
        // key, identifier, parent, rowid, data
        @[ @666, @"", @1, @2, [NSData data] ],
    ];

    iTermGraphTableTransformer *transformer =
    [[iTermGraphTableTransformer alloc] initWithNodeRows:nodes];

    iTermEncoderGraphRecord *record = transformer.root;
    XCTAssertNil(record);
}

- (void)testGraphTableTransformer_TwoRoots {
    NSArray *nodes = @[
        // key, identifier, parent, rowid, data
        @[ @"",  @"", @0, @1, [NSData data] ],
        @[ @"",  @"", @0, @2, [NSData data] ],
    ];

    iTermGraphTableTransformer *transformer =
    [[iTermGraphTableTransformer alloc] initWithNodeRows:nodes];

    iTermEncoderGraphRecord *record = transformer.root;
    XCTAssertNil(record);
}

- (void)testGraphTableTransformer_ChildWithBadParent {
    NSData *data = [NSData data];
    NSArray *nodes = @[
        // key, identifier, parent, rowid, data
        @[ @"",      @"", @0,   @1,   data ],
        @[ @"child", @"", @666, @2, data ],
    ];

    iTermGraphTableTransformer *transformer =
    [[iTermGraphTableTransformer alloc] initWithNodeRows:nodes];

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
                                NSNumber * _Nonnull parent,
                                BOOL * _Nonnull stop) {
        XCTAssertFalse(done);
        XCTAssertNotNil(before);
        XCTAssertNotNil(after);

        if ([before.key isEqualToString:@"leaf"]) {
            NSDictionary *expectedBeforePOD = @{ @"key": @"value1" };
            XCTAssertEqualObjects(before.pod, expectedBeforePOD);

            NSDictionary *expectedAfterPOD = @{ @"key": @"value2" };
            XCTAssertEqualObjects(after.pod, expectedAfterPOD);
            done = YES;
        }
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
                                NSNumber * _Nonnull parent,
                                BOOL * _Nonnull stop) {
        XCTAssertFalse(done);
        XCTAssertNotNil(before);
        XCTAssertNotNil(after);

        if ([before.key isEqualToString:@"leaf"]) {
            NSDictionary *expectedBeforePOD = @{ @"key": @"value1" };
            XCTAssertEqualObjects(before.pod, expectedBeforePOD);

            NSDictionary *expectedAfterPOD = @{ };
            XCTAssertEqualObjects(after.pod, expectedAfterPOD);
            done = YES;
        }
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
                                NSNumber * _Nonnull parent,
                                BOOL * _Nonnull stop) {
        XCTAssertFalse(done);
        XCTAssertNotNil(before);
        XCTAssertNotNil(after);

        if ([before.key isEqualToString:@"leaf"]) {
            NSDictionary *expectedBeforePOD = @{ };
            XCTAssertEqualObjects(before.pod, expectedBeforePOD);

            NSDictionary *expectedAfterPOD = @{ @"key": @"value1" };
            XCTAssertEqualObjects(after.pod, expectedAfterPOD);
            done = YES;
        }
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
                                NSNumber * _Nonnull parent,
                                BOOL * _Nonnull stop) {
        if ([before.key isEqualToString:@"leaf"]) {
            XCTAssertNil(after);
            NSDictionary *expectedBeforePOD = @{ @"key": @"value1" };
            XCTAssertEqualObjects(before.pod, expectedBeforePOD);
            done = YES;
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
                                NSNumber * _Nonnull parent,
                                BOOL * _Nonnull stop) {
        if ([after.key isEqualToString:@"leaf"]) {
            XCTAssertNil(before);

            NSDictionary *expectedAfterPOD = @{ @"key": @"value1" };
            XCTAssertEqualObjects(after.pod, expectedAfterPOD);
            done = YES;
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
                                       iTermGraphEncoder * _Nonnull subencoder,
                                       BOOL *stop) {
        [subencoder encodeString:[NSString stringWithFormat:@"value1_%@_%@", identifier, @(index)]
                          forKey:@"k"];
        return YES;
    }];

    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeArrayWithKey:@"a"
                     generation:1
                    identifiers:@[ @"i1", @"i2", @"i3" ]
                          options:0
                          block:^BOOL (NSString * _Nonnull identifier, NSInteger index, iTermGraphEncoder * _Nonnull subencoder, BOOL *stop) {
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
                                       iTermGraphEncoder * _Nonnull subencoder,
                                       BOOL *stop) {
        [subencoder encodeString:[NSString stringWithFormat:@"value1_%@_%@", identifier, @(index)]
                          forKey:[NSString stringWithFormat:@"k_%@", identifier]];
        return YES;
    }];
    {
        NSArray<NSString *> *actual = [self pseudoSQLFromEncoder:encoder];
        NSArray<NSString *> *expected = @[
            @"insert node key=, identifier=, parent=0, data={} -> 1",
            @"insert node key=__array, identifier=a, parent=1, data={__order=i1\ti2\ti3} -> 2",
            @"insert node key=, identifier=i1, parent=2, data={k_i1=value1_i1_0} -> 3",
            @"insert node key=, identifier=i2, parent=2, data={k_i2=value1_i2_1} -> 4",
            @"insert node key=, identifier=i3, parent=2, data={k_i3=value1_i3_2} -> 5"
        ];
        XCTAssertEqualObjects(actual, expected);
    }

    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeArrayWithKey:@"a"
                     generation:2
                    identifiers:@[ @"i1", @"i2", @"i3" ]
                          options:0
                          block:^BOOL (NSString * _Nonnull identifier, NSInteger index, iTermGraphEncoder * _Nonnull subencoder, BOOL *stop) {
        [subencoder encodeString:[NSString stringWithFormat:@"value2_%@_%@", identifier, @(index)]
                          forKey:[NSString stringWithFormat:@"k_%@", identifier]];
        return YES;
    }];

    {
        NSArray<NSString *> *actual = [self pseudoSQLFromEncoder:encoder];
        NSArray<NSString *> *expected = @[
            @"update node where rowid=3 set data={k_i1=value2_i1_0}",
            @"update node where rowid=4 set data={k_i2=value2_i2_1}",
            @"update node where rowid=5 set data={k_i3=value2_i3_2}"
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
                                       iTermGraphEncoder * _Nonnull subencoder,
                                       BOOL *stop) {
        [subencoder encodeString:[NSString stringWithFormat:@"value1_%@_%@", identifier, @(index)]
                          forKey:[NSString stringWithFormat:@"k_%@", identifier]];
        return YES;
    }];
    {
        NSArray<NSString *> *actual = [self pseudoSQLFromEncoder:encoder];
        NSArray<NSString *> *expected = @[
            @"insert node key=, identifier=, parent=0, data={} -> 1",
            @"insert node key=__array, identifier=a, parent=1, data={__order=i1\ti2\ti3} -> 2",
            @"insert node key=, identifier=i1, parent=2, data={k_i1=value1_i1_0} -> 3",
            @"insert node key=, identifier=i2, parent=2, data={k_i2=value1_i2_1} -> 4",
            @"insert node key=, identifier=i3, parent=2, data={k_i3=value1_i3_2} -> 5"
        ];
        XCTAssertEqualObjects(actual, expected);
    }

    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeArrayWithKey:@"a"
                     generation:2
                    identifiers:@[ @"i2", @"i3" ]
                          options:0
                          block:^BOOL (NSString * _Nonnull identifier, NSInteger index, iTermGraphEncoder * _Nonnull subencoder, BOOL *stop) {
        [subencoder encodeString:[NSString stringWithFormat:@"value2_%@_%@", identifier, @(index)]
                          forKey:[NSString stringWithFormat:@"k_%@", identifier]];
        return YES;
    }];

    {
        NSArray<NSString *> *actual = [self pseudoSQLFromEncoder:encoder];
        NSArray<NSString *> *expected = @[
            @"update node where rowid=2 set data={__order=i2\ti3}",
            @"delete node where rowid=3",
            @"update node where rowid=4 set data={k_i2=value2_i2_0}",
            @"update node where rowid=5 set data={k_i3=value2_i3_1}"
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
                                       iTermGraphEncoder * _Nonnull subencoder,
                                       BOOL *stop) {
        [subencoder encodeString:[NSString stringWithFormat:@"value1_%@_%@", identifier, @(index)]
                          forKey:[NSString stringWithFormat:@"k_%@", identifier]];
        return YES;
    }];
    {
        NSArray<NSString *> *actual = [self pseudoSQLFromEncoder:encoder];
        NSArray<NSString *> *expected = @[
            @"insert node key=, identifier=, parent=0, data={} -> 1",
            @"insert node key=__array, identifier=a, parent=1, data={__order=i1\ti2\ti3} -> 2",
            @"insert node key=, identifier=i1, parent=2, data={k_i1=value1_i1_0} -> 3",
            @"insert node key=, identifier=i2, parent=2, data={k_i2=value1_i2_1} -> 4",
            @"insert node key=, identifier=i3, parent=2, data={k_i3=value1_i3_2} -> 5"
        ];
        XCTAssertEqualObjects(actual, expected);
    }

    encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:encoder.record];
    [encoder encodeArrayWithKey:@"a"
                     generation:2
                    identifiers:@[ @"i1", @"i2", @"i3", @"i4" ]
                          options:0
                          block:^BOOL (NSString * _Nonnull identifier, NSInteger index, iTermGraphEncoder * _Nonnull subencoder, BOOL *stop) {
        [subencoder encodeString:[NSString stringWithFormat:@"value1_%@_%@", identifier, @(index)]
                          forKey:[NSString stringWithFormat:@"k_%@", identifier]];
        return YES;
    }];

    {
        NSArray<NSString *> *actual = [self pseudoSQLFromEncoder:encoder];
        NSArray<NSString *> *expected = @[
            @"update node where rowid=2 set data={__order=i1\ti2\ti3\ti4}",
            @"insert node key=, identifier=i4, parent=2, data={k_i4=value1_i4_3} -> 6"
        ];
        XCTAssertEqualObjects(actual, expected);
    }
}

- (NSArray<NSString *> *)pseudoSQLFromEncoder:(iTermGraphDeltaEncoder *)encoder {
    NSMutableArray<NSString *> *statements = [NSMutableArray array];
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSNumber * _Nonnull parent,
                                BOOL * _Nonnull stop) {
        if (before && !after) {
            [statements addObject:[NSString stringWithFormat:@"delete node where rowid=%@", before.rowid]];
        } else if (!before && after) {
            after.rowid = @(++_rowid);
            [statements addObject:[NSString stringWithFormat:@"insert node key=%@, identifier=%@, parent=%@, data=%@ -> %@",
                                   after.key, after.identifier, parent ?: @0, after.pod.compactDescription, after.rowid]];
        } else if (before && after) {
            if ([before.pod isEqual:after.pod]) {
                return;
            }
            [statements addObject:[NSString stringWithFormat:@"update node where rowid=%@ set data=%@",
                                   before.rowid, after.pod.compactDescription]];
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
        @"insert node key=, identifier=, parent=0, data={k1=k1_v1} -> 1",
        @"insert node key=k2, identifier=, parent=1, data={k3=k3_v1} -> 2",
        @"insert node key=k4, identifier=, parent=2, data={k5=k5_v1} -> 3",
        @"insert node key=k6, identifier=i1, parent=2, data={k7=k7_v1} -> 4",
        @"insert node key=k6, identifier=i2, parent=2, data={k9=k9_v1, k9a=k9a_v1} -> 5",
        @"insert node key=k6, identifier=i3, parent=2, data={k10=k10_v1} -> 6"
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
        @"update node where rowid=1 set data={k1=k1_v2}",
        @"update node where rowid=2 set data={}",
        @"delete node where rowid=4",
        @"update node where rowid=5 set data={k9=k9_v2, k9a=k9a_v1, k9b=k9b_v1}",
        @"insert node key=k6, identifier=i4, parent=2, data={k11=k11_v1} -> 7"
    ];
    XCTAssertEqualObjects(actual, expected);
}

- (NSString *)hexified:(id)pod {
    NSData *data = [NSData it_dataWithSecurelyArchivedObject:pod error:nil];
    NSString *hex = data.it_hexEncoded;
    return hex;
}

- (void)testGraphDatabase_Initialization {
    NSDictionary *results = @{
        @"select key, identifier, parent, rowid, data from Node": [iTermMockDatabaseResultSet withRows:@[]]
    };

    iTermMockDatabaseFactory *mockDB = [[iTermMockDatabaseFactory alloc] initWithResults:[results mutableCopy]
                                                                                database:nil];
    iTermGraphDatabase *gdb = [[iTermGraphDatabase alloc] initWithURL:[NSURL fileURLWithPath:@"/db"]
                                                      databaseFactory:mockDB];

    NSArray<NSString *> *expectedCommands = @[
        @"PRAGMA journal_mode=WAL",
        @"create table if not exists Node (key text not null, identifier text not null, parent integer not null, data blob)",
    ];
    iTermMockDatabase *db = (iTermMockDatabase *)gdb.db;
    XCTAssertEqualObjects(db.commands, expectedCommands);
}

- (void)testGraphDatabase_Load {
    NSDictionary *pod = @{
        @"color": @"red",
        @"number": @123
    };
    NSMutableDictionary<NSString *,id<iTermDatabaseResultSet>> *results = [NSMutableDictionary dictionary];
    results[@"select key, identifier, parent, rowid, data from Node"] = [iTermMockDatabaseResultSet withRows:@[
        @{ @"key": @"",
           @"identifier": @"",
           @"parent": @0,
           @"rowid": @1,
           @"data": [NSData it_dataWithSecurelyArchivedObject:@{} error:nil]
        },

        @{ @"key": @"mynode",
           @"identifier": @"",
           @"parent": @1,
           @"rowid": @2,
           @"data": [NSData it_dataWithSecurelyArchivedObject:pod error:nil]
        },
    ]];

    iTermMockDatabaseFactory *mockDB = [[iTermMockDatabaseFactory alloc] initWithResults:results
                                                                                database:nil];
    iTermGraphDatabase *gdb = [[iTermGraphDatabase alloc] initWithURL:[NSURL fileURLWithPath:@"/db"]
                                                      databaseFactory:mockDB];
    XCTAssertNotNil(gdb);
    iTermMockDatabase *db = mockDB.database;
    XCTAssertNotNil(db);

    NSDictionary *pods = @{
        @"color": @"red",
        @"number": @123 ,
    };
    iTermEncoderGraphRecord *mynode =
        [iTermEncoderGraphRecord withPODs:pods
                                   graphs:@[]
                               generation:0
                                      key:@"mynode"
                               identifier:@""
                                    rowid:@2];
    iTermEncoderGraphRecord *expectedRecord =
    [iTermEncoderGraphRecord withPODs:@{}
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
    results[@"select key, identifier, parent, rowid, data from Node"] = [iTermMockDatabaseResultSet withRows:@[]];

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
    NSString *hex = [self hexified:@{ @"World": @"Hello" }];
    NSArray<NSString *> *expectedCommands = @[
        @"PRAGMA journal_mode=WAL",
        @"create table if not exists Node (key text not null, identifier text not null, parent integer not null, data blob)",
        @"insert into Node (key, identifier, parent, data) values (, , 0, )",
        @"insert into Node (key, identifier, parent, data) values (wrapper, , 1, )",
        [NSString stringWithFormat:@"insert into Node (key, identifier, parent, data) values (mynode, , 2, %@)", hex]
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
        @"delete from Node where rowid=3"
    ];
    XCTAssertEqualObjects(db.commands, expectedCommands);
}

- (void)testGraphDatabase_InsertNode {
    NSMutableDictionary<NSString *,id<iTermDatabaseResultSet>> *results = [NSMutableDictionary dictionary];
    results[@"select key, identifier, parent, rowid, data from Node"] = [iTermMockDatabaseResultSet withRows:@[]];

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
    NSString *hex = [self hexified:@{ @"World": @"Hello" }];
    NSArray<NSString *> *expectedCommands = @[
        @"PRAGMA journal_mode=WAL",
        @"create table if not exists Node (key text not null, identifier text not null, parent integer not null, data blob)",
        @"insert into Node (key, identifier, parent, data) values (, , 0, )",
        @"insert into Node (key, identifier, parent, data) values (wrapper, , 1, )",
        [NSString stringWithFormat:@"insert into Node (key, identifier, parent, data) values (mynode, , 2, %@)", hex]
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
        [NSString stringWithFormat:@"insert into Node (key, identifier, parent, data) values (othernode, , 2, %@)",
         [self hexified:@{ @"Everybody": @"Goodbye" }]]
    ];
    XCTAssertEqualObjects(db.commands, expectedCommands);
}

- (void)testGraphDatabase_UpdateValue {
    NSMutableDictionary<NSString *,id<iTermDatabaseResultSet>> *results = [NSMutableDictionary dictionary];
    results[@"select key, identifier, parent, rowid, data from Node"] = [iTermMockDatabaseResultSet withRows:@[]];

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
    NSString *hex = [self hexified:@{ @"World": @"Hello" }];
    NSArray<NSString *> *expectedCommands = @[
        @"PRAGMA journal_mode=WAL",
        @"create table if not exists Node (key text not null, identifier text not null, parent integer not null, data blob)",
        @"insert into Node (key, identifier, parent, data) values (, , 0, )",
        @"insert into Node (key, identifier, parent, data) values (wrapper, , 1, )",
        [NSString stringWithFormat:@"insert into Node (key, identifier, parent, data) values (mynode, , 2, %@)", hex]
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
        [NSString stringWithFormat:@"update Node set data=%@ where rowid=3",
         [self hexified:@{ @"World": @"Goodbye" }]]
    ];
    XCTAssertEqualObjects(db.commands, expectedCommands);
}

- (void)testGraphDatabase_InsertValue {
    NSMutableDictionary<NSString *,id<iTermDatabaseResultSet>> *results = [NSMutableDictionary dictionary];
    results[@"select key, identifier, parent, rowid, data from Node"] = [iTermMockDatabaseResultSet withRows:@[]];

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
    NSString *hex = [self hexified:@{ @"World": @"Hello" }];
    NSArray<NSString *> *expectedCommands = @[
        @"PRAGMA journal_mode=WAL",
        @"create table if not exists Node (key text not null, identifier text not null, parent integer not null, data blob)",
        @"insert into Node (key, identifier, parent, data) values (, , 0, )",
        @"insert into Node (key, identifier, parent, data) values (wrapper, , 1, )",
        [NSString stringWithFormat:@"insert into Node (key, identifier, parent, data) values (mynode, , 2, %@)", hex]
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
        [NSString stringWithFormat:@"update Node set data=%@ where rowid=3",
         [self hexified:@{ @"World": @"Hello",
                           @"Everybody": @"Goodbye" }]]
    ];
    XCTAssertEqualObjects(db.commands, expectedCommands);
}

- (void)testGraphDatabase_DeleteValue {
    NSMutableDictionary<NSString *,id<iTermDatabaseResultSet>> *results = [NSMutableDictionary dictionary];
    results[@"select key, identifier, parent, rowid, data from Node"] = [iTermMockDatabaseResultSet withRows:@[]];

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
    NSString *hex = [self hexified:@{ @"World": @"Hello" }];
    NSArray<NSString *> *expectedCommands = @[
        @"PRAGMA journal_mode=WAL",
        @"create table if not exists Node (key text not null, identifier text not null, parent integer not null, data blob)",
        @"insert into Node (key, identifier, parent, data) values (, , 0, )",
        @"insert into Node (key, identifier, parent, data) values (wrapper, , 1, )",
        [NSString stringWithFormat:@"insert into Node (key, identifier, parent, data) values (mynode, , 2, %@)", hex]
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
        @"update Node set data= where rowid=3"
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
            [subencoder encodeArrayWithKey:@"values" generation:1 identifiers:@[ @"i1", @"i2" ] options:0 block:^BOOL (NSString * _Nonnull identifier, NSInteger index, iTermGraphEncoder * _Nonnull subencoder, BOOL *stop) {
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
            [subencoder encodeArrayWithKey:@"values" generation:2 identifiers:@[ @"i2", @"i3" ] options:0 block:^BOOL (NSString * _Nonnull identifier, NSInteger index, iTermGraphEncoder * _Nonnull subencoder, BOOL *stop) {
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
                              block:^BOOL(id<iTermEncoderAdapter>  _Nonnull encoder, NSInteger i, NSString * _Nonnull identifier, BOOL *stop) {
            return [encoder encodeDictionaryWithKey:@"Root"
                                         generation:iTermGenerationAlwaysEncode
                                              block:^BOOL(id<iTermEncoderAdapter>  _Nonnull encoder) {
                [encoder encodeArrayWithKey:@"Subviews"
                                identifiers:@[ @"view1" ]
                                 generation:iTermGenerationAlwaysEncode
                                      block:^BOOL(id<iTermEncoderAdapter>  _Nonnull encoder, NSInteger i, NSString * _Nonnull identifier, BOOL *stop) {
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
#endif
