//
//  iTermGraphDatabase.m
//  iTerm2
//
//  Created by George Nachman on 7/27/20.
//

#import "iTermGraphDatabase.h"

#import "DebugLogging.h"
#import "FMDatabase.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermGraphDeltaEncoder.h"
#import "iTermGraphTableTransformer.h"
#import "iTermPromise.h"
#import "iTermThreadSafety.h"
#import <stdatomic.h>

@class iTermGraphDatabaseState;

@interface iTermGraphDatabaseState: iTermSynchronizedState<iTermGraphDatabaseState *>
@property (nonatomic, strong) id<iTermDatabase> db;

- (instancetype)initWithQueue:(dispatch_queue_t)queue database:(id<iTermDatabase>)db;
@end

@implementation iTermGraphDatabaseState

- (instancetype)initWithQueue:(dispatch_queue_t)queue database:(id<iTermDatabase>)db {
    self = [super initWithQueue:queue];
    if (self) {
        _db = db;
    }
    return self;
}

@end

@interface iTermGraphDatabase()
@property (atomic, readwrite) iTermEncoderGraphRecord *record;
@end

@implementation iTermGraphDatabase {
    NSInteger _recoveryCount;
    _Atomic int _updating;
    _Atomic int _invalid;

    // Load complete means that the initial attempt to load the DB has finished. It may have failed, leaving
    // us without any state, but it is now safe to proceed to use the graph DB as it won't change out
    // from under you after this point.
    // There is no promised value. This is just used as a barrier.
    iTermPromise *_loadCompletePromise;
    iTermCyclicLog *_log;
}

- (instancetype)initWithDatabase:(id<iTermDatabase>)db {
    self = [super init];
    if (self) {
        if (![db lock]) {
            DLogCyclic(_log, @"Could not acquire lock. Give up.");
            return nil;
        }
        _log = [[iTermCyclicLog alloc] init];
        _updating = ATOMIC_VAR_INIT(0);
        _invalid = ATOMIC_VAR_INIT(0);
        _thread = [[iTermThread alloc] initWithLabel:@"com.iterm2.graph-db"
                                        stateFactory:^iTermSynchronizedState * _Nonnull(dispatch_queue_t  _Nonnull queue) {
            return [[iTermGraphDatabaseState alloc] initWithQueue:queue
                                                         database:db];
        }];

        _url = [db url];
        _loadCompletePromise = [iTermPromise promise:^(id<iTermPromiseSeal>  _Nonnull seal) {
            [_thread dispatchAsync:^(iTermGraphDatabaseState *state) {
                [self finishInitialization:state];
                [seal fulfill:[NSNull null]];
            }];
        }];
    }
    return self;
}

- (void)doHousekeeping {
    [_thread dispatchAsync:^(iTermGraphDatabaseState *state) {
        // PRAGMA returns a result set, so we must use executeQuery and close it
        FMResultSet *rs = [state.db executeQuery:@"pragma wal_checkpoint"];
        [rs close];
        [state.db executeUpdate:@"vacuum"];
    }];
}

- (void)finishInitialization:(iTermGraphDatabaseState *)state {
    if ([self reallyFinishInitialization:state]) {
        return;
    }
    // Failed.
    [state.db unlock];
    state.db = nil;
    _invalid = YES;
}

- (BOOL)reallyFinishInitialization:(iTermGraphDatabaseState *)state {
    if (![self openAndInitializeDatabase:state]) {
        DLogCyclic(_log, @"openAndInitialize failed. Attempt recovery.");
        return [self attemptRecovery:state encoder:nil];
    }
    DLogCyclic(_log, @"Opened ok.");

    NSError *error = nil;
    self.record = [self load:state error:&error];
    if (error) {
        DLogCyclic(_log, @"load failed. Attempt recovery. %@", error);
        return [self attemptRecovery:state encoder:nil];
    }
    DLogCyclic(_log, @"Loaded ok. Root record: key=%@ id=%@ gen=%@ rowid=%@",
               self.record.key, self.record.identifier, @(self.record.generation), self.record.rowid);

    return YES;
}

