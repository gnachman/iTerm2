//
//  iTermGraphDatabaseRecoveryTests.m
//  ModernTests
//
//  Drives iTermGraphDatabase through a real save → fail → recovery cycle to
//  exercise the recovery path in trySaveEncoder:state:completion:.
//

#import <XCTest/XCTest.h>

#import "iTermGraphDatabase.h"
#import "iTermGraphDeltaEncoder.h"
#import "iTermGraphEncoder.h"
#import "iTermEncoderGraphRecord.h"
#import "iTermDatabase.h"

#pragma mark - Failure-injection wrapper

// Subclass of the real SQLite-backed iTermDatabase that can be told to fail
// its next `transaction:` call. Forcing transaction: to return NO without
// running the block is the simplest way to make iTermGraphDatabase's save
// return NO, which sends trySaveEncoder: down its recovery branch.
@interface iTermGraphDBRecoveryTest_FailableDatabase : iTermSqliteDatabaseImpl
@property (nonatomic, assign) BOOL failNextTransaction;
@end

@implementation iTermGraphDBRecoveryTest_FailableDatabase

- (BOOL)transaction:(BOOL (^ NS_NOESCAPE)(void))block {
    if (_failNextTransaction) {
        _failNextTransaction = NO;
        return NO;
    }
    return [super transaction:block];
}

@end

#pragma mark - Test

@interface iTermGraphDatabaseRecoveryTests : XCTestCase
@end

@implementation iTermGraphDatabaseRecoveryTests {
    NSURL *_url;
    iTermGraphDBRecoveryTest_FailableDatabase *_db;
    iTermGraphDatabase *_gdb;
}

- (void)setUp {
    [super setUp];
    // Skip the BETA-only integrity abort inside trySaveEncoder so this test
    // can observe the corrupt self.record via its own assertions instead of
    // dying mid-save. The bug we're demonstrating happens whether the abort
    // is on or off — the abort just turns the silent corruption into an
    // immediate crash for production diagnostics.
    setenv("ITERM2_SKIP_GRAPH_INTEGRITY_ASSERT", "1", 1);

    NSString *name = [NSString stringWithFormat:@"graph-db-recovery-%@.sqlite",
                      [[NSUUID UUID] UUIDString]];
    _url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    _db = [[iTermGraphDBRecoveryTest_FailableDatabase alloc] initWithURL:_url];
    _gdb = [[iTermGraphDatabase alloc] initWithDatabase:_db];
    XCTAssertNotNil(_gdb, @"Failed to construct iTermGraphDatabase");
    [_gdb waitUntilReady];
}

- (void)tearDown {
    _gdb = nil;
    _db = nil;
    [[NSFileManager defaultManager] removeItemAtURL:_url error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:[_url URLByAppendingPathExtension:@"wal"]
                                              error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:[_url URLByAppendingPathExtension:@"shm"]
                                              error:nil];
    _url = nil;
    [super tearDown];
}

// Walks the graph rooted at `record` and collects the path of every record
// whose rowid is nil. Returns an empty array when the tree is fully populated.
- (NSArray<NSString *> *)pathsWithNilRowids:(iTermEncoderGraphRecord *)record
                                       path:(NSString *)path {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    if (record.rowid == nil) {
        [result addObject:path];
    }
    for (iTermEncoderGraphRecord *child in record.graphRecords) {
        NSString *childPath = [NSString stringWithFormat:@"%@.%@[%@]@gen%@",
                               path, child.key, child.identifier, @(child.generation)];
        [result addObjectsFromArray:[self pathsWithNilRowids:child path:childPath]];
    }
    return result;
}

// Real-code reproduction of the recovery rowid-leak bug.
//
// Setup:
//   1. Save once successfully so self.record has a baseline leaf at
//      generation 5.
//   2. Arm the failable DB to fail the next transaction.
//   3. Save again, calling encodeChildWithKey:identifier:generation: TWICE
//      for the same (key, identifier) but with two different generations.
//      Because both calls hit iTermGraphDeltaEncoder.m's "Same key+id, new
//      generation" branch (lines 73-90), each call allocates a fresh
//      sub-encoder record. The encoder's _children array ends up with two
//      DISTINCT instances that share the same (key="leaf", identifier="1")
//      tuple.
//
// What trySaveEncoder: does on the failed save (iTermGraphDatabase.m:243-251):
//   a. Build a recovery encoder with previousRevision=nil.
//   b. encodeGraph: aliases the failed save's tree (no copy).
//   c. eraseRowIDs walks _graphRecords recursively and nils every rowid,
//      hitting BOTH duplicate instances.
//   d. attemptRecovery: deletes the file, opens a fresh DB, and replays the
//      tree as inserts via reallySave.
//
// Where the leak comes in:
//   reallySave's enumerate uses iTermOrderedDictionary byMapping: keyed on
//   (key, identifier) (iTermGraphDeltaEncoder.m:121-130) — when two siblings
//   share the same tuple, the dictionary collapses them to one entry. The
//   INSERT pass therefore visits exactly one of the two duplicates and only
//   that one gets a lastInsertRowID assigned. The other lives on in
//   self.record with rowid=nil.
//
// On the next real save iTermGraphDeltaEncoder builds with self.record as
// previousRevision, walks down to the orphaned record, and trips the
// MissingRowID @throw at iTermGraphDatabase.m:376 — which is the crash this
// user hit on the May 3 nightly.
- (void)testRecoveryWithDuplicateKeyIdentifierLeavesNilRowid {
    // 1. Baseline save establishes self.record with a leaf at generation 5.
    [_gdb updateSynchronously:YES
                        block:^(iTermGraphEncoder * _Nonnull encoder) {
        [encoder encodeChildWithKey:@"leaf"
                         identifier:@"1"
                         generation:5
                              block:^BOOL(iTermGraphEncoder * _Nonnull sub) {
            [sub encodeString:@"v1" forKey:@"key"];
            return YES;
        }];
    }
                   completion:nil];

    iTermEncoderGraphRecord *baselineLeaf =
        [_gdb.record childRecordWithKey:@"leaf" identifier:@"1"];
    XCTAssertNotNil(baselineLeaf.rowid,
                    @"Baseline save should produce a leaf with a rowid");

    // 2 + 3. Arm the failure and emit two encodeChild calls with the same
    // (key, identifier) but different generations.
    _db.failNextTransaction = YES;
    [_gdb updateSynchronously:YES
                        block:^(iTermGraphEncoder * _Nonnull encoder) {
        [encoder encodeChildWithKey:@"leaf"
                         identifier:@"1"
                         generation:6
                              block:^BOOL(iTermGraphEncoder * _Nonnull sub) {
            [sub encodeString:@"v2a" forKey:@"key"];
            return YES;
        }];
        [encoder encodeChildWithKey:@"leaf"
                         identifier:@"1"
                         generation:7
                              block:^BOOL(iTermGraphEncoder * _Nonnull sub) {
            [sub encodeString:@"v2b" forKey:@"key"];
            return YES;
        }];
    }
                   completion:nil];

    // After recovery, every record reachable from self.record should have a
    // rowid. With the bug, exactly one of the duplicate "leaf"/"1" siblings
    // is left at rowid=nil because the byMapping-based enumerate collapsed
    // it out of the INSERT pass.
    iTermEncoderGraphRecord *root = _gdb.record;
    XCTAssertNotNil(root, @"self.record is nil after recovery");

    NSArray<NSString *> *nilPaths =
        [self pathsWithNilRowids:root path:@"root"];
    XCTAssertEqualObjects(nilPaths, @[],
                          @"BUG: recovery published self.record with %lu "
                          @"nil-rowid record(s) at: %@. "
                          @"eraseRowIDs nilled both duplicates, but "
                          @"reallySave's enumerate walked them through "
                          @"iTermOrderedDictionary byMapping which collapsed "
                          @"them to one entry — the other was missed by the "
                          @"INSERT pass.",
                          (unsigned long)nilPaths.count,
                          [nilPaths componentsJoinedByString:@", "]);
}

@end