// NOTE: It is critical that the completion block not be called synchronously.
- (BOOL)updateSynchronously:(BOOL)sync
                      block:(void (^ NS_NOESCAPE)(iTermGraphEncoder * _Nonnull))block
                 completion:(nullable iTermCallback *)completion {
    DLogCyclic(_log, @"updateSynchronously:%@", @(sync));
    assert([NSThread isMainThread]);
    if (_invalid) {
        DLogCyclic(_log, @"Invalid, so fail");
        [completion invokeWithObject:@NO];
        return YES;
    }
    if (self.updating && !sync) {
        DLogCyclic(_log, @"Already updating and asynchronous, do nothing.");
        return NO;
    }
    DLogCyclic(_log, @"beginUpdate");
    [self beginUpdate];
    // You have to wait for loading to complete before initializing the delta encoder or you can end
    // up with two root nodes when a second instance of iTerm2 just quit and this races against loading.
    [_loadCompletePromise wait];
    DLogCyclic(_log, @"Creating encoder. self.record: key=%@ id=%@ rowid=%@ ptr=%p",
               self.record.key, self.record.identifier, self.record.rowid, self.record);
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:self.record];
    block(encoder);
    __weak __typeof(self) weakSelf = self;

    iTermCyclicLog *log = _log;
    void (^perform)(iTermGraphDatabaseState *) = ^(iTermGraphDatabaseState *state) {
        DLogCyclic(log, @"Perform weakSelf=%@", weakSelf);
        if (!self->_invalid) {
            [weakSelf trySaveEncoder:encoder state:state completion:completion];
        }
        DLogCyclic(log, @"endUpdate");
        [weakSelf endUpdate];
    };
    if (sync) {
        DLogCyclic(_log, @"dispatch sync");
        [_thread dispatchSync:perform];
    } else {
        DLogCyclic(_log, @"dispatch async");
        [_thread dispatchAsync:perform];
    }
    return YES;
}

- (void)invalidateSynchronously:(BOOL)sync {
    if (sync) {
        [_thread dispatchSync:^(iTermGraphDatabaseState *_Nullable state) {
            [self reallyInvalidate:state];
        }];
    } else {
        [_thread dispatchAsync:^(iTermGraphDatabaseState *_Nullable state) {
            [self reallyInvalidate:state];
        }];
    }
}

- (void)reallyInvalidate:(iTermGraphDatabaseState *)state {
    _invalid = YES;
    [state.db executeUpdate:@"delete from Node"];
    [state.db close];
    state.db = nil;
}

- (void)whenReady:(void (^)(void))readyBlock {
    [_loadCompletePromise onQueue:dispatch_get_main_queue() then:^(id value){ readyBlock(); }];
}

#pragma mark - Private

// any queue
- (BOOL)updating {
    return _updating > 0;
}

// any queue
- (void)beginUpdate {
    _updating++;
}

// any queue
- (void)endUpdate {
    _updating--;
}

// This will mutate encoder.record.
// NOTE: It is critical that the completion block not be called synchronously.
- (void)trySaveEncoder:(iTermGraphDeltaEncoder *)originalEncoder
                 state:(iTermGraphDatabaseState *)state
            completion:(nullable iTermCallback *)completion {
    DLogCyclic(_log, @"trySaveEncoder");
    iTermGraphDeltaEncoder *encoder = originalEncoder;
    BOOL ok = YES;
    @try {
        if (!state.db) {
            ok = NO;
            DLogCyclic(_log, @"I have no db");
            return;
        }
        if ([self save:encoder state:state]) {
            _recoveryCount = 0;
            DLogCyclic(_log, @"Save succeeded");
            return;
        }

        DLogCyclic(_log, @"save failed: %@ with recovery count %@", state.db.lastError, @(_recoveryCount));
        if (_recoveryCount >= 3) {
            DLogCyclic(_log, @"Not attempting recovery.");
            ok = NO;
            return;
        }
        _recoveryCount += 1;
        DLogCyclic(_log, @"Starting recovery attempt %@. originalEncoder.record rowid=%@ ptr=%p",
                   @(_recoveryCount), originalEncoder.record.rowid, originalEncoder.record);
        // For recovery, create a fresh encoder with no previous revision.
        // This treats everything as inserts, avoiding the need for valid rowIDs in "before" state.
        encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:nil];
        [encoder encodeGraph:originalEncoder.record];
        DLogCyclic(_log, @"Recovery: After encodeGraph, encoder.record rowid=%@ ptr=%p children=%@",
                   encoder.record.rowid, encoder.record, @(encoder.record.graphRecords.count));
        // Erase rowIDs from the recovery encoder's record since we're treating everything as inserts.
        // The "after" records will get new rowIDs assigned during the insert.
        [encoder.record eraseRowIDs];
        DLogCyclic(_log, @"Recovery: After eraseRowIDs, encoder.record rowid=%@ (should be nil)",
                   encoder.record.rowid);
        ok = [self attemptRecovery:state encoder:encoder];
        DLogCyclic(_log, @"Recovery attempt %@ result: %@", @(_recoveryCount), @(ok));
    } @catch (NSException *exception) {
        NSString *description = [NSString stringWithFormat:@"%@:\n%@\n%@",
                                 exception.name,
                                 exception.reason,
                                 [exception.it_originalCallStackSymbols componentsJoinedByString:@"\n"]];
        DLogCyclic(_log, @"Exception: %@", description);
        [_log fatalError];
        ok = NO;
    } @finally {
        [completion invokeWithObject:@(ok)];
        if (ok) {
            // If we were able to save, then use this record as the new baseline. Note that we
            // very carefully take it from encoder, not originalEncoder, because regardless of
            // whether a recovery was attempted `encoder.record` has the correct rowids.
            DLogCyclic(_log, @"Save succeeded. Setting self.record from encoder.record: rowid=%@ ptr=%p",
                       encoder.record.rowid, encoder.record);
            self.record = encoder.record;
        } else {
            // Recovery failed. Clear self.record so the next save attempt won't have a corrupted
            // "before" state with missing rowIDs.
            DLogCyclic(_log, @"Save failed. Clearing self.record (was ptr=%p rowid=%@)",
                       self.record, self.record.rowid);
            self.record = nil;
        }
        // Uncomment to debug missing rowIDs
        // [self assertRecordIntegrity:self.record];
    }
}

- (void)assertRecordIntegrity:(iTermEncoderGraphRecord *)record {
    if (!record) {
        return;
    }
    ITAssertWithMessage(record.rowid != nil, @"Record missing rowid: %@", record);
    for (iTermEncoderGraphRecord *child in record.graphRecords) {
        [self assertRecordIntegrity:child];
    }
}

// On failure, the db will be closed.
- (BOOL)attemptRecovery:(iTermGraphDatabaseState *)state
                encoder:(iTermGraphDeltaEncoder *)encoder {
    if (!state.db) {
        return NO;
    }
    // Close and unlink the old database.
    [state.db close];
    [state.db unlink];

    // Save the URL before releasing the old instance.
    NSURL *url = [state.db url];

    // Release the advisory lock from the old instance before creating a new one.
    [state.db unlock];

    // Create a brand new FMDatabase instance to avoid any corrupted state from
    // the old instance (especially if files were externally moved while open).
    state.db = [[iTermSqliteDatabaseImpl alloc] initWithURL:url];

    // Acquire the lock with the new instance.
    if (![state.db lock]) {
        DLogCyclic(_log, @"Failed to acquire lock after recovery.");
        return NO;
    }

    // Open and initialize the fresh database.
    if (![self openAndInitializeDatabase:state]) {
        DLogCyclic(_log, @"Failed to open and initialize datbase after deleting it.");
        return NO;
    }
    if (!encoder) {
        DLogCyclic(_log, @"Opened database after deleting it. There is no record to save.");
        return YES;
    }
    DLogCyclic(_log, @"Save record after deleting and creating database.");
    const BOOL ok = [self save:encoder state:state];
    if (!ok) {
        [state.db close];
        return NO;
    }
    return YES;
}

- (BOOL)save:(iTermGraphDeltaEncoder *)encoder
       state:(iTermGraphDatabaseState *)state {
    DLogCyclic(_log, @"save");
    assert(state.db);

    const BOOL ok = [state.db transaction:^BOOL{
        return [self reallySave:encoder state:state];
    }];
    if (!ok) {
        DLogCyclic(_log, @"Commit transaction failed: %@", state.db.lastError);
    }
    return ok;
}

// Runs within a transaction.
- (BOOL)reallySave:(iTermGraphDeltaEncoder *)encoder
             state:(iTermGraphDatabaseState *)state {
    DLog(@"Start saving");
    NSDate *start = [NSDate date];
    const BOOL ok =
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSNumber *parent,
                                NSString *path,
                                BOOL *stop) {
        if (before && !before.rowid) {
            NSString *reason = [NSString stringWithFormat:@"MissingRowID: Before lacking a rowid! path=%@ before: key=%@ id=%@ gen=%@ ptr=%p after: key=%@ id=%@ gen=%@ rowid=%@ ptr=%p",
                                path,
                                before.key,
                                before.identifier,
                                @(before.generation),
                                before,
                                after.key,
                                after.identifier,
                                @(after.generation),
                                after.rowid,
                                after];
            @throw [NSException exceptionWithName:@"MissingRowID"
                                           reason:reason
                                         userInfo:nil];
        }
        if (before && !after) {
            if (![state.db executeUpdate:@"delete from Node where rowid=?", before.rowid]) {
                *stop = YES;
                return;
            }
            return;
        }
        if (!before && after) {
            if (![state.db executeUpdate:@"insert into Node (key, identifier, parent, data) values (?, ?, ?, ?)",
                  after.key, after.identifier, parent, after.data ?: [NSData data]]) {
                *stop = YES;
                return;
            }
            NSNumber *lastInsertRowID = state.db.lastInsertRowId;
            if (parent.integerValue == 0) {
                DLog(@"Insert root node with path %@, rowid %@", path, lastInsertRowID);
            }
            assert(lastInsertRowID);
            @try {
                // Issue 9117
                after.rowid = lastInsertRowID;
            } @catch (NSException *exception) {
                @throw [exception it_rethrowWithMessage:@"after.key=%@ after.identifier=%@", after.key, after.identifier];
            }
            return;
        }
        if (before && after) {
            if (before.parent == nil) {
                DLog(@"Updating root with path %@, rowid %@", path, before.rowid);
            }
            if (after.rowid == nil) {
                after.rowid = before.rowid;
            } else {
                if (before.generation == after.generation &&
                    after.generation != iTermGenerationAlwaysEncode) {
                    DLog(@"Don't update rowid %@ %@[%@] because it is unchanged", before.rowid, after.key, after.identifier);
                    return;
                }
            }
            assert(before.rowid.longLongValue == after.rowid.longLongValue);
            if ([before.data isEqual:after.data]) {
                return;
            }
            if (![state.db executeUpdate:@"update Node set data=? where rowid=?", after.data, before.rowid]) {
                *stop = YES;
            }
            return;
        }
        assert(NO);
    }];
    NSDate *end = [NSDate date];
    DLogCyclic(_log, @"Save result=%@ duration=%.1fms",
               @(ok), (end.timeIntervalSinceNow - start.timeIntervalSinceNow) * 1000);
    return ok;
}

- (BOOL)createTables:(iTermGraphDatabaseState *)state {
    // PRAGMA returns a result set, so we must use executeQuery and close it explicitly
    FMResultSet *rs = [state.db executeQuery:@"PRAGMA journal_mode=WAL"];
    [rs close];

    if (![state.db executeUpdate:@"create table if not exists Node (key text not null, identifier text not null, parent integer not null, data blob)"]) {
        return NO;
    }
    [state.db executeUpdate:@"create index if not exists parent_index on Node (parent)"];

    // Delete nodes without parents.
    [state.db executeUpdate:
     @"delete from Node where "
     @"  rowid in ("
     @"    select child.rowid as id "
     @"      from "
     @"        Node as child"
     @"        left join "
     @"          Node as parentNode "
     @"          on parentNode.rowid = child.parent "
     @"      where "
     @"        parentNode.rowid is NULL and "
     @"        child.parent != 0"
     @"  )"];
    return YES;
}

// If this returns YES, the database is open and has the expected tables.
- (BOOL)openAndInitializeDatabase:(iTermGraphDatabaseState *)state {
    if (![state.db open]) {
        return NO;
    }

    if (![self createTables:state]) {
        DLogCyclic(_log, @"Create table failed: %@", state.db.lastError);
        [state.db close];
        return NO;
    }
    return YES;
}

- (iTermEncoderGraphRecord * _Nullable)load:(iTermGraphDatabaseState *)state
                                      error:(out NSError **)error {
    DLog(@"load");
    NSMutableArray<NSArray *> *nodes = [NSMutableArray array];
    {
        DLog(@"select from Node...");
        FMResultSet *rs = [state.db executeQuery:@"select key, identifier, parent, rowid, data from Node"];
        while ([rs next]) {
            DLog(@"Read row");
            [nodes addObject:@[ [rs stringForColumn:@"key"],
                                [rs stringForColumn:@"identifier"],
                                @([rs longLongIntForColumn:@"parent"]),
                                @([rs longLongIntForColumn:@"rowid"]),
                                [rs dataForColumn:@"data"] ?: [NSData data] ]];
        }
        DLog(@"Select done");
        [rs close];
    }

    DLog(@"Begin transforming");
    iTermGraphTableTransformer *transformer = [[iTermGraphTableTransformer alloc] initWithNodeRows:nodes];
    iTermEncoderGraphRecord *record = transformer.root;
    DLog(@"Done transforming");

    if (!record) {
        if (error) {
            *error = transformer.lastError;
        }
        return nil;
    }

    return record;
}

@end

